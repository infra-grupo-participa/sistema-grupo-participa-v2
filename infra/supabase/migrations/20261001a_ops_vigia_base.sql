-- 20261001a — Vigia das rotinas (1/5): schema ops, tabelas e o wrapper ops.cron_post.
--
-- POR QUÊ
--   net.http_post é assíncrono: o cron.job_run_details marca "succeeded" assim que o pedido entra na fila.
--   Medido em 30/09 00:45 UTC: 100% das execuções dos crons HTTP "succeeded" em 7 dias, enquanto
--   net._http_response (6 h) tinha 29 timeouts, 15×502, 14×500 e 1×546. Ninguém via.
--   O _http_response não guarda url nem jobname: sem o wrapper não dá para saber de quem é a resposta.
--
-- O QUE CRIA
--   ops.config            1 linha: enviar (false), cursor do cron.job_run_details, estado inicial, resumo diário.
--   ops.rotina            config por jobname: N falhas seguidas, janela sem sucesso, K ok para fechar, silêncio.
--   ops.rotina_estado     estado vivo por jobname (sequência de falhas/ok, último ok, incidente aberto).
--   ops.rotina_chamada    1 linha por net.http_post feito pelo wrapper (request_id, url SEM query, classe).
--   ops.rotina_alerta     o que o vigia decidiu avisar (enviado ou só gravado).
--   ops.cron_post(p_job, url, body, params, headers, timeout_milliseconds)
--       mesmos nomes/defaults de net.http_post (pg_net 0.19.5). Chama net.http_post e grava a chamada num
--       sub-bloco que engole erro. Diferenças de comportamento em relação a net.http_post:
--         (1) se ops.rotina.timeout_ms da rotina estiver preenchido, ele substitui o timeout do command
--             (seed: só ingest-mensageria-hourly = 15 s; mede 3,0–5,6 s na edge e o 5 s cortava respostas 200);
--         (2) piso global ops.config.timeout_minimo_ms — padrão 0 (desligado), teto 30 s.
--       Por que não um piso alto: o worker do pg_net 0.19.5 só pega o próximo lote quando o lote atual termina;
--       um pedido de 155 s seguraria a fila inteira (inclusive avisos de 10 s como ra_fn_avisar_n8n).
--       Rotina que dá 504 real (ingest-active, ingest-disparos) se conserta na edge, não com timeout maior.
--       O registro NUNCA derruba o cron. Headers e params NUNCA são gravados.
--
-- SEGURANÇA
--   Schema ops fechado para PUBLIC/anon/authenticated. O wrapper é SECURITY INVOKER e só o dono dos jobs
--   (postgres, conferido em cron.job) executa: aberto a PUBLIC ele seria proxy de SSRF com rótulo falso.
--   ⚠️ net.http_post continua com EXECUTE para PUBLIC (medido 30/09) — fora do escopo, ver ADR 0001.
--
-- REVERSÃO: ver 20261001c (desfaz os commands) e depois `drop schema ops cascade`.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $pre$
begin
  if exists (select 1 from pg_namespace where nspname = 'ops') then
    raise exception '20261001a: schema ops já existe — conferir antes de aplicar';
  end if;
  if exists (select 1 from cron.job where username <> 'postgres' and command ~ 'net\.http_post\(') then
    raise exception '20261001a: há job HTTP com dono ≠ postgres — o grant do wrapper precisa incluir esse dono';
  end if;
end
$pre$;

create schema ops;
revoke all on schema ops from public, anon, authenticated;
comment on schema ops is 'Vigia das rotinas pg_cron/pg_net. Interno: sem acesso de anon/authenticated. ADR 0001.';

create table ops.config (
  id                   boolean primary key default true check (id),
  enviar               boolean not null default false,
  cursor_runid         bigint,
  inicializado         boolean not null default false,
  ultimo_resumo_dia    date,
  ttl_resposta         interval not null default interval '6 hours',   -- pg_net.ttl medido 30/09
  prazo_sem_resposta   interval not null default interval '30 minutes',
  retencao_chamada     interval not null default interval '14 days',
  hora_resumo_utc      int not null default 11 check (hora_resumo_utc between 0 and 23),
  timeout_minimo_ms    int not null default 0 check (timeout_minimo_ms between 0 and 30000),
  atualizado_em        timestamptz not null default now()
);
comment on column ops.config.timeout_minimo_ms is 'Piso global do timeout do wrapper. Padrão 0 (desligado); teto 30 s porque o worker do pg_net 0.19.5 processa em lote e um pedido longo segura a fila. Preferir ops.rotina.timeout_ms.';
comment on column ops.config.enviar is 'false = o vigia só grava em ops.rotina_alerta; true = também posta no Slack (Vault slack_webhook_rotinas).';

create table ops.rotina (
  jobname          text primary key,
  n_falhas         int not null check (n_falhas >= 1),
  janela           interval not null check (janela >= interval '10 minutes'),
  k_ok             int not null default 3 check (k_ok >= 1),
  intervalo        interval,                 -- de onde N/janela saíram (medido ou do schedule)
  intervalo_fonte  text check (intervalo_fonte in ('medido_7d','schedule','manual')),
  timeout_ms       int check (timeout_ms between 1000 and 30000),   -- nulo = usa o do command
  silenciado_ate   timestamptz,
  command_antes    text,                     -- command antes da 20261001c (sem segredo: assert na c)
  criado_em        timestamptz not null default now()
);

create table ops.rotina_estado (
  jobname              text primary key,
  ativo                boolean,
  http                 boolean not null default false,
  rastreio             text not null default 'sql' check (rastreio in ('sql','wrapper','sem_rastreio','removido')),
  consec_falhas        int not null default 0,
  consec_ok            int not null default 0,
  ultimo_evento_em     timestamptz,
  ultima_classe        text,
  ultimo_ok_em         timestamptz,
  ultimo_erro          text,                 -- só no banco: curto e redigido (ops.redigir). NUNCA vai ao Slack
  ultima_falha         text,                 -- o que vai ao Slack: 'HTTP 502 · falha_http' / 'falha_sql' / ...
  observado_desde      timestamptz not null default now(),
  incidente_aberto_em  timestamptz,
  incidente_motivo     text,
  atualizado_em        timestamptz not null default now()
);

create table ops.rotina_chamada (
  request_id       bigint primary key,
  jobname          text not null,
  url              text not null,            -- sem query string
  enviado_em       timestamptz not null default now(),
  reconciliado_em  timestamptz,
  status           int,
  classe           text check (classe in ('ok','falha_http','timeout_cliente','sem_resposta','perdida')),
  erro             text
);
create index rotina_chamada_pendente_idx on ops.rotina_chamada (enviado_em) where reconciliado_em is null;
create index rotina_chamada_enviado_idx  on ops.rotina_chamada (enviado_em);

create table ops.rotina_alerta (
  id          bigint generated always as identity primary key,
  criado_em   timestamptz not null default now(),
  tipo        text not null check (tipo in ('ciclo','inicial','resumo')),
  mudancas    jsonb not null default '[]'::jsonb,
  texto       text not null,
  enviado     boolean not null default false,
  request_id  bigint
);
create index rotina_alerta_criado_idx on ops.rotina_alerta (criado_em);

insert into ops.config (id) values (true);

-- Wrapper. Mesma assinatura de net.http_post (pg_net 0.19.5) + p_job na frente.
create function ops.cron_post(
  p_job                text,
  url                  text,
  body                 jsonb   default '{}'::jsonb,
  params               jsonb   default '{}'::jsonb,
  headers              jsonb   default '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint
language plpgsql
security invoker
set search_path = ''
as $f$
declare
  v_id bigint;
  v_t  integer := timeout_milliseconds;
begin
  -- Timeout por rotina (ops.rotina.timeout_ms) e piso global (padrão 0). Falhou a leitura → o do command.
  begin
    select greatest(coalesce((select r.timeout_ms from ops.rotina r where r.jobname = p_job), timeout_milliseconds),
                    c.timeout_minimo_ms)
      into v_t from ops.config c where c.id;
  exception when others then
    v_t := timeout_milliseconds;
  end;
  v_id := net.http_post(url := url, body := body, params := params,
                        headers := headers, timeout_milliseconds := coalesce(v_t, timeout_milliseconds));
  begin
    insert into ops.rotina_chamada (request_id, jobname, url)
    values (v_id, coalesce(p_job, '?'), split_part(url, '?', 1));
  exception when others then
    null;  -- o registro nunca derruba a rotina; a falta dele aparece como "sem sucesso na janela"
  end;
  return v_id;
end
$f$;
comment on function ops.cron_post is 'net.http_post + registro em ops.rotina_chamada (sem headers/params). Só para commands de cron.job. ADR 0001.';

revoke all on all tables in schema ops from public, anon, authenticated;
revoke execute on all functions in schema ops from public, anon, authenticated;
grant usage on schema ops to postgres;
grant execute on function ops.cron_post(text, text, jsonb, jsonb, jsonb, integer) to postgres;

do $pos$
declare v_acl text;
begin
  select coalesce(proacl::text, 'null') into v_acl from pg_proc where oid = 'ops.cron_post'::regproc;
  if v_acl = 'null' or v_acl ~ '(^|[{,])=X' or v_acl ~ '(anon|authenticated)=' then
    raise exception '20261001a: proacl do wrapper aberto: %', v_acl;
  end if;
  if has_schema_privilege('anon', 'ops', 'usage') or has_schema_privilege('authenticated', 'ops', 'usage') then
    raise exception '20261001a: anon/authenticated ainda usam o schema ops';
  end if;
end
$pos$;
