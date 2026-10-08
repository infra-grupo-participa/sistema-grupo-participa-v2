-- 20261008230000: CRM, fila do webhook de integrações (ActiveCampaign, Unnichat, SendFlow)
--
-- STATUS: APLICADA em produção 08/10/2026 (~21:30 UTC, schema_migrations 20261008230000). Ensaio: 20261008230000_ensaio.sql (begin … rollback). Medição e 5 perguntas:
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
