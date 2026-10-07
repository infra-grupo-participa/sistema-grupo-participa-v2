-- 20261007153421_ensaio.sql (escrito como 20261007y) — ensaio da 20261007153421_crm_realtime_caixa em transação DESFEITA (termina em ROLLBACK;
-- o DO final ainda levanta exceção com o resultado, então nada é gravado mesmo se o cliente não mandar o rollback).
-- Esperado:
--   upd_noop = 0  (update sem mudança visível não avisa)
--   upd_status = 1 (mudou erro/status → 1 aviso, mesmo com N linhas)
--   ins = 1        (insert de mensagem → 1 aviso)
--   conv_noop = 0, conv_lidas = 1
--   payload sem dado pessoal: {"t": "...", "id": <uuid do aviso>}
--   RLS: comercial vê os avisos de crm:caixa (>0); usuário fora do Comercial = 0; comercial em outro tópico = 0;
--   anon = 0
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
-- 20261007y_crm_realtime_caixa.sql
-- Aviso em tempo real da caixa do WhatsApp do CRM (Supabase Realtime, Broadcast em canal PRIVADO "crm:caixa").
-- O banco só avisa "mudou" (payload {t: <tabela>}, sem id de pessoa nem dado pessoal); a tela recarrega pelas RPCs
-- de sempre (crm_conversas / crm_mensagens), que aplicam as permissões. postgres_changes não serve: o schema crm
-- não é exposto e não está na publication.
--   • Triggers por COMANDO (for each statement) com transition tables: lote = 1 aviso; update sem mudança visível
--     (retentativa da fila, proxima_tentativa_em…) não avisa.
--   • Policy em realtime.messages: só ouve "crm:caixa" quem é do Comercial (crm.eh_comercial()). Nenhuma policy de
--     INSERT: cliente não publica no tópico.
--   • realtime.send já engole erro (WARNING) e o bloco exception daqui também: a gravação principal nunca cai.
-- Kill-switch: alter table crm.mensagem disable trigger rt_caixa_ins; … disable trigger rt_caixa_upd;
--              alter table crm.conversa disable trigger rt_caixa_upd;  (a tela segue pela busca periódica)
do $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then raise exception 'premissa: realtime.send ausente'; end if;
  if to_regprocedure('crm.eh_comercial()') is null then raise exception 'premissa: crm.eh_comercial ausente'; end if;
  if exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages' and policyname = 'crm_caixa_ouvir') then
    raise exception 'premissa: policy crm_caixa_ouvir já existe';
  end if;
  if exists (select 1 from pg_trigger where tgname like 'rt_caixa_%' and tgrelid in ('crm.mensagem'::regclass, 'crm.conversa'::regclass)) then
    raise exception 'premissa: triggers rt_caixa_* já existem';
  end if;
end $$;

create function crm.tg_rt_caixa()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_mudou boolean := false;
begin
  begin
    if tg_table_name = 'mensagem' and tg_op = 'INSERT' then
      v_mudou := exists (select 1 from novas);
    elsif tg_table_name = 'mensagem' then
      -- só o que a tela mostra (crm.mensagem_json) ou a conversa a que pertence
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.status, n.lida_em, n.erro, n.texto, n.tipo, n.em, n.pessoa_id, n.autor_id, n.template_id,
                n.midia_status, n.midia_caminho, n.midia_mime, n.midia_tamanho, n.midia_nome)
               is distinct from
               (o.status, o.lida_em, o.erro, o.texto, o.tipo, o.em, o.pessoa_id, o.autor_id, o.template_id,
                o.midia_status, o.midia_caminho, o.midia_mime, o.midia_tamanho, o.midia_nome));
    elsif tg_table_name = 'conversa' then
      -- contador de não lidas (marcar como lida em outra tela) e unificação de pessoa
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.nao_lidas, n.pessoa_id) is distinct from (o.nao_lidas, o.pessoa_id));
    end if;
    if v_mudou then
      perform realtime.send(jsonb_build_object('t', tg_table_name), 'mudou', 'crm:caixa', true);
    end if;
  exception when others then
    raise warning 'crm.tg_rt_caixa: %', sqlerrm;
  end;
  return null;
end $$;
revoke execute on function crm.tg_rt_caixa() from public, anon, authenticated;

create trigger rt_caixa_ins after insert on crm.mensagem
  referencing new table as novas for each statement execute function crm.tg_rt_caixa();
create trigger rt_caixa_upd after update on crm.mensagem
  referencing old table as velhas new table as novas for each statement execute function crm.tg_rt_caixa();
create trigger rt_caixa_upd after update on crm.conversa
  referencing old table as velhas new table as novas for each statement execute function crm.tg_rt_caixa();

create policy crm_caixa_ouvir on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'crm:caixa'
    and coalesce((select crm.eh_comercial()), false)
  );

do $$
declare
  r jsonb := '{}';
  n0 int; n1 int;
  v_msg uuid; v_conv uuid;
  v_com text; v_fora text;
  t0 timestamptz;
begin
  select id into v_msg from crm.mensagem order by em desc limit 1;
  select id into v_conv from crm.conversa order by ultima_em desc nulls last limit 1;
  v_com := (select p.id::text from public.perfis p where p.status = 'ativo' and p.cargo in ('dev', 'admin') limit 1);
  v_fora := (select u.id::text from auth.users u where not exists (select 1 from public.perfis p where p.id = u.id) limit 1);
  if v_msg is null or v_conv is null or v_com is null or v_fora is null then raise exception 'ensaio sem massa'; end if;

  select count(*) into n0 from realtime.messages where topic = 'crm:caixa';

  update crm.mensagem set status = status where id = v_msg;
  select count(*) into n1 from realtime.messages where topic = 'crm:caixa';
  r := r || jsonb_build_object('upd_noop', n1 - n0); n0 := n1;

  update crm.mensagem set erro = coalesce(erro, '') || ' [ensaio]';      -- todas as linhas, um comando
  select count(*) into n1 from realtime.messages where topic = 'crm:caixa';
  r := r || jsonb_build_object('upd_status', n1 - n0, 'linhas', (select count(*) from crm.mensagem)); n0 := n1;

  insert into crm.mensagem (id, conversa_id, pessoa_id, direcao, tipo, texto, em, status)
  select gen_random_uuid(), conversa_id, pessoa_id, 'entrada', 'texto', 'ensaio', now(), null from crm.mensagem where id = v_msg;
  select count(*) into n1 from realtime.messages where topic = 'crm:caixa';
  r := r || jsonb_build_object('ins', n1 - n0); n0 := n1;

  update crm.conversa set criado_em = criado_em where id = v_conv;
  select count(*) into n1 from realtime.messages where topic = 'crm:caixa';
  r := r || jsonb_build_object('conv_noop', n1 - n0); n0 := n1;

  update crm.conversa set nao_lidas = nao_lidas + 1 where id = v_conv;
  select count(*) into n1 from realtime.messages where topic = 'crm:caixa';
  r := r || jsonb_build_object('conv_lidas', n1 - n0); n0 := n1;

  r := r || jsonb_build_object('payloads', (select jsonb_agg(distinct (payload - 'id')) from realtime.messages where topic = 'crm:caixa'),
                               'chaves', (select jsonb_agg(distinct k) from realtime.messages, jsonb_object_keys(payload) k where topic = 'crm:caixa'));

  -- RLS (como o Realtime autoriza: role authenticated + claims + realtime.topic)
  perform set_config('realtime.topic', 'crm:caixa', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_com, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  r := r || jsonb_build_object('rls_comercial', (select count(*) from realtime.messages));
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_fora, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  r := r || jsonb_build_object('rls_fora', (select count(*) from realtime.messages));
  execute 'reset role';
  perform set_config('realtime.topic', 'outro:topico', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_com, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  r := r || jsonb_build_object('rls_outro_topico', (select count(*) from realtime.messages));
  execute 'reset role';
  perform set_config('realtime.topic', 'crm:caixa', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  r := r || jsonb_build_object('rls_anon', (select count(*) from realtime.messages));
  execute 'reset role';

  r := r || jsonb_build_object('acl_tg', (select proacl::text from pg_proc where oid = 'crm.tg_rt_caixa()'::regprocedure));

  -- custo do trigger num update de lote (todas as mensagens)
  t0 := clock_timestamp();
  update crm.mensagem set erro = coalesce(erro, '') || '.';
  r := r || jsonb_build_object('ms_update_lote', round(extract(epoch from clock_timestamp() - t0) * 1000, 2));

  raise exception 'RESULTADO_ENSAIO %', r;
end $$;
rollback;
