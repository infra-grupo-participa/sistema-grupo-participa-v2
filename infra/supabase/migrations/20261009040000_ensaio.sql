-- Ensaio de 20261009040000 (saturação no vigia). UMA transação, desfeita: aplica a migration (cópia literal abaixo)
-- e roda T1..T10. Termina em raise exception 'ENSAIO_OK {...}' (desfaz tudo) — sucesso = a mensagem começa com ENSAIO_OK.
-- Rodar fora dos minutos :x2 (ciclo do vigia). Management API /database/query, arquivo lido em utf-8.
-- Esperado: T2 disparados=[] (banco saudável); T3 5 tipos; T4 []; T5 []; T6 erro 'sem ensaio_nao_existe no Vault';
--           T7 request_id preenchido e 5 enfileirados; T9 sat.erro preenchido e vigia rodou; T10 command = select ops.ciclo(), false×4;
--           T11 vigiar() forçado a erro → alerta 'conexoes' gravado E enfileirado + alerta 'vigia_erro';
--           T12 statement_timeout 500 ms cancela a saturação (57014) → vigiar() roda mesmo assim.
begin;
-- ═══ MIGRATION (cópia literal de 20261009040000_ops_vigia_saturacao.sql) ═══
-- 20261009040000 — Vigia (7): saturação do banco, no mesmo ciclo do ops-vigia-10min.
--
-- POR QUÊ
--   08/10/2026: o banco caiu 2× sem aviso. Medido em cron.job_run_details: 89 execuções "job startup timeout"
--   entre 20:05 e 20:30 UTC (o pg_cron não conseguiu conexão para começar a rotina); nas 30 h anteriores, 0.
--   O vigia (20261001a..e) só olha rotina por rotina e só abre incidente após N falhas — ninguém via o banco.
--   max_connections = 60 (3 reservadas), cron.max_running_jobs = 32, cron.use_background_workers = off
--   (cada rotina é uma conexão libpq de verdade).
--
-- O QUE CRIA
--   ops.config + colunas saturacao_* (limites e o liga/desliga do envio; padrão: NÃO envia).
--   ops.banco_alerta   1 linha por tipo disparado (o que foi medido, o texto, se foi enfileirado ao Slack).
--   ops.saturacao_medir()  lê pg_stat_activity, cron.job_run_details (últimos 10 min), crm.integracao_fila.
--   ops.saturacao_avaliar(medida) aplica limites e anti-spam (1 alerta por tipo a cada 30 min), grava, envia.
--   ops.vigiar_saturacao() = avaliar(medir()).
--   ops.ciclo()            o que o job 68 passa a chamar: vigiar_saturacao() e depois ops.vigiar(), cada um em
--                          sub-bloco próprio (inclui 57014). Falha do vigiar() vira alerta 'vigia_erro'.
--                          Mesmo job, mesma conexão, mesmo horário.
--
-- TIPOS (limites em ops.config; texto curto em português, só números + usuário/aplicação/rotina)
--   conexoes          conexões de cliente >= saturacao_conexoes_limite (45 de 60)
--   cron_falhas       execuções do pg_cron com status 'failed' nos últimos 10 min > 0 (destaca startup timeout)
--   consultas_lentas  consultas 'active' de cliente há > saturacao_lenta_seg (30 s), exceto a própria sessão,
--                     walsender/replicação/workers (backend_type <> 'client backend') e as rotinas lentas
--                     conhecidas (saturacao_lenta_jobs_ok: fin-identidade-recalcular, p50 28 s, máx 67 s em 7 d)
--   fila_pendente     crm.integracao_fila pendente > saturacao_fila_pendente_limite (2000)
--   fila_erro         na última hora, (erro + descartado) / recebidos >= saturacao_fila_erro_pct (20%)
--                     com pelo menos saturacao_fila_erro_min (20) recebidos
--   O texto da consulta lenta fica SÓ no banco (redigido por ops.redigir antes do corte); o Slack não recebe.
--
-- ENVIO: desligado. Ligar (decisão do Marcio):
--   select vault.create_secret('<URL do webhook do Slack>', 'slack_webhook_rotinas');   -- se ainda não existir
--   update ops.config set saturacao_enviar = true where id;
--   Desligar: update ops.config set saturacao_enviar = false where id;
--   O status HTTP da resposta do Slack é conferido no ciclo seguinte (ops.banco_alerta.http_status).
--
-- CUSTO (medido, ver 20261009040000.explain.md): 5 consultas, todas por índice ou em visão de memória.
--
-- REVERSÃO: 20261009040000_reversao.sql (devolve o command do job 68 e remove as funções; dados ficam).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $pre$
begin
  if not exists (select 1 from cron.job where jobname = 'ops-vigia-10min' and command = 'select ops.vigiar()') then
    raise exception '20261009040000: job ops-vigia-10min não está com o command esperado — conferir antes';
  end if;
  if to_regprocedure('ops.ciclo()') is not null then
    raise exception '20261009040000: ops.ciclo() já existe';
  end if;
end
$pre$;

alter table ops.config
  add column saturacao_enviar             boolean not null default false,
  add column saturacao_webhook            text    not null default 'slack_webhook_rotinas',
  add column saturacao_conexoes_limite    int     not null default 45 check (saturacao_conexoes_limite between 1 and 1000),
  add column saturacao_lenta_seg          int     not null default 30 check (saturacao_lenta_seg between 1 and 3600),
  add column saturacao_lenta_jobs_ok      text[]  not null default '{fin-identidade-recalcular}',
  add column saturacao_fila_pendente_limite int   not null default 2000 check (saturacao_fila_pendente_limite >= 1),
  add column saturacao_fila_erro_pct      numeric not null default 20 check (saturacao_fila_erro_pct > 0 and saturacao_fila_erro_pct <= 100),
  add column saturacao_fila_erro_min      int     not null default 20 check (saturacao_fila_erro_min >= 1),
  add column saturacao_antispam           interval not null default interval '30 minutes'
                                          check (saturacao_antispam >= interval '1 minute');
comment on column ops.config.saturacao_enviar is 'false = alertas de saturação só gravados em ops.banco_alerta; true = também ao Slack (Vault: saturacao_webhook).';

create table ops.banco_alerta (
  id           bigint generated always as identity primary key,
  criado_em    timestamptz not null default now(),
  tipo         text not null check (tipo in ('conexoes','cron_falhas','consultas_lentas','fila_pendente','fila_erro','consumo_semanal','vigia_erro')),
  valor        numeric not null,
  texto        text not null,
  detalhe      jsonb not null default '{}'::jsonb,   -- só banco: pode ter trecho de consulta (redigido)
  enviado      boolean not null default false,       -- enfileirado no pg_net; a prova é http_status
  request_id   bigint,
  http_status  int,
  erro         text
);
create index banco_alerta_tipo_idx on ops.banco_alerta (tipo, criado_em desc);
create index banco_alerta_conferir_idx on ops.banco_alerta (id) where request_id is not null and http_status is null;

create function ops.fmt_num(p numeric) returns text
language sql immutable set search_path = '' as $f$
  select replace(to_char(round(p), 'FM999,999,999,990'), ',', '.')
$f$;

create function ops.fmt_dur(p interval) returns text
language sql immutable set search_path = '' as $f$
  select case when p < interval '1 minute' then extract(epoch from p)::int || ' s'
              else floor(extract(epoch from p) / 60)::int || ' min ' || (extract(epoch from p)::int % 60) || ' s' end
$f$;

-- Só leitura. Cada bloco é independente: se crm.integracao_fila sumir, o resto continua medindo.
create function ops.saturacao_medir() returns jsonb
language plpgsql stable set search_path = '' as $f$
declare
  c      ops.config%rowtype;
  v_ag   timestamptz := clock_timestamp();
  r      jsonb := jsonb_build_object('medido_em', clock_timestamp());
  v      jsonb;
begin
  select * into c from ops.config where id;

  -- conexões: só client backend ocupa vaga de max_connections (walsender e workers não)
  select jsonb_build_object(
           'cliente', count(*) filter (where a.backend_type = 'client backend'),
           'total', count(*),
           'max', current_setting('max_connections')::int,
           'top', (select coalesce(jsonb_agg(jsonb_build_object('quem', t.quem, 'n', t.n) order by t.n desc), '[]'::jsonb)
                     from (select coalesce(b.usename::text, '?') || ' / ' || coalesce(nullif(b.application_name, ''), '?') as quem,
                                  count(*) as n
                             from pg_catalog.pg_stat_activity b where b.backend_type = 'client backend'
                            group by 1 order by 2 desc limit 4) t))
    into v from pg_catalog.pg_stat_activity a;
  r := r || jsonb_build_object('conexoes', v);

  -- pg_cron: failed nos últimos 10 min. Faixa por runid (pkey) — nunca varre a tabela.
  select jsonb_build_object(
           'falhas', count(*),
           'startup_timeout', count(*) filter (where d.return_message ilike 'job startup timeout%'),
           'rotinas', (select coalesce(jsonb_agg(x.jobname order by x.n desc), '[]'::jsonb)
                         from (select j.jobname, count(*) n
                                 from cron.job_run_details d2 join cron.job j on j.jobid = d2.jobid
                                where d2.runid > (select max(m.runid) from cron.job_run_details m) - 2000
                                  and d2.status = 'failed'
                                  and coalesce(d2.end_time, d2.start_time) > v_ag - interval '10 minutes'
                                group by 1 order by 2 desc limit 3) x))
    into v
    from cron.job_run_details d
   where d.runid > (select max(m.runid) from cron.job_run_details m) - 2000
     and d.status = 'failed'
     and coalesce(d.end_time, d.start_time) > v_ag - interval '10 minutes';
  r := r || jsonb_build_object('cron', v);

  -- consultas lentas
  select jsonb_build_object(
           'n', count(*),
           'max_seg', coalesce(round(max(extract(epoch from v_ag - a.query_start))), 0),
           'lista', coalesce(jsonb_agg(jsonb_build_object(
                       'pid', a.pid,
                       'quem', coalesce(a.usename::text, '?') || ' / ' || coalesce(nullif(a.application_name, ''), '?'),
                       'seg', round(extract(epoch from v_ag - a.query_start)),
                       'espera', a.wait_event_type || ':' || a.wait_event,
                       'consulta', left(ops.redigir(a.query), 200))      -- redige e DEPOIS corta; só banco
                     order by a.query_start) filter (where a.pid is not null), '[]'::jsonb))
    into v
    from pg_catalog.pg_stat_activity a
   where a.backend_type = 'client backend'
     and a.state = 'active'
     and a.pid <> pg_catalog.pg_backend_pid()
     and a.query_start < v_ag - make_interval(secs => c.saturacao_lenta_seg)
     and not exists (select 1 from cron.job j
                      where j.jobname = any (c.saturacao_lenta_jobs_ok) and btrim(j.command) = btrim(a.query));
  r := r || jsonb_build_object('lentas', v);

  -- fila do CRM (índices: integracao_fila_aberta_idx parcial; integracao_fila_recebido_idx)
  begin
    select jsonb_build_object(
             'pendente', (select count(*) from crm.integracao_fila f where f.estado = 'pendente'),
             'recebidos_1h', count(*),
             'erro_1h', count(*) filter (where g.estado in ('erro', 'descartado')))
      into v
      from crm.integracao_fila g
     where g.recebido_em > v_ag - interval '1 hour';
    r := r || jsonb_build_object('fila', v);
  exception when others then
    r := r || jsonb_build_object('fila', jsonb_build_object('erro', sqlstate));
  end;

  return r;
end
$f$;

-- Limites + anti-spam + gravação + envio. Recebe a medida pronta (o ensaio injeta medidas simuladas).
create function ops.saturacao_avaliar(p jsonb) returns jsonb
language plpgsql set search_path = '' as $f$
declare
  c        ops.config%rowtype;
  v_ag     timestamptz := clock_timestamp();
  v_cand   jsonb := '[]'::jsonb;
  v_ids    bigint[];
  v_tipos  text[];
  v_texto  text;
  v_url    text;
  v_req    bigint;
  v_conf   int;
  n        numeric;
begin
  select * into c from ops.config where id;

  -- confere a resposta do Slack dos envios anteriores (net._http_response vive 6 h)
  update ops.banco_alerta s set http_status = coalesce(h.status_code, -1),
         erro = case when h.status_code between 200 and 299 then null
                     else left(coalesce('HTTP ' || h.status_code, h.error_msg, 'sem resposta'), 120) end
    from net._http_response h
   where s.request_id = h.id and s.request_id is not null and s.http_status is null
     and s.criado_em > v_ag - interval '6 hours';               -- o id do pg_net é reciclado depois do TTL
  get diagnostics v_conf = row_count;
  update ops.banco_alerta s set http_status = -1, erro = 'sem resposta do Slack em 6 h'
   where s.request_id is not null and s.http_status is null and s.criado_em <= v_ag - interval '6 hours';

  n := (p->'conexoes'->>'cliente')::numeric;
  if n >= c.saturacao_conexoes_limite then
    v_cand := v_cand || jsonb_build_object('tipo', 'conexoes', 'valor', n, 'detalhe', p->'conexoes',
      'texto', format('Conexões quase esgotadas: %s de %s em uso (alerta a partir de %s). Quem mais usa: %s.',
                      ops.fmt_num(n), p->'conexoes'->>'max', c.saturacao_conexoes_limite,
                      (select string_agg(t->>'quem' || ' = ' || (t->>'n'), ', ')
                         from jsonb_array_elements(p->'conexoes'->'top') t)));
  end if;

  n := (p->'cron'->>'falhas')::numeric;
  if n > 0 then
    v_cand := v_cand || jsonb_build_object('tipo', 'cron_falhas', 'valor', n, 'detalhe', p->'cron',
      'texto', format('Rotinas falhando: %s execução(ões) falharam nos últimos 10 min%s. Mais afetadas: %s.',
                      ops.fmt_num(n),
                      case when (p->'cron'->>'startup_timeout')::int > 0
                           then format(', %s por "job startup timeout" (o banco não deu conexão para a rotina começar)',
                                       ops.fmt_num((p->'cron'->>'startup_timeout')::numeric)) else '' end,
                      (select string_agg(x, ', ') from jsonb_array_elements_text(p->'cron'->'rotinas') x)));
  end if;

  n := (p->'lentas'->>'n')::numeric;
  if n > 0 then
    v_cand := v_cand || jsonb_build_object('tipo', 'consultas_lentas', 'valor', n, 'detalhe', p->'lentas',
      'texto', format('Consultas presas: %s rodando há mais de %s s. A mais longa: %s (%s).',
                      ops.fmt_num(n), c.saturacao_lenta_seg,
                      ops.fmt_dur(make_interval(secs => (p->'lentas'->>'max_seg')::numeric)),
                      p->'lentas'->'lista'->0->>'quem'));
  end if;

  n := (p->'fila'->>'pendente')::numeric;
  if n > c.saturacao_fila_pendente_limite then
    v_cand := v_cand || jsonb_build_object('tipo', 'fila_pendente', 'valor', n, 'detalhe', p->'fila',
      'texto', format('Fila do CRM acumulando: %s eventos pendentes (alerta acima de %s).',
                      ops.fmt_num(n), ops.fmt_num(c.saturacao_fila_pendente_limite)));
  end if;

  if p ? 'vigia_erro' then
    v_cand := v_cand || jsonb_build_object('tipo', 'vigia_erro', 'valor', 1, 'detalhe', jsonb_build_object('sqlstate', p->>'vigia_erro'),
      'texto', format('O vigia das rotinas falhou neste ciclo (erro %s): as rotinas não foram conferidas.', p->>'vigia_erro'));
  end if;

  if (p->'fila'->>'recebidos_1h')::numeric >= c.saturacao_fila_erro_min then
    n := round(100 * (p->'fila'->>'erro_1h')::numeric / (p->'fila'->>'recebidos_1h')::numeric, 1);
    if n >= c.saturacao_fila_erro_pct then
      v_cand := v_cand || jsonb_build_object('tipo', 'fila_erro', 'valor', n, 'detalhe', p->'fila',
        'texto', format('Fila do CRM com erro: %s%% dos %s eventos da última hora deram erro ou foram descartados (%s).',
                        replace(n::text, '.', ','), ops.fmt_num((p->'fila'->>'recebidos_1h')::numeric),
                        ops.fmt_num((p->'fila'->>'erro_1h')::numeric)));
    end if;
  end if;

  -- anti-spam: 1 por tipo na janela (índice tipo, criado_em desc)
  with ins as (
    insert into ops.banco_alerta (tipo, valor, texto, detalhe)
    select x->>'tipo', (x->>'valor')::numeric, ops.slack_esc(x->>'texto'), coalesce(x->'detalhe', '{}'::jsonb)
      from jsonb_array_elements(v_cand) x
     where not exists (select 1 from ops.banco_alerta s
                        where s.tipo = x->>'tipo' and s.criado_em > v_ag - c.saturacao_antispam)
    returning id, tipo, texto
  )
  select array_agg(id order by id), array_agg(tipo order by id),
         string_agg(texto, E'\n' order by id)
    into v_ids, v_tipos, v_texto from ins;

  if v_ids is not null and c.saturacao_enviar then
    select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = c.saturacao_webhook;
    if v_url is not null then
      v_req := net.http_post(url := v_url,
                             body := jsonb_build_object('text', 'Alerta do banco (' || ops.fmt_hora(v_ag) || ')' || E'\n' || v_texto),
                             timeout_milliseconds := 10000);
      update ops.banco_alerta set enviado = true, request_id = v_req where id = any (v_ids);
    else
      update ops.banco_alerta set erro = 'sem ' || c.saturacao_webhook || ' no Vault' where id = any (v_ids);
    end if;
  end if;

  delete from ops.banco_alerta al
   where al.id in (select x.id from ops.banco_alerta x where x.criado_em < v_ag - interval '90 days'
                    order by x.criado_em limit 5000);

  return jsonb_build_object('disparados', coalesce(to_jsonb(v_tipos), '[]'::jsonb),
                            'candidatos', jsonb_array_length(v_cand),
                            'request_id', v_req, 'conferidos', v_conf);
end
$f$;

create function ops.vigiar_saturacao() returns jsonb
language plpgsql set search_path = '' as $f$
declare
  v_ag timestamptz := clock_timestamp();
  v    jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('ops.vigiar_saturacao')) then
    return jsonb_build_object('pulado', 'outro ciclo em andamento');
  end if;
  v := ops.saturacao_avaliar(ops.saturacao_medir());
  return v || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_ag) * 1000));
end
$f$;

-- O job 68 passa a chamar isto. Cada metade num sub-bloco próprio (subtransação): a falha de uma desfaz só ela.
-- `when others` NÃO pega 57014 (query_canceled / statement_timeout): listado à parte.
-- Falha de ops.vigiar() não some: vira alerta 'vigia_erro' em ops.banco_alerta (mesmo anti-spam e envio) e warning.
create function ops.ciclo() returns jsonb
language plpgsql set search_path = '' as $f$
declare
  v_sat jsonb;
  v_vig jsonb;
  v_st  text;
begin
  begin
    v_sat := ops.vigiar_saturacao();
  exception when query_canceled or others then
    v_sat := jsonb_build_object('erro', sqlstate || ' ' || left(sqlerrm, 200));
    raise warning 'ops.vigiar_saturacao falhou: % %', sqlstate, sqlerrm;
  end;
  begin
    v_vig := ops.vigiar();
  exception when query_canceled or others then
    v_st  := sqlstate;
    v_vig := jsonb_build_object('erro', sqlstate || ' ' || left(sqlerrm, 200));
    raise warning 'ops.vigiar falhou: % %', sqlstate, sqlerrm;
  end;
  if v_st is not null then
    begin
      v_vig := v_vig || jsonb_build_object('alerta', ops.saturacao_avaliar(jsonb_build_object('vigia_erro', v_st)));
    exception when query_canceled or others then
      raise warning 'alerta vigia_erro falhou: % %', sqlstate, sqlerrm;
    end;
  end if;
  return coalesce(v_vig, '{}'::jsonb) || jsonb_build_object('saturacao', v_sat);
end
$f$;

select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'ops-vigia-10min'),
                      command := 'select ops.ciclo()');

-- Função nova nasce com EXECUTE para PUBLIC; tabela nova, revogar explicitamente (schema ops já é fechado).
revoke all on table ops.banco_alerta from public, anon, authenticated, service_role;
revoke execute on function ops.fmt_num(numeric), ops.fmt_dur(interval), ops.saturacao_medir(),
                           ops.saturacao_avaliar(jsonb), ops.vigiar_saturacao(), ops.ciclo()
  from public, anon, authenticated, service_role;

do $pos$
declare v text;
begin
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, 'null'), ' ') into v
    from pg_proc p
   where p.pronamespace = 'ops'::regnamespace
     and p.proname in ('fmt_num', 'fmt_dur', 'saturacao_medir', 'saturacao_avaliar', 'vigiar_saturacao', 'ciclo')
     and (p.proacl is null or p.proacl::text ~ '(^|[{,])=X' or p.proacl::text ~ '(anon|authenticated|service_role)=');
  if v is not null then
    raise exception '20261009040000: EXECUTE aberto: %', v;
  end if;
  if has_table_privilege('anon', 'ops.banco_alerta', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'ops.banco_alerta', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'ops.banco_alerta', 'select,insert,update,delete,truncate,references,trigger') then
    raise exception '20261009040000: ops.banco_alerta acessível por anon/authenticated/service_role';
  end if;
  if not exists (select 1 from cron.job where jobname = 'ops-vigia-10min' and command = 'select ops.ciclo()') then
    raise exception '20261009040000: alter_job não pegou';
  end if;
end
$pos$;
-- ═══ TESTES ═══
create temp table ens (r jsonb);
do $t$
declare
  r jsonb := '{}'::jsonb; v jsonb; t0 timestamptz;
  sim jsonb := jsonb_build_object(
    'conexoes', jsonb_build_object('cliente', 47, 'total', 58, 'max', 60,
                                   'top', jsonb_build_array(jsonb_build_object('quem', 'authenticator / PostgREST 14.5', 'n', 22),
                                                            jsonb_build_object('quem', 'postgres / pg_cron', 'n', 14))),
    'cron', jsonb_build_object('falhas', 12, 'startup_timeout', 9, 'rotinas', jsonb_build_array('crm-evolution-enviar', 'dados-ac-utm')),
    'lentas', jsonb_build_object('n', 2, 'max_seg', 252, 'lista', jsonb_build_array(jsonb_build_object('quem', 'authenticator / PostgREST 14.5', 'seg', 252))),
    'fila', jsonb_build_object('pendente', 2340, 'recebidos_1h', 120, 'erro_1h', 42));
begin
  -- T1 medida real (sem texto de consulta na saída)
  t0 := clock_timestamp(); v := ops.saturacao_medir();
  r := r || jsonb_build_object('T1_medida_real', v #- '{lentas,lista}', 'T1_ms', round(extract(epoch from clock_timestamp()-t0)*1000, 1));
  t0 := clock_timestamp(); v := ops.saturacao_medir();
  r := r || jsonb_build_object('T1_ms_2a', round(extract(epoch from clock_timestamp()-t0)*1000, 1));
  -- T2 ciclo real com limites de produção: esperado disparados = [] se o banco está saudável
  r := r || jsonb_build_object('T2_vigiar_saturacao_real', ops.vigiar_saturacao());
  -- T3 simulação: os 5 tipos disparam
  r := r || jsonb_build_object('T3_simulado', ops.saturacao_avaliar(sim));
  r := r || jsonb_build_object('T3_textos', (select jsonb_agg(texto order by id) from ops.banco_alerta));
  -- T4 anti-spam: mesma medida de novo → nada
  r := r || jsonb_build_object('T4_antispam', ops.saturacao_avaliar(sim));
  -- T5 abaixo do limite não dispara (44 conexões, 0 falhas, 0 lentas, 2000 pendentes, 19% / 19 recebidos)
  update ops.banco_alerta set criado_em = criado_em - interval '31 minutes';
  r := r || jsonb_build_object('T5_abaixo', ops.saturacao_avaliar(jsonb_build_object(
          'conexoes', jsonb_build_object('cliente', 44, 'max', 60, 'top', '[]'::jsonb),
          'cron', jsonb_build_object('falhas', 0, 'startup_timeout', 0, 'rotinas', '[]'::jsonb),
          'lentas', jsonb_build_object('n', 0, 'max_seg', 0, 'lista', '[]'::jsonb),
          'fila', jsonb_build_object('pendente', 2000, 'recebidos_1h', 19, 'erro_1h', 19))));
  -- T6 envio ligado sem segredo no Vault → grava erro, não posta
  update ops.config set saturacao_enviar = true, saturacao_webhook = 'ensaio_nao_existe' where id;
  v := ops.saturacao_avaliar(sim);   -- statement separado: subquery no mesmo comando não vê o que a função gravou
  r := r || jsonb_build_object('T6_sem_segredo', v,
          'T6_erros', (select jsonb_agg(distinct erro) from ops.banco_alerta where criado_em > now() - interval '1 minute'));
  -- T7 envio ligado com segredo (URL inválida, transação desfeita: o pg_net nunca vê o pedido)
  update ops.banco_alerta set criado_em = criado_em - interval '31 minutes';
  perform vault.create_secret('https://exemplo.invalid/ensaio', 'ensaio_webhook_saturacao');
  update ops.config set saturacao_webhook = 'ensaio_webhook_saturacao' where id;
  v := ops.saturacao_avaliar(sim);
  r := r || jsonb_build_object('T7_com_segredo', v,
          'T7_enfileirados', (select count(*) from ops.banco_alerta where request_id = (v->>'request_id')::bigint and enviado));
  update ops.config set saturacao_enviar = false, saturacao_webhook = 'slack_webhook_rotinas' where id;
  -- T8 ciclo completo (o que o job 68 chama), 2×
  t0 := clock_timestamp(); v := ops.ciclo();
  r := r || jsonb_build_object('T8_ciclo_ms', round(extract(epoch from clock_timestamp()-t0)*1000, 1), 'T8_sat', v->'saturacao', 'T8_vigia_ms', v->'ms');
  t0 := clock_timestamp(); v := ops.ciclo();
  r := r || jsonb_build_object('T8_ciclo_ms_2a', round(extract(epoch from clock_timestamp()-t0)*1000, 1));
  -- T9 erro na saturação não derruba o vigia (tira o EXECUTE do crm.integracao_fila não dá como postgres;
  --    simula renomeando a função de medida dentro da transação)
  alter function ops.saturacao_medir() rename to saturacao_medir_x;
  v := ops.ciclo();
  r := r || jsonb_build_object('T9_sat_erro', v->'saturacao', 'T9_vigia_rodou', v ? 'ms');
  alter function ops.saturacao_medir_x() rename to saturacao_medir;
  -- T10 permissões
  r := r || jsonb_build_object('T10_job', (select command from cron.job where jobname = 'ops-vigia-10min'),
          'T10_anon_exec', has_function_privilege('anon', 'ops.ciclo()', 'execute'),
          'T10_auth_exec', has_function_privilege('authenticated', 'ops.saturacao_avaliar(jsonb)', 'execute'),
          'T10_public_acl', (select bool_or(proacl::text ~ '(^|[{,])=X') from pg_proc where pronamespace = 'ops'::regnamespace),
          'T10_anon_tab', has_table_privilege('anon', 'ops.banco_alerta', 'select'));
  -- T11 ops.vigiar() forçado a erro: a saturação do mesmo ciclo continua gravada e enfileirada
  update ops.banco_alerta set criado_em = criado_em - interval '31 minutes';
  update ops.config set saturacao_conexoes_limite = 1, saturacao_enviar = true, saturacao_webhook = 'ensaio_webhook_saturacao' where id;
  alter function ops.vigiar() rename to vigiar_x;
  v := ops.ciclo();
  alter function ops.vigiar_x() rename to vigiar;
  r := r || jsonb_build_object('T11_ciclo', v,
          'T11_gravados', (select jsonb_agg(jsonb_build_object('tipo', tipo, 'enfileirado', enviado, 'request_id', request_id, 'texto', texto) order by id)
                             from ops.banco_alerta where criado_em > now() - interval '1 minute'));
  update ops.config set saturacao_conexoes_limite = 45, saturacao_enviar = false, saturacao_webhook = 'slack_webhook_rotinas' where id;
  insert into ens values (r);
end
$t$;
-- T12 cancelamento real: medir() dorme 2 s, statement_timeout 500 ms → 57014 dentro da saturação; vigiar() tem de rodar
create or replace function ops.saturacao_medir() returns jsonb language plpgsql set search_path = '' as $s$
begin perform pg_catalog.pg_sleep(2); return '{}'::jsonb; end $s$;
set local statement_timeout = '500ms';
insert into ens select jsonb_build_object('T12_ciclo', ops.ciclo() - 'mudancas');
set local statement_timeout = '20s';
do $f$ begin raise exception 'ENSAIO_OK %', (select jsonb_agg(r) from ens); end $f$;
rollback;
