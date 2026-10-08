-- Ensaio de 20261009041000 (consumo semanal). UMA transação, desfeita: aplica 20261009040000 + 20261009041000 (cópias
-- literais abaixo) e roda T1..T6. Termina em raise exception 'ENSAIO_OK {...}' (desfaz tudo).
-- Esperado: T1 primeira foto; T2 com_base > 0 e 0 regressões; T3 linha 'REGRESSÃO'; T4 enfileirado = true;
--           T5 0 sobrando; T6 '6 11 * * 1 | set statement_timeout ...', false×4;
--           T7 nenhum '@', 'sk_ab12', 'tk9z', 'fulano' na saída; DO/vault → '[texto omitido] #queryid'.
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
-- ═══ MIGRATION (cópia literal de 20261009041000_ops_consumo_semanal.sql) ═══
-- 20261009041000 — Vigia (8): relatório semanal de consumo do banco (segunda 08:06 BRT) no Slack.
--
-- DEPENDE DE 20261009040000 (ops.banco_alerta, ops.fmt_num, ops.config.saturacao_webhook).
--
-- POR QUÊ
--   fin.recalcular_identidade foi de 930 ms a 26 s por chamada em 11 dias sem ninguém ver. pg_stat_statements
--   ZERA no reinício (medido: stats_reset 08/10 20:35 UTC, depois da queda) — então a comparação semana × semana
--   precisa de uma foto própria: ops.consumo_semana.
--
-- O QUE CRIA
--   ops.config + consumo_enviar (false = só grava; true = posta no Slack pelo mesmo webhook da saturação),
--                consumo_cursor_runid (cursor em cron.job_run_details, pkey).
--   ops.consumo_semana  foto semanal: consultas (top 300 por tempo ∪ top 300 por chamadas) e tabelas (top 300 por
--                       tamanho). Guarda o acumulado e o consumo da semana. Retenção 12 semanas.
--   ops.consulta_curta(text, queryid) consulta normalizada → 100 chars; literal ('…', E'…', $$…$$, $tag$…$tag$,
--                       número ≥ 4 dígitos) → ?; do/set/alter/create/copy/vault/grant ou vault./decrypted_secret →
--                       só palavra-chave + queryid. consulta_curta_redigida = isso + ops.redigir.
--   ops.consumo_semanal() mede, grava a foto, monta a mensagem, grava em ops.banco_alerta (tipo consumo_semanal) e
--                       envia se consumo_enviar. O status HTTP do Slack é conferido pelo ciclo de 10 min.
--   cron ops-consumo-semanal '6 11 * * 1' (UTC = segunda 08:06 BRT). Minuto 6 da hora 11: só os 6 jobs de todo
--   minuto rodam ali (conferido em cron.job 08/10); o :07 tem fin-hotmart-* (2) e crm-whatsapp-reprocessar.
--   statement_timeout próprio de 60 s no command.
--
-- O QUE A MENSAGEM TRAZ
--   Top 10 consultas por tempo total e por chamadas, na semana, com variação contra a semana anterior.
--   "REGRESSÃO" quando a média por chamada da semana > 3× a média da semana anterior (mín. 5 chamadas).
--   Top 5 rotinas do pg_cron por duração somada na semana + falhas. Top 5 tabelas por crescimento.
--   Variação só aparece quando há base (a mesma consulta na foto anterior e sem reinício entre as duas fotos);
--   depois de um reinício o consumo da semana vale "desde o reinício" e a mensagem diz isso.
--
-- LIGAR:    update ops.config set consumo_enviar = true where id;   (webhook: ver 20261009040000)
-- DESLIGAR: update ops.config set consumo_enviar = false where id;  ou  select cron.unschedule('ops-consumo-semanal');
-- REVERSÃO: 20261009041000_reversao.sql

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $pre$
begin
  if to_regclass('ops.banco_alerta') is null then
    raise exception '20261009041000: aplicar 20261009040000 antes';
  end if;
  if exists (select 1 from cron.job where jobname = 'ops-consumo-semanal') then
    raise exception '20261009041000: job ops-consumo-semanal já existe';
  end if;
  if to_regclass('extensions.pg_stat_statements') is null then
    raise exception '20261009041000: extensions.pg_stat_statements não existe';
  end if;
end
$pre$;

alter table ops.config
  add column consumo_enviar        boolean not null default false,
  add column consumo_cursor_runid  bigint;

create table ops.consumo_semana (
  foto_em       timestamptz not null,
  tipo          text not null check (tipo in ('consulta', 'tabela')),
  chave         text not null,           -- consulta: userid:queryid · tabela: schema.tabela
  rotulo        text not null,           -- consulta: usuário + texto curto (sem literal) · tabela: schema.tabela
  acum_calls    bigint,                  -- acumulado do pg_stat_statements no momento da foto
  acum_ms       double precision,
  semana_calls  bigint,                  -- consumo da semana (ou desde o reinício)
  semana_ms     double precision,
  com_base      boolean not null default false,  -- havia foto anterior comparável
  bytes         bigint,
  primary key (tipo, foto_em, chave)
);
comment on table ops.consumo_semana is 'Foto semanal de consumo (pg_stat_statements zera no reinício). Retenção 12 semanas. ADR 0001.';

create function ops.consulta_curta(p text, p_queryid bigint default null) returns text
language sql immutable set search_path = '' as $f$
  select case
    -- utilitário/DDL/segredo: texto descartado, só palavra-chave + queryid
    when coalesce(p, '') ~* '^\s*(do|set|alter|create|copy|vault|grant)\M'
      or coalesce(p, '') ~* '(vault\.|decrypted_secret)'
      then upper(substring(coalesce(p, '') from '^\s*(\w+)')) || ' [texto omitido] #' || coalesce(p_queryid::text, '?')
    else left(btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '(\$[A-Za-z_]*\$).*?\1', '?', 'g'),        -- dollar-quoted: $$…$$ e $tag$…$tag$
           '[Ee]''([^''\\]|\\.|'''')*''', '?', 'g'),  -- E'..\'..'
           '''([^'']|'''')*''', '?', 'g'),              -- literal de texto ('' dentro)
           '\m\d{4,}\M', '?', 'g'),                     -- número longo (id, telefone sem máscara)
           '\s+', ' ', 'g')), 100)
  end
$f$;

-- redige DEPOIS de tirar os literais e corta de novo
create function ops.consulta_curta_redigida(p text, p_queryid bigint default null) returns text
language sql immutable set search_path = '' as $f$
  select left(ops.redigir(ops.consulta_curta(p, p_queryid)), 100)
$f$;

create function ops.consumo_semanal() returns jsonb
language plpgsql set search_path = '' as $f$
declare
  c        ops.config%rowtype;
  v_ag     timestamptz := clock_timestamp();
  v_prev   timestamptz;
  v_reset  timestamptz;
  v_max    bigint;
  v_tot    double precision;
  v_tot_ant double precision;
  l_tempo  text; l_calls text; l_regr text; l_cron text; l_tab text;
  v_nregr  int;
  v_texto  text;
  v_id     bigint;
  v_url    text;
  v_req    bigint;
begin
  if not pg_try_advisory_xact_lock(hashtext('ops.consumo_semanal')) then
    return jsonb_build_object('pulado', 'outro em andamento');
  end if;
  select * into c from ops.config where id;
  select max(s.foto_em) into v_prev from ops.consumo_semana s where s.tipo = 'consulta';
  select i.stats_reset into v_reset from extensions.pg_stat_statements_info i;

  -- 1. foto das consultas (top 300 por tempo ∪ top 300 por chamadas) com o consumo da semana
  insert into ops.consumo_semana (foto_em, tipo, chave, rotulo, acum_calls, acum_ms, semana_calls, semana_ms, com_base)
  select v_ag, 'consulta', q.chave, q.rotulo, q.calls, q.total_ms,
         case when b.ok then q.calls - p.acum_calls else q.calls end,
         case when b.ok then q.total_ms - p.acum_ms else q.total_ms end,
         b.ok
    from (select s.userid::regrole::text || ':' || s.queryid as chave,
                 s.userid::regrole::text || ': ' || ops.consulta_curta_redigida(s.query, s.queryid) as rotulo,
                 s.calls, s.total_exec_time as total_ms,
                 row_number() over (order by s.total_exec_time desc) as r_t,
                 row_number() over (order by s.calls desc) as r_c
            from extensions.pg_stat_statements(true) s
           where s.dbid = (select d.oid from pg_catalog.pg_database d where d.datname = current_database())
             and s.queryid is not null) q
    left join ops.consumo_semana p on p.tipo = 'consulta' and p.foto_em = v_prev and p.chave = q.chave
   cross join lateral (select p.chave is not null and v_reset < v_prev
                              and q.calls >= p.acum_calls as ok) b
   where q.r_t <= 300 or q.r_c <= 300
  on conflict do nothing;

  -- 2. foto das tabelas (top 300 por tamanho, schemas de usuário)
  insert into ops.consumo_semana (foto_em, tipo, chave, rotulo, bytes, com_base)
  select v_ag, 'tabela', t.nome, t.nome, t.bytes, false
    from (select n.nspname || '.' || cl.relname as nome, pg_catalog.pg_total_relation_size(cl.oid) as bytes
            from pg_catalog.pg_class cl join pg_catalog.pg_namespace n on n.oid = cl.relnamespace
           where cl.relkind in ('r', 'm', 'p')
             and n.nspname not in ('pg_catalog', 'information_schema', 'pg_toast')
           order by 2 desc limit 300) t
  on conflict do nothing;

  -- 3. linhas da mensagem
  select sum(s.semana_ms) into v_tot from ops.consumo_semana s where s.tipo = 'consulta' and s.foto_em = v_ag;
  select sum(s.semana_ms) into v_tot_ant from ops.consumo_semana s where s.tipo = 'consulta' and s.foto_em = v_prev;

  with cur as (
    select s.*, a.semana_ms as ant_ms, a.semana_calls as ant_calls,
           s.semana_ms / nullif(s.semana_calls, 0) as media,
           a.semana_ms / nullif(a.semana_calls, 0) as media_ant
      from ops.consumo_semana s
      left join ops.consumo_semana a on a.tipo = 'consulta' and a.foto_em = v_prev and a.chave = s.chave and s.com_base
     where s.tipo = 'consulta' and s.foto_em = v_ag
  ), t as (select * from cur order by semana_ms desc nulls last limit 10),
     k as (select * from cur order by semana_calls desc nulls last limit 10),
     r as (select * from cur where semana_calls >= 5 and ant_calls >= 5 and media > 3 * media_ant
            order by semana_ms desc limit 5)
  select (select string_agg(format('%s. %s · %s chamadas · média %s%s — %s', x.n, ops.fmt_ms(x.semana_ms),
                                   ops.fmt_num(x.semana_calls), ops.fmt_ms(x.media),
                                   coalesce(' (' || ops.fmt_var(x.semana_ms, x.ant_ms) || ')', ''), x.rotulo), E'\n' order by x.n)
            from (select t.*, row_number() over (order by semana_ms desc nulls last) n from t) x),
         (select string_agg(format('%s. %s chamadas%s · média %s — %s', x.n, ops.fmt_num(x.semana_calls),
                                   coalesce(' (' || ops.fmt_var(x.semana_calls, x.ant_calls) || ')', ''),
                                   ops.fmt_ms(x.media), x.rotulo), E'\n' order by x.n)
            from (select k.*, row_number() over (order by semana_calls desc nulls last) n from k) x),
         (select string_agg(format('REGRESSÃO: média %s → %s (%s×) — %s', ops.fmt_ms(r.media_ant), ops.fmt_ms(r.media),
                                   round((r.media / r.media_ant)::numeric, 1), r.rotulo), E'\n') from r),
         (select count(*) from r)
    into l_tempo, l_calls, l_regr, v_nregr;

  -- rotinas: cursor em runid (pkey); 1ª vez cai para os últimos 7 dias
  select max(d.runid) into v_max from cron.job_run_details d;
  select string_agg(format('%s. %s — %s em %s execuções%s', x.n, x.jobname, ops.fmt_ms(x.ms), ops.fmt_num(x.execs),
                           case when x.falhas > 0 then ' · ' || x.falhas || ' falha(s)' else '' end), E'\n' order by x.n)
    into l_cron
    from (select j.jobname, sum(extract(epoch from d.end_time - d.start_time) * 1000) as ms, count(*) as execs,
                 count(*) filter (where d.status = 'failed') as falhas,
                 row_number() over (order by sum(extract(epoch from d.end_time - d.start_time)) desc nulls last) as n
            from cron.job_run_details d join cron.job j on j.jobid = d.jobid
           where d.runid > coalesce(c.consumo_cursor_runid, 0) and d.runid <= v_max
             and d.start_time > v_ag - interval '7 days'
           group by j.jobname) x
   where x.n <= 5;

  select string_agg(format('%s. %s +%s (agora %s)', x.n, x.chave, pg_catalog.pg_size_pretty(x.cresceu),
                           pg_catalog.pg_size_pretty(x.bytes)), E'\n' order by x.n)
    into l_tab
    from (select s.chave, s.bytes, s.bytes - a.bytes as cresceu,
                 row_number() over (order by s.bytes - a.bytes desc) as n
            from ops.consumo_semana s
            join ops.consumo_semana a on a.tipo = 'tabela' and a.chave = s.chave
                                     and a.foto_em = (select max(z.foto_em) from ops.consumo_semana z
                                                       where z.tipo = 'tabela' and z.foto_em < v_ag)
           where s.tipo = 'tabela' and s.foto_em = v_ag and s.bytes > a.bytes) x
   where x.n <= 5;

  v_texto := ops.slack_esc(concat_ws(E'\n',
    'Consumo do banco — semana até ' || ops.fmt_hora(v_ag),
    case when v_prev is null then 'Primeira foto: sem comparação com a semana anterior.'
         when v_reset >= v_prev then 'Atenção: o banco reiniciou em ' || ops.fmt_hora(v_reset)
                                     || '; os números de consulta valem desde então.' end,
    'Tempo em consultas: ' || coalesce(ops.fmt_ms(v_tot), '0') ||
      case when v_tot_ant is not null then ' (semana anterior: ' || ops.fmt_ms(v_tot_ant) || ')' else '' end || '.',
    case when l_regr is not null then E'\n' || l_regr end,
    E'\nTop 10 por tempo total:', coalesce(l_tempo, '-'),
    E'\nTop 10 por chamadas:', coalesce(l_calls, '-'),
    E'\nRotinas que mais ocuparam o banco:', coalesce(l_cron, '-'),
    E'\nTabelas que mais cresceram:', coalesce(l_tab, case when v_prev is null then 'primeira foto' else 'nenhuma' end)));

  insert into ops.banco_alerta (tipo, valor, texto, detalhe)
  values ('consumo_semanal', v_nregr, v_texto,
          jsonb_build_object('foto_em', v_ag, 'foto_anterior', v_prev, 'stats_reset', v_reset))
  returning id into v_id;

  if c.consumo_enviar then
    select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = c.saturacao_webhook;
    if v_url is not null then
      v_req := net.http_post(url := v_url, body := jsonb_build_object('text', v_texto), timeout_milliseconds := 10000);
      update ops.banco_alerta set enviado = true, request_id = v_req where id = v_id;
    else
      update ops.banco_alerta set erro = 'sem ' || c.saturacao_webhook || ' no Vault' where id = v_id;
    end if;
  end if;

  update ops.config set consumo_cursor_runid = coalesce(v_max, consumo_cursor_runid) where id;
  delete from ops.consumo_semana s where s.foto_em < v_ag - interval '85 days';   -- 12 semanas + folga

  return jsonb_build_object('alerta', v_id, 'regressoes', v_nregr, 'request_id', v_req,
                            'ms', round(extract(epoch from clock_timestamp() - v_ag) * 1000));
end
$f$;

create function ops.fmt_ms(p double precision) returns text
language sql immutable set search_path = '' as $f$
  select case when p is null then '?'
              when p < 10 then replace(round(p::numeric, 2)::text, '.', ',') || ' ms'
              when p < 1000 then round(p::numeric) || ' ms'
              when p < 60000 then replace(round((p / 1000)::numeric, 1)::text, '.', ',') || ' s'
              when p < 3600000 then replace(round((p / 60000)::numeric, 1)::text, '.', ',') || ' min'
              else replace(round((p / 3600000)::numeric, 1)::text, '.', ',') || ' h' end
$f$;

create function ops.fmt_var(p_atual double precision, p_ant double precision) returns text
language sql immutable set search_path = '' as $f$
  select case when p_ant is null or p_ant <= 0 then null
              else case when p_atual >= p_ant then '+' else '' end
                   || round((100 * (p_atual - p_ant) / p_ant)::numeric) || '%' end
$f$;

select cron.schedule('ops-consumo-semanal', '6 11 * * 1',
                     $c$set statement_timeout = '60s'; select ops.consumo_semanal()$c$);

revoke all on table ops.consumo_semana from public, anon, authenticated, service_role;
revoke execute on function ops.consulta_curta(text, bigint), ops.consulta_curta_redigida(text, bigint), ops.consumo_semanal(), ops.fmt_ms(double precision),
                           ops.fmt_var(double precision, double precision)
  from public, anon, authenticated, service_role;

do $pos$
declare v text;
begin
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, 'null'), ' ') into v
    from pg_proc p
   where p.pronamespace = 'ops'::regnamespace
     and p.proname in ('consulta_curta', 'consulta_curta_redigida', 'consumo_semanal', 'fmt_ms', 'fmt_var')
     and (p.proacl is null or p.proacl::text ~ '(^|[{,])=X' or p.proacl::text ~ '(anon|authenticated|service_role)=');
  if v is not null then
    raise exception '20261009041000: EXECUTE aberto: %', v;
  end if;
  if has_table_privilege('anon', 'ops.consumo_semana', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('authenticated', 'ops.consumo_semana', 'select,insert,update,delete,truncate,references,trigger')
     or has_table_privilege('service_role', 'ops.consumo_semana', 'select,insert,update,delete,truncate,references,trigger') then
    raise exception '20261009041000: ops.consumo_semana acessível por anon/authenticated/service_role';
  end if;
end
$pos$;
-- ═══ TESTES ═══
do $t$
declare
  r jsonb := '{}'::jsonb; v jsonb; t0 timestamptz; v_f1 timestamptz; v_ch text;
begin
  -- T1 primeira foto (sem comparação)
  t0 := clock_timestamp(); v := ops.consumo_semanal();
  r := r || jsonb_build_object('T1', v, 'T1_ms_total', round(extract(epoch from clock_timestamp()-t0)*1000, 1),
          'T1_linhas', (select jsonb_object_agg(tipo, n) from (select tipo, count(*) n from ops.consumo_semana group by 1) x),
          'T1_texto_inicio', (select left(texto, 300) from ops.banco_alerta where id = (v->>'alerta')::bigint));
  select max(foto_em) into v_f1 from ops.consumo_semana;
  -- T2 segunda foto logo depois: há base → variação calculada, 0 regressões esperadas
  t0 := clock_timestamp(); v := ops.consumo_semanal();
  r := r || jsonb_build_object('T2', v, 'T2_ms_total', round(extract(epoch from clock_timestamp()-t0)*1000, 1),
          'T2_com_base', (select count(*) filter (where com_base) || '/' || count(*) from ops.consumo_semana
                           where tipo = 'consulta' and foto_em > v_f1));
  -- T3 regressão simulada: a consulta mais cara tinha média de 0,001 ms na "semana anterior"
  delete from ops.consumo_semana where foto_em > v_f1;
  select chave into v_ch from ops.consumo_semana where tipo = 'consulta' and foto_em = v_f1 order by acum_ms desc limit 1;
  update ops.consumo_semana set semana_calls = 1000, semana_ms = 1, acum_calls = acum_calls - 10, acum_ms = acum_ms - 500
   where tipo = 'consulta' and foto_em = v_f1 and chave = v_ch;
  v := ops.consumo_semanal();
  r := r || jsonb_build_object('T3', v, 'T3_linha_regressao',
          (select substring(texto from 'REGRESSÃO[^\n]{0,60}') from ops.banco_alerta where id = (v->>'alerta')::bigint));
  -- T4 envio ligado com segredo (URL inválida; transação desfeita, o pg_net nunca vê)
  perform vault.create_secret('https://exemplo.invalid/ensaio', 'ensaio_webhook_consumo');
  update ops.config set consumo_enviar = true, saturacao_webhook = 'ensaio_webhook_consumo' where id;
  v := ops.consumo_semanal();
  r := r || jsonb_build_object('T4', v, 'T4_enfileirado', (select enviado from ops.banco_alerta where id = (v->>'alerta')::bigint));
  update ops.config set consumo_enviar = false, saturacao_webhook = 'slack_webhook_rotinas' where id;
  -- T5 retenção: foto de 90 dias some
  insert into ops.consumo_semana (foto_em, tipo, chave, rotulo) values (now() - interval '90 days', 'tabela', 'x.y', 'x.y');
  perform ops.consumo_semanal();
  r := r || jsonb_build_object('T5_velha_sobrou', (select count(*) from ops.consumo_semana where foto_em < now() - interval '85 days'));
  -- T6 job e permissões
  r := r || jsonb_build_object('T6_job', (select schedule || ' | ' || command from cron.job where jobname = 'ops-consumo-semanal'),
          'T6_anon_exec', has_function_privilege('anon', 'ops.consumo_semanal()', 'execute'),
          'T6_public_acl', (select bool_or(proacl::text ~ '(^|[{,])=X') from pg_proc where pronamespace = 'ops'::regnamespace),
          'T6_anon_tab', has_table_privilege('anon', 'ops.consumo_semana', 'select'),
          'T6_service_tab', has_table_privilege('service_role', 'ops.consumo_semana', 'select,insert,update,delete,truncate,references,trigger'),
          'T6_tamanho_foto_kb', (select pg_total_relation_size('ops.consumo_semana') / 1024));
  -- T7 limpeza do texto: $$…$$ e $tag$…$tag$ com e-mail e token curto, E'..\'..', '' dobrado; DO e vault omitidos
  r := r || jsonb_build_object('T7_select', ops.consulta_curta_redigida(
            $q$select $$fulano@exemplo.com sk_ab12$$, $tg$x@y.com tk9z$tg$, E'it\'s a@b.co', 'joao''s' from t where id = 123456$q$, 11),
          'T7_do', ops.consulta_curta_redigida($q$DO $$ begin perform 'fulano@exemplo.com'; end $$$q$, 22),
          'T7_vault', ops.consulta_curta_redigida($q$select vault.create_secret($1, $2)$q$, 33),
          'T7_normalizado', ops.consulta_curta_redigida($q$select a from b where c = $1 and d->>$2 = $3$q$, 44));
  raise exception 'ENSAIO_OK %', r;
end
$t$;
rollback;
