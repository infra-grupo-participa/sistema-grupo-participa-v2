-- Ensaio de 20261008230000 (fila do webhook do CRM). UMA transação, desfeita no rollback: aplica a migration inteira
-- (texto idêntico ao arquivo, colado abaixo) e roda T1..T11. Eventos sintéticos com e-mail @exemplo.invalid; a saída
-- só tem contagens e o JSON de resposta das funções (sem e-mail, sem token: o token é lido do Vault dentro do SQL).
-- Esperado: todas as linhas com ok = true. Rodar pela Management API (/database/query) com o arquivo lido em utf-8.
begin;
-- ═══ MIGRATION (cópia literal de 20261008230000_crm_integracao_fila.sql) ═══
-- 20261008230000: CRM, fila do webhook de integrações (ActiveCampaign, Unnichat, SendFlow)
--
-- STATUS: NÃO APLICADA. Ensaio: 20261008230000_ensaio.sql (begin … rollback). Medição e 5 perguntas:
-- 20261008230000.explain.md. Reversão: 20261008230000_reversao.sql. Aplicar com a Edge crm-integracao-webhook do mesmo
-- ramo (fix/crm-webhook-fila); a ordem não importa (a RPC mantém nome, assinatura e grants).
--
-- POR QUE (incidente 08/10/2026 20:04–20:10 e 20:24–20:28 UTC): o ActiveCampaign mandou ~38 mil webhooks distintos em
--   6 min (~100/s). Cada um chamava public.crm_integracao_receber, que fazia TODO o trabalho na hora (Vault, insert em
--   crm.evento_jornada com 6 gatilhos, crm.anexar_integracao com advisory lock por e-mail, pessoas.registrar,
--   crm.garantir_pc). O pool (max_connections 60, banco de 7 sistemas) saturou: ~30 mil × 522 e banco reiniciado.
--
-- DECISÃO DE NEGÓCIO (João, 08/10): "forma sustentável, manter funcionando".
--   1. TODO evento entra na fila e é processado no ritmo do processador, nunca derrubando o banco. Nenhuma perda por
--      desenho (erro 3× vira 'descartado' e FICA na fila para reprocessar; ver o explain).
--   2. Rajada = mais de N eventos da mesma fonte recebidos no último minuto (crm.config.integracao_rajada_por_minuto,
--      padrão 300). Evento recebido em rajada é carimbado em_massa no insert: é gravado normalmente (pessoa, jornada,
--      catalogação), só a ATIVAÇÃO automática (gatilho zz_ativacao_ac → toque 1) fica suprimida.
--   3. Os eventos perdidos de 08/10 não são recuperados.
--
-- O QUE FAZ
--   a. crm.config: integracao_fila_ligada (default true: liga a fila ao aplicar; false = caminho antigo síncrono,
--      idêntico) e integracao_rajada_por_minuto (default 300). crm.config é linha única (id boolean, 1 linha): a
--      coluna nova com default não desfaz regra de vigência.
--   b. crm.integracao_fila: RLS ligada, sem policy, sem grant (só postgres). Guarda o evento normalizado (tem e-mail
--      e telefone): processado é apagado depois de 7 dias, descartado depois de 30 (até 1000 por rodada).
--   c. crm.integracao_gravar_evento: o laço ANTIGO de crm_integracao_receber (corpo vivo md5 7f3af05c…), extraído
--      sem mudar regra; usado pelo caminho síncrono e pelo processador.
--   d. public.crm_integracao_receber: mesmo prelúdio (fonte, token do Vault, 1..100 eventos). Fila ligada: só
--      enfileira (insert … on conflict do nothing), MESMO com a fonte desligada (o kill-switch por fonte vale no
--      processador). Fila desligada: caminho antigo idêntico (fonte desligada = ignorado).
--   e. crm.integracao_processar_fila(p_limite = 200): 1 processador por vez (pg_try_advisory_xact_lock), for update
--      skip locked, evento normal antes do em_massa, cada item no seu bloco begin/exception, para em 10 s de relógio.
--      57014 (timeout do cron) é capturado explicitamente: sobe tentativa e encerra a rodada (pentest 08/10).
--      Expurgo: processado 7 dias; descartado e pendente/erro parado 30 dias. Fonte desligada em crm.config fica
--      pendente (freio também do processamento).
--   f. Ativação: crm.tg_ativacao_ac (corpo vivo md5 conferido) ganha UMA condição: com crm.ativacao_suprimida = 'sim'
--      (set_config local, só o processador liga, só durante um item em_massa) não ativa. O corpo do gatilho vai para
--      crm.ativacao_ac_evento(evento), que a equipe chama para liberar a ativação de um lote (consulta no explain).
--   g. cron crm-integracao-fila, a cada minuto, com statement_timeout e lock_timeout próprios.
-- Guarda: aborta se o corpo vivo de crm_integracao_receber ou de crm.tg_ativacao_ac não for o lido em 08/10.
-- blindagem.autorizar_guarda: não exigido (nenhuma das funções está em blindagem.auditoria_funcoes; conferido).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.crm_integracao_receber(text,text,jsonb)'::regprocedure)
     is distinct from '7f3af05ca622754eab5553135ff54ded' then
    raise exception '20261008230000: corpo vivo de crm_integracao_receber mudou desde 08/10 (releia antes de aplicar)';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'crm.tg_ativacao_ac()'::regprocedure)
     is distinct from '9d96f6417d47c9022f80b4b4b17acfd1' then
    raise exception '20261008230000: corpo vivo de crm.tg_ativacao_ac mudou desde 08/10 (releia antes de aplicar)';
  end if;
  if (select count(*) from crm.config) <> 1 then
    raise exception '20261008230000: crm.config deixou de ser linha única';
  end if;
  if to_regclass('crm.integracao_fila') is not null then
    raise exception '20261008230000: crm.integracao_fila já existe';
  end if;
end
$g$;

-- ─── a. config ────────────────────────────────────────────────────────────────────────────────────────────────────
alter table crm.config
  add column integracao_fila_ligada boolean not null default true,
  add column integracao_rajada_por_minuto integer not null default 300
    constraint config_integracao_rajada_ck check (integracao_rajada_por_minuto between 10 and 100000);
comment on column crm.config.integracao_fila_ligada is
  '20261008230000: true = o webhook só enfileira (crm.integracao_fila, processada pelo cron); false = caminho síncrono antigo.';
comment on column crm.config.integracao_rajada_por_minuto is
  '20261008230000: mais que N eventos da mesma fonte no último minuto = rajada (em_massa: grava, mas não ativa).';

-- ─── b. fila ──────────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.integracao_fila (
  id              bigint generated always as identity primary key,
  fonte           text        not null check (fonte in ('activecampaign', 'unnichat', 'sendflow')),
  fonte_evento_id text        not null check (length(fonte_evento_id) between 1 and 200),
  evento          jsonb       not null check (jsonb_typeof(evento) = 'object'),
  recebido_em     timestamptz not null default now(),
  em_massa        boolean     not null default false,
  estado          text        not null default 'pendente'
                  check (estado in ('pendente', 'processado', 'erro', 'descartado')),
  tentativas      smallint    not null default 0 check (tentativas between 0 and 3),
  erro            text        check (erro ~ '^[0-9A-Z]{5}$'),   -- só o SQLSTATE: a mensagem pode ter e-mail
  processado_em   timestamptz,
  constraint integracao_fila_evento_key unique (fonte, fonte_evento_id)
);
comment on table crm.integracao_fila is
  '20261008230000: entrada do webhook de integrações. Processada por crm.integracao_processar_fila (cron a cada minuto). '
  'Tem e-mail/telefone: processado sai em 7 dias, descartado em 30.';
-- o processador lê a frente da fila: primeiro o que NÃO é rajada, depois a rajada (predicado literal repetido na
-- consulta). Sem isso, um lead normal que chega depois de 38 mil eventos de rajada esperaria ~3 h pelo toque 1.
create index integracao_fila_aberta_idx on crm.integracao_fila (em_massa, id) where estado in ('pendente', 'erro');
-- rajada (recebido no último minuto, por fonte) e expurgo (recebido há mais de 7/30 dias)
create index integracao_fila_recebido_idx on crm.integracao_fila (recebido_em, fonte);

alter table crm.integracao_fila enable row level security;
revoke all on table crm.integracao_fila from public, anon, authenticated, service_role;

-- ─── c. o laço antigo, extraído (regra idêntica; p_recebido_em = now() no caminho síncrono) ─────────────────────────
-- Devolve: 'invalido' | 'duplicado' | resultado de crm.anexar_integracao | 'falhou' (casamento deu erro: o evento fica
-- gravado com resultado 'pendente', como antes).
create function crm.integracao_gravar_evento(p_fonte text, p_evento jsonb, p_recebido_em timestamptz)
returns text
language plpgsql
set search_path = ''
as $f$
declare
  e jsonb := p_evento; v_id bigint; v_res text; v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
  begin
    v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, p_recebido_em);
  exception when others then v_quando := null;
  end;
  if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
     or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > p_recebido_em + interval '1 day' then
    return 'invalido';
  end if;
  v_utm := jsonb_strip_nulls(jsonb_build_object(
             'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
             'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
  insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, recebido_em, email_norm, fone_key, nome, lista, tag, dados)
  values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando, p_recebido_em,
          pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
          nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
          nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
          case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
  on conflict (fonte, fonte_evento_id) do nothing
  returning id into v_id;
  if v_id is null then return 'duplicado'; end if;
  -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
  begin
    -- 20261007a: só o AC leva o telefone (cria/completa a pessoa); o número não é gravado no evento
    v_res := crm.anexar_integracao(v_id, case when p_fonte = 'activecampaign' then left(e ->> 'telefone', 40) end);
  exception when others then
    raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    return 'falhou';
  end;
  return coalesce(v_res, 'falhou');
end
$f$;
revoke all on function crm.integracao_gravar_evento(text, jsonb, timestamptz) from public, anon, authenticated, service_role;

-- ─── d. a RPC do webhook (mesma assinatura: create or replace mantém o grant postgres + service_role) ──────────────
create or replace function public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ligado boolean; v_seg text; e jsonb; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0; v_criadas int := 0;
  v_fila boolean; v_rajada int; v_massa boolean; v_validos int; v_enf int;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end,
         c.integracao_fila_ligada, c.integracao_rajada_por_minuto
    into v_ligado, v_fila, v_rajada from crm.config c;
  -- 20261008230000 (João, 08/10): com a fila ligada, ENFILEIRA mesmo com a fonte desligada. O kill-switch por fonte
  -- passa a valer no processador (o item fica pendente; o expurgo apaga o parado há 30 dias). Token conferido acima.
  -- Rajada = já havia N ou mais da mesma fonte no último minuto.
  if coalesce(v_fila, false) then
    if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
      return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
    end if;
    select count(*) >= v_rajada into v_massa
      from (select 1 from crm.integracao_fila f
             where f.recebido_em > now() - interval '1 minute' and f.fonte = p_fonte
             limit v_rajada) r;
    insert into crm.integracao_fila (fonte, fonte_evento_id, evento, em_massa)
    select p_fonte, btrim(x ->> 'id'), x, v_massa
      from jsonb_array_elements(p_eventos) x
     where jsonb_typeof(x) = 'object' and nullif(btrim(coalesce(x ->> 'id', '')), '') is not null
       and length(x ->> 'id') <= 200
    on conflict (fonte, fonte_evento_id) do nothing;
    get diagnostics v_enf = row_count;
    select count(*) into v_validos
      from jsonb_array_elements(p_eventos) x
     where jsonb_typeof(x) = 'object' and nullif(btrim(coalesce(x ->> 'id', '')), '') is not null
       and length(x ->> 'id') <= 200;
    return jsonb_build_object('ok', true, 'autorizado', true, 'enfileirados', v_enf, 'duplicados', v_validos - v_enf,
                              'invalidos', jsonb_array_length(p_eventos) - v_validos, 'em_massa', v_massa);
  end if;

  -- caminho antigo (fila desligada): mesma ordem de antes (desligado → ignorado; 1..100) e o mesmo laço, agora em
  -- crm.integracao_gravar_evento
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_res := crm.integracao_gravar_evento(p_fonte, e, now());
    if v_res = 'invalido' then v_inval := v_inval + 1; continue; end if;
    if v_res = 'duplicado' then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    if v_res in ('anexado', 'pessoa_criada') then v_anex := v_anex + 1; end if;
    if v_res = 'pessoa_criada' then v_criadas := v_criadas + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'pessoas_criadas', v_criadas, 'invalidos', v_inval);
end
$function$;

-- ─── f. ativação: o corpo do gatilho vira função (para liberar lote em_massa) + a supressão ───────────────────────
-- Corpo idêntico ao bloco interno do crm.tg_ativacao_ac vivo. Devolve o resultado de crm.ativacao_entrar
-- ('negocio_criado', 'duplicado', 'projeto_fechado', …), 'sem_projeto', ou 'erro:<sqlstate>'.
create function crm.ativacao_ac_evento(p_ev crm.evento_jornada)
returns text
language plpgsql
set search_path = ''
as $f$
declare v_dados jsonb; v_proj text; v_res text;
begin
  begin
    v_dados := jsonb_strip_nulls(jsonb_build_object('tipo', p_ev.tipo, 'lista', nullif(nullif(btrim(coalesce(p_ev.lista, '')), ''), '0'),
                                                    'tag', nullif(btrim(coalesce(p_ev.tag, '')), ''), 'utm', p_ev.dados -> 'utm',
                                                    'eventoId', p_ev.id));
    v_proj := crm.projeto_do_evento('activecampaign', v_dados);
    if v_proj is null then return 'sem_projeto'; end if;
    v_res := crm.ativacao_entrar(v_proj, p_ev.pessoa_id, 'activecampaign', 'ej-' || p_ev.id, crm.mql_do_evento('activecampaign', v_dados),
                                 case when p_ev.tipo = 'subscribe' then 'inscrição na lista ' || coalesce(p_ev.lista, '?')
                                      else 'tag ' || coalesce(p_ev.tag, '?') end);
  exception when others then
    raise warning 'crm.tg_ativacao_ac: evento % (%)', p_ev.id, sqlstate;   -- nunca derruba o webhook; sem sqlerrm (pode ter e-mail)
    return 'erro:' || sqlstate;
  end;
  return v_res;
end
$f$;
revoke all on function crm.ativacao_ac_evento(crm.evento_jornada) from public, anon, authenticated, service_role;

create or replace function crm.tg_ativacao_ac()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return null; end if;
  -- 20261008230000: evento recebido em rajada (crm.integracao_fila.em_massa) é gravado, mas não ativa.
  -- Só crm.integracao_processar_fila liga este sinal, local à transação e só durante o item em_massa.
  if current_setting('crm.ativacao_suprimida', true) = 'sim' then return null; end if;
  perform crm.ativacao_ac_evento(new);
  return null;
end
$f$;

-- ─── e. o processador ─────────────────────────────────────────────────────────────────────────────────────────────
create function crm.integracao_processar_fila(p_limite integer default 200)
returns jsonb
language plpgsql
set search_path = ''
as $f$
declare
  v_ini timestamptz := clock_timestamp();
  v_lim int := least(greatest(coalesce(p_limite, 1), 1), 1000);
  r record; v_res text;
  v_ok int := 0; v_inval int := 0; v_err int := 0; v_desc int := 0; v_exp int := 0; v_n int;
  v_ac boolean; v_un boolean; v_sf boolean; v_parar boolean := false;
begin
  if not pg_try_advisory_xact_lock(hashtext('crm.integracao_processar_fila')) then
    return jsonb_build_object('ok', true, 'ocupado', true);
  end if;

  -- expurgo: a fila guarda e-mail/telefone. Até 1000 por rodada.
  delete from crm.integracao_fila f
   where f.id in (select g.id from crm.integracao_fila g
                   where g.recebido_em < now() - interval '7 days'
                     and ((g.estado = 'processado' and g.processado_em < now() - interval '7 days')
                       or (g.estado = 'descartado' and g.recebido_em < now() - interval '30 days')
                       -- pendente/erro parado 30 dias (fonte desligada desde então): prazo também, a fila tem PII
                       or (g.estado in ('pendente', 'erro') and g.recebido_em < now() - interval '30 days'))
                   limit 1000);
  get diagnostics v_exp = row_count;

  if not exists (select 1 from crm.integracao_fila f where f.estado in ('pendente', 'erro')) then
    return jsonb_build_object('ok', true, 'processados', 0, 'expurgados', v_exp);
  end if;

  -- freio por fonte também no processamento: fonte desligada fica pendente
  select coalesce(c.activecampaign_ligado, false), coalesce(c.unnichat_ligado, false), coalesce(c.sendflow_ligado, false)
    into v_ac, v_un, v_sf from crm.config c;

  for r in
    select f.id, f.fonte, f.evento, f.recebido_em, f.em_massa, f.tentativas
      from crm.integracao_fila f
     where f.estado in ('pendente', 'erro')
       and f.fonte = any (array_remove(array[case when v_ac then 'activecampaign' end, case when v_un then 'unnichat' end,
                                             case when v_sf then 'sendflow' end], null))
     order by f.em_massa, f.id
     limit v_lim
       for update skip locked
  loop
    exit when clock_timestamp() - v_ini > interval '10 seconds';
    begin
      perform set_config('crm.ativacao_suprimida', case when r.em_massa then 'sim' else '' end, true);
      v_res := crm.integracao_gravar_evento(r.fonte, r.evento, r.recebido_em);
      perform set_config('crm.ativacao_suprimida', '', true);
      if v_res = 'invalido' then
        update crm.integracao_fila set estado = 'descartado', erro = '22023', processado_em = now() where id = r.id;
        v_inval := v_inval + 1;
      else
        update crm.integracao_fila set estado = 'processado', erro = null, processado_em = now() where id = r.id;
        v_ok := v_ok + 1;
      end if;
    exception
    when query_canceled then
      -- 57014 (statement_timeout do cron, 25 s, ou cancelamento): "when others" NÃO pega. Sem isto a rodada inteira
      -- era desfeita sem subir tentativas e o mesmo item travava a fila para sempre. Marca a tentativa e encerra a
      -- rodada (o tempo do comando já acabou); o que veio antes é gravado.
      perform set_config('crm.ativacao_suprimida', '', true);
      update crm.integracao_fila
         set tentativas = r.tentativas + 1, erro = '57014',
             estado = case when r.tentativas + 1 >= 3 then 'descartado' else 'erro' end,
             processado_em = case when r.tentativas + 1 >= 3 then now() end
       where id = r.id;
      if r.tentativas + 1 >= 3 then v_desc := v_desc + 1; else v_err := v_err + 1; end if;
      v_parar := true;
    when others then
      perform set_config('crm.ativacao_suprimida', '', true);
      update crm.integracao_fila
         set tentativas = r.tentativas + 1, erro = sqlstate,
             estado = case when r.tentativas + 1 >= 3 then 'descartado' else 'erro' end,
             processado_em = case when r.tentativas + 1 >= 3 then now() end
       where id = r.id;
      if r.tentativas + 1 >= 3 then v_desc := v_desc + 1; else v_err := v_err + 1; end if;
    end;
    exit when v_parar;
  end loop;
  perform set_config('crm.ativacao_suprimida', '', true);
  return jsonb_build_object('ok', true, 'processados', v_ok, 'invalidos', v_inval, 'erros', v_err, 'descartados', v_desc,
                            'expurgados', v_exp, 'cancelado', v_parar, 'ms', round(extract(epoch from clock_timestamp() - v_ini) * 1000));
end
$f$;
revoke all on function crm.integracao_processar_fila(integer) from public, anon, authenticated, service_role;
comment on function crm.integracao_processar_fila(integer) is
  '20261008230000: consome crm.integracao_fila (cron crm-integracao-fila, a cada minuto). Um por vez; para em 10 s.';

-- ─── g. cron ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- set dentro do comando: vale para a conexão do job (pg_cron abre uma por execução). O processador já para em 10 s;
-- o statement_timeout é o teto se um item travar; lock_timeout para não enfileirar atrás de DDL.
select cron.schedule('crm-integracao-fila', '* * * * *',
  $c$set statement_timeout = '25s'; set lock_timeout = '5s'; select crm.integracao_processar_fila();$c$);

-- ═══ TESTES (mesma transação; tudo desfeito no rollback) ═══
-- Fase A roda com a config REAL de produção (lida e gravada na saída, linha T0): hoje activecampaign_ligado = false,
-- activecampaign_cria_pessoa = false. Fase B liga SÓ a fonte (cria_pessoa continua false, como em produção).
-- Fase C liga cria_pessoa (cenário "se religarem"), rotulado. Nenhum teste muda integracao_rajada_por_minuto: a rajada
-- é provada com o N real (300), semeando 300 linhas já processadas no último minuto.
create temp table _z_out (em bigserial, passo text, ok boolean, linha text) on commit drop;
create temp table _z_ativ (evento_id bigint) on commit drop;
create temp table _z_mail (k text primary key, email text) on commit drop;
-- Instrumento: a catalogação vira "anota quem chegou à ativação e devolve null" (desfeito no rollback). Hoje há 0 linhas
-- em crm.projeto_ativacao: o caminho real terminaria em 'projeto_fechado' sem rastro observável.
create or replace function crm.projeto_do_evento(p_fonte text, p_dados jsonb) returns text
language plpgsql volatile set search_path = '' as $i$
begin insert into pg_temp._z_ativ values ((p_dados ->> 'eventoId')::bigint); return null; end $i$;
-- dois e-mails de pessoas que JÁ existem (lidos aqui dentro; não saem na saída)
insert into pg_temp._z_mail
select k, e from (select 'normal' k, 0 o union all select 'massa', 1 union all select 'antigo', 2) x
cross join lateral (select e.email_norm e from crm.evento_jornada e
                     where e.fonte = 'activecampaign' and e.email_norm is not null and e.pessoa_id is not null
                     group by e.email_norm order by max(e.id) desc offset x.o limit 1) y;

insert into pg_temp._z_out (passo, ok, linha)
select 'T0 config real de produção', true, row_to_json(c)::text
  from (select activecampaign_ligado, activecampaign_cria_pessoa, unnichat_ligado, sendflow_ligado, ativacao_ligada,
               integracao_fila_ligada, integracao_rajada_por_minuto from crm.config) c;

do $t$
declare
  tok text := (select ds.decrypted_secret from vault.decrypted_secrets ds where ds.name = 'crm_webhook_activecampaign');
  r jsonb; v_n int; v_ej int; v_id_normal bigint; v_id_massa bigint; v_lib text;
  ev_norm jsonb := jsonb_build_object('id', 'ensaio-fila-normal', 'tipo', 'subscribe', 'lista', '603',
                                      'email', (select email from pg_temp._z_mail where k = 'normal'));
  ev_massa jsonb := jsonb_build_object('id', 'ensaio-fila-massa', 'tipo', 'subscribe', 'lista', '603',
                                       'email', (select email from pg_temp._z_mail where k = 'massa'));
  ev_novo jsonb := '{"id":"ensaio-fila-novo","tipo":"subscribe","lista":"603","email":"fila.ensaio.novo@exemplo.invalid"}';
begin
  -- ══ FASE A: config real (AC desligado, cria_pessoa false) ══
  -- T1 enfileira com a fonte DESLIGADA (decisão do João) e não toca em evento_jornada
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(ev_norm, ev_novo));
  select count(*) into v_ej from crm.evento_jornada where fonte = 'activecampaign' and fonte_evento_id like 'ensaio-fila-%';
  insert into pg_temp._z_out (passo, ok, linha) values ('T1 [real] fonte desligada: enfileira', (r ->> 'enfileirados')::int = 2 and v_ej = 0
    and (r ->> 'em_massa')::boolean = false, r::text || ' evento_jornada=' || v_ej);

  -- T2 duplicado ignorado
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(ev_norm));
  insert into pg_temp._z_out (passo, ok, linha) values ('T2 [real] duplicado', (r ->> 'enfileirados')::int = 0 and (r ->> 'duplicados')::int = 1, r::text);

  -- T3 token errado recusa ANTES de tudo (nada entra)
  select count(*) into v_n from crm.integracao_fila;
  r := public.crm_integracao_receber('activecampaign', 'token-errado', jsonb_build_array('{"id":"ensaio-fila-tok","tipo":"update"}'::jsonb));
  insert into pg_temp._z_out (passo, ok, linha) values ('T3 [real] token errado', (r ->> 'autorizado')::boolean = false
    and (select count(*) from crm.integracao_fila) = v_n, r::text);

  -- T5 sem id: inválido na entrada; 1..100 vale também na fila
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array('{"tipo":"update"}'::jsonb, 'null'::jsonb));
  insert into pg_temp._z_out (passo, ok, linha) values ('T5 [real] invalidos', (r ->> 'invalidos')::int = 2 and (r ->> 'enfileirados')::int = 0, r::text);
  r := public.crm_integracao_receber('activecampaign', tok, '[]'::jsonb);
  insert into pg_temp._z_out (passo, ok, linha) values ('T5b [real] 1..100', r ->> 'msg' = 'Envie de 1 a 100 eventos.', r::text);

  -- T4 processador com a fonte desligada: não processa, não cria pessoa, item fica pendente
  r := crm.integracao_processar_fila(200);
  insert into pg_temp._z_out (passo, ok, linha) values ('T4 [real] processador respeita fonte desligada',
    (r ->> 'processados') is null or (r ->> 'processados')::int = 0,
    r::text || ' | pendentes=' || (select count(*) from crm.integracao_fila where estado = 'pendente')
    || ' | evento_jornada=' || (select count(*) from crm.evento_jornada where fonte_evento_id like 'ensaio-fila-%'));

  -- T6 rajada com o N REAL (300): 300 linhas da mesma fonte no último minuto (semeadas já processadas)
  insert into crm.integracao_fila (fonte, fonte_evento_id, evento, estado, processado_em)
  select 'activecampaign', 'ensaio-semente-' || g, jsonb_build_object('id', 'ensaio-semente-' || g, 'tipo', 'update'), 'processado', now()
    from generate_series(1, 297) g;   -- + os 2 do T1 = 299
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array('{"id":"ensaio-fila-300","tipo":"update"}'::jsonb));
  insert into pg_temp._z_out (passo, ok, linha) values ('T6a [real N=300] 300º do minuto ainda é normal', (r ->> 'em_massa')::boolean = false, r::text);
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(ev_massa));
  insert into pg_temp._z_out (passo, ok, linha) values ('T6b [real N=300] 301º = em_massa', (r ->> 'em_massa')::boolean = true
    and (select em_massa from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-massa'), r::text);

  -- T9a flag da fila desligada + fonte desligada = antigo idêntico (ignorado), nada na fila
  update crm.config set integracao_fila_ligada = false;
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array('{"id":"ensaio-fila-off","tipo":"update"}'::jsonb));
  insert into pg_temp._z_out (passo, ok, linha) values ('T9a [real] fila off + fonte off = ignorado (antigo)',
    r ->> 'ignorado' = 'desligado' and not exists (select 1 from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-off'), r::text);
  update crm.config set integracao_fila_ligada = true;

  -- ══ FASE B: liga SÓ a fonte; activecampaign_cria_pessoa continua false (como em produção) ══
  update crm.config set activecampaign_ligado = true;
  r := crm.integracao_processar_fila(200);
  select id into v_id_normal from crm.evento_jornada where fonte = 'activecampaign' and fonte_evento_id = 'ensaio-fila-normal';
  select id into v_id_massa from crm.evento_jornada where fonte = 'activecampaign' and fonte_evento_id = 'ensaio-fila-massa';
  insert into pg_temp._z_out (passo, ok, linha) values ('T7a [fonte ligada, cria_pessoa false] processou os pendentes',
    (r ->> 'processados')::int = 4 and not exists (select 1 from crm.integracao_fila where estado in ('pendente', 'erro')), r::text);
  insert into pg_temp._z_out (passo, ok, linha)
  select 'T7b [cria_pessoa false] existente anexa; e-mail novo NÃO vira pessoa',
         bool_and(case e.fonte_evento_id when 'ensaio-fila-novo' then e.resultado = 'sem_pessoa' and e.pessoa_id is null
                                         else e.resultado = 'anexado' and e.pessoa_id is not null end) and count(*) = 3,
         string_agg(e.fonte_evento_id || '=' || e.resultado || ' recebido_em_da_fila=' || (e.recebido_em = f.recebido_em)::text, '; ' order by e.id)
    from crm.evento_jornada e join crm.integracao_fila f using (fonte, fonte_evento_id)
   where e.fonte_evento_id in ('ensaio-fila-normal', 'ensaio-fila-massa', 'ensaio-fila-novo');
  insert into pg_temp._z_out (passo, ok, linha) values ('T7c ativação: normal SIM, em_massa NÃO, sem pessoa NÃO',
    exists (select 1 from pg_temp._z_ativ where evento_id = v_id_normal) and not exists (select 1 from pg_temp._z_ativ where evento_id = v_id_massa)
    and (select count(*) from pg_temp._z_ativ) = 1 and coalesce(current_setting('crm.ativacao_suprimida', true), '') = '',
    'chegaram à ativação: ' || coalesce((select string_agg(evento_id::text, ',') from pg_temp._z_ativ), 'nenhum') ||
    ' | normal=' || v_id_normal || ' massa=' || v_id_massa);

  -- liberação manual do lote em massa (a consulta do explain); conferência num comando seguinte (snapshot)
  select string_agg(x.res, ',') into v_lib
    from (select crm.ativacao_ac_evento(ej) res
            from crm.integracao_fila f
            join crm.evento_jornada ej on ej.fonte = f.fonte and ej.fonte_evento_id = f.fonte_evento_id
           where f.em_massa and f.estado = 'processado' and f.fonte = 'activecampaign'
             and f.recebido_em >= now() - interval '1 hour'
             and ej.pessoa_id is not null and ej.tipo in ('subscribe', 'contact_tag_added')
             and f.id > 0
           order by f.id limit 200) x;
  insert into pg_temp._z_out (passo, ok, linha) values ('T7d liberar lote em_massa (consulta do explain)',
    v_lib = 'sem_projeto' and exists (select 1 from pg_temp._z_ativ where evento_id = v_id_massa),
    'resultado=' || coalesce(v_lib, 'nenhuma linha'));

  -- T8 rodada vazia
  r := crm.integracao_processar_fila(200);
  insert into pg_temp._z_out (passo, ok, linha) values ('T8 rodada vazia', (r ->> 'processados')::int = 0, r::text);

  -- T9b fila off + fonte ligada = caminho antigo síncrono (mesmas chaves de antes), cria_pessoa false
  update crm.config set integracao_fila_ligada = false;
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(jsonb_build_object('id', 'ensaio-fila-antigo',
         'tipo', 'update', 'lista', '0', 'email', (select email from pg_temp._z_mail where k = 'antigo')),
         '{"id":"ensaio-fila-antigo-novo","tipo":"update","lista":"0","email":"fila.ensaio.antigo@exemplo.invalid"}'::jsonb,
         '{"id":"ensaio-fila-antigo-inval","tipo":"x y!","ocorreuEm":"nao-e-data"}'::jsonb));
  insert into pg_temp._z_out (passo, ok, linha) values ('T9b fila off = caminho antigo (cria_pessoa false)',
    (r ->> 'novos')::int = 2 and (r ->> 'anexados')::int = 1 and (r ->> 'pessoas_criadas')::int = 0 and (r ->> 'invalidos')::int = 1
    and not exists (select 1 from crm.integracao_fila where fonte_evento_id like 'ensaio-fila-antigo%'), r::text);
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(jsonb_build_object('id', 'ensaio-fila-antigo', 'tipo', 'update')));
  insert into pg_temp._z_out (passo, ok, linha) values ('T9c caminho antigo: duplicado', (r ->> 'duplicados')::int = 1, r::text);
  update crm.config set integracao_fila_ligada = true;

  -- ══ FASE C (cenário, não é o estado de hoje): cria_pessoa religado ══
  update crm.config set activecampaign_cria_pessoa = true;
  r := public.crm_integracao_receber('activecampaign', tok, jsonb_build_array(
         '{"id":"ensaio-fila-novo2","tipo":"update","email":"fila.ensaio.novo2@exemplo.invalid"}'::jsonb));
  r := crm.integracao_processar_fila(200);
  insert into pg_temp._z_out (passo, ok, linha) values ('T7e [cenário cria_pessoa true] e-mail novo vira pessoa',
    (select resultado from crm.evento_jornada where fonte_evento_id = 'ensaio-fila-novo2') = 'pessoa_criada', r::text);
  update crm.config set activecampaign_cria_pessoa = false;

  -- itens para o T10
  insert into crm.integracao_fila (fonte, fonte_evento_id, evento) values
    ('activecampaign', 'ensaio-fila-erro', '{"id":"ensaio-fila-erro","tipo":"update"}'),
    ('activecampaign', 'ensaio-fila-ok2', '{"id":"ensaio-fila-ok2","tipo":"update"}'),
    ('activecampaign', 'ensaio-fila-inval', '{"id":"ensaio-fila-inval","tipo":"x y!"}');
end
$t$;

-- T11 permissões (antes do T10, que troca a função de gravação)
insert into pg_temp._z_out (passo, ok, linha)
select 'T11 grants (anon/authenticated/service_role sem acesso)', bool_and(not x.pode),
       string_agg(x.quem || ':' || x.oque || '=' || x.pode, ' ')
  from (select r.quem, o.oque,
               case when o.oque = 'fila' then has_table_privilege(r.quem, 'crm.integracao_fila', 'select,insert,update,delete')
                    else has_function_privilege(r.quem, o.oque, 'execute') end pode
          from (values ('anon'), ('authenticated'), ('service_role')) r(quem)
          cross join (values ('fila'), ('crm.integracao_processar_fila(integer)'),
                             ('crm.integracao_gravar_evento(text,jsonb,timestamptz)'),
                             ('crm.ativacao_ac_evento(crm.evento_jornada)')) o(oque)) x;
insert into pg_temp._z_out (passo, ok, linha)
select 'T11b RPC mantém grant', p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'),
       p.proacl::text || ' secdef=' || p.prosecdef
  from pg_proc p where p.oid = 'public.crm_integracao_receber(text,text,jsonb)'::regprocedure;
insert into pg_temp._z_out (passo, ok, linha)
select 'T11c RLS e cron', c.relrowsecurity and exists (select 1 from cron.job j where j.jobname = 'crm-integracao-fila' and j.schedule = '* * * * *'),
       'rls=' || c.relrowsecurity || ' cron=' || coalesce((select j.command from cron.job j where j.jobname = 'crm-integracao-fila'), 'ausente')
  from pg_class c where c.oid = 'crm.integracao_fila'::regclass;

-- T10/T12 (fonte ligada): erro 3x → descartado; inválido 22023; 57014 não trava a fila.
alter function crm.integracao_gravar_evento(text, jsonb, timestamptz) rename to integracao_gravar_evento_orig;
create function crm.integracao_gravar_evento(p_fonte text, p_evento jsonb, p_recebido_em timestamptz) returns text
language plpgsql set search_path = '' as $b$
begin
  if p_evento ->> 'id' = 'ensaio-fila-erro' then raise exception 'forçado' using errcode = 'P0001'; end if;
  if p_evento ->> 'id' = 'ensaio-fila-lento' then perform pg_sleep(3); end if;
  return crm.integracao_gravar_evento_orig(p_fonte, p_evento, p_recebido_em);
end $b$;
do $t2$
declare r1 jsonb; r2 jsonb; r3 jsonb; v text;
begin
  r1 := crm.integracao_processar_fila(200);
  r2 := crm.integracao_processar_fila(200);
  r3 := crm.integracao_processar_fila(200);
  select estado || '/' || tentativas || '/' || coalesce(erro, '-') into v from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-erro';
  insert into pg_temp._z_out (passo, ok, linha) values ('T10 erro 3x → descartado; inválido descartado; ok segue',
    v = 'descartado/3/P0001'
    and (select estado || '/' || erro from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-inval') = 'descartado/22023'
    and (select estado from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-ok2') = 'processado'
    and coalesce(current_setting('crm.ativacao_suprimida', true), '') = '',
    'erro=' || v || ' | r1=' || r1::text);
end
$t2$;

insert into crm.integracao_fila (fonte, fonte_evento_id, evento) values
  ('activecampaign', 'ensaio-fila-antes', '{"id":"ensaio-fila-antes","tipo":"update"}'),
  ('activecampaign', 'ensaio-fila-lento', '{"id":"ensaio-fila-lento","tipo":"update"}'),
  ('activecampaign', 'ensaio-fila-depois', '{"id":"ensaio-fila-depois","tipo":"update"}');
create temp table _z_r (n int, r jsonb) on commit drop;
set local statement_timeout = '2s';
do $t3$ begin insert into pg_temp._z_r values (1, crm.integracao_processar_fila(200)); end $t3$;
set local statement_timeout = '20s';
insert into pg_temp._z_out (passo, ok, linha)
select 'T12a 57014: anterior gravado, lento em erro, rodada encerrada',
       (select estado from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-antes') = 'processado'
   and (select estado || '/' || tentativas || '/' || erro from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-lento') = 'erro/1/57014'
   and (select estado from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-depois') = 'pendente'
   and (select (r ->> 'cancelado')::boolean from pg_temp._z_r where n = 1),
       'r1=' || (select r::text from pg_temp._z_r where n = 1);
set local statement_timeout = '2s';
do $t3$ begin insert into pg_temp._z_r values (2, crm.integracao_processar_fila(200)); end $t3$;
set local statement_timeout = '2s';
do $t3$ begin insert into pg_temp._z_r values (3, crm.integracao_processar_fila(200)); end $t3$;
set local statement_timeout = '20s';
do $t3$ begin insert into pg_temp._z_r values (4, crm.integracao_processar_fila(200)); end $t3$;
insert into pg_temp._z_out (passo, ok, linha)
select 'T12b 3ª vez descartado; o seguinte processa (fila não trava)',
       (select estado || '/' || tentativas || '/' || erro from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-lento') = 'descartado/3/57014'
   and (select estado from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-depois') = 'processado',
       'lento=' || (select estado || '/' || tentativas || '/' || erro from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-lento');

-- T13 de volta à config real (fonte desligada): pendente parado 31 dias sai no expurgo; o recente fica pendente
update crm.config set activecampaign_ligado = false;
insert into crm.integracao_fila (fonte, fonte_evento_id, evento, recebido_em) values
  ('activecampaign', 'ensaio-fila-velho', '{"id":"ensaio-fila-velho","tipo":"update"}', now() - interval '31 days'),
  ('activecampaign', 'ensaio-fila-recente', '{"id":"ensaio-fila-recente","tipo":"update"}', now());
do $t4$ declare r jsonb; begin
  r := crm.integracao_processar_fila(200);
  insert into pg_temp._z_out (passo, ok, linha) values ('T13 [real] parado 30 dias expurgado; recente fica pendente',
    not exists (select 1 from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-velho')
    and (select estado from crm.integracao_fila where fonte_evento_id = 'ensaio-fila-recente') = 'pendente', r::text);
end $t4$;

select em, passo, ok, linha from pg_temp._z_out order by em;
rollback;
