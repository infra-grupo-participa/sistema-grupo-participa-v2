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
