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
