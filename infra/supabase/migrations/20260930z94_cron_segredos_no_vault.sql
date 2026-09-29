-- 20260930z94 — Crons deixam de carregar segredo em texto: header lido do Vault na hora da chamada.
--
-- POR QUÊ
--   cron.job.command guardava o valor do x-webhook-secret (11 jobs, 1 valor) e um Bearer (job 1) em texto puro.
--   Quem lê cron.job (ou cron.job_run_details, que copia o command a cada execução) lê o segredo.
--   O job 2 lia o Bearer de uma GUC (app.ig_collect_secret), e GUC é legível por qualquer role conectada
--   (current_setting / pg_db_role_setting). Medido em 29/09: pg_db_role_setting tem 0 linhas com ig_collect
--   e current_setting('app.ig_collect_secret', true) volta NULL — a GUC não está gravada no banco hoje (o job 2
--   mandaria "Bearer " vazio). sip/supabase/migrations/0035_pg_cron_ig.sql:8 manda gravá-la (no arquivo há um
--   placeholder, não o valor). Mesmo assim o job 2 passa para o Vault (ninguém mais precisa gravar a GUC)
--   e a migration aborta se a GUC estiver gravada no momento do apply.
--   Pendência fora daqui: sip 0035 e docs/06-integrations.md / 07-security.md ainda mandam gravar a GUC.
--   Molde: cron 56 (fin-hotmart-catalogo) — (select decrypted_secret from vault.decrypted_secrets where name = ...).
--
-- ESCOPO (cron.job lido em 29/09; valores NUNCA escritos aqui — lidos do command vivo por regexp)
--   header x-webhook-secret → Vault 'cron_webhook_secret'
--      9 ingest-meta-5min          11 ingest-active-5min         16 ingest-criativos-15min
--     17 ingest-paginas-15min      18 ingest-sendflow-30min      21 ingest-google-30min
--     22 reconcilia-grupo-30min    25 reler-leads-incompletos    26 ingest-mensageria-hourly
--     34 ingest-aquecimento-15min (inativo)                      37 ingest-alunos-historico-diario
--   header Authorization: Bearer → Vault 'cron_ig_collect_bearer' (edge sip/supabase/functions/ig-collect)
--      1 ig-collect-daily (inativo)       — literal no command
--      2 ig-collect-quad-daily (inativo)  — GUC app.ig_collect_secret (reset só se estiver gravada;
--                                          hoje não está. Como postgres o reset dá 42501: se a GUC aparecer, aborta)
--   FORA: 56 (já no molde) · 57/61/63 (outro executor, z90/resolvedor).
--
-- GUARDAS
--   md5 do command vivo de cada job (29/09). Mudou → aborta, nada é alterado.
--   Dono de cada job alvo precisa ler vault.decrypted_secrets.
--   Exatamente 1 valor distinto de x-webhook-secret em todo cron.job e exatamente os 11 jobs acima com ele.
--   Nome no Vault já existente com OUTRO valor, ou valor já no Vault com OUTRO nome → aborta (decidir à mão).
--   Cada command tem o padrão exatamente 1 vez.
--   GUC: nenhum outro job nem função (pg_proc.prosrc) usa app.ig_collect_secret antes do reset.
--   Pós-condição A: nenhum command de cron.job contém mais os valores, o padrão literal ou a GUC.
--   Pós-condição B: o command novo é EXECUTADO com net.http_post trocado por um eco em pg_temp (aborta se
--   sobrar qualquer net.* depois da troca); o header resultante tem o mesmo md5 do valor antigo.
--
-- NÃO FAZ
--   Não limpa cron.job_run_details. Não rotaciona. Não mexe em edge function. Não gera .backup-antes.sql:
--   o command antigo contém o segredo — a reversão é a descrita abaixo.
--
-- ⚠️ APLICAR A z94 NÃO FECHA A EXPOSIÇÃO — ROTAÇÃO É OBRIGATÓRIA (fora deste arquivo)
--   O valor atual já vazou: histórico do repo controle-de-eventos (commit 3b9d763), transcripts locais e
--   cron.job_run_details. A z94 só impede que o PRÓXIMO valor vá parar em texto.
--   Ordem da rotação (nunca deixar WEBHOOK_SECRET vazia nas edges):
--     1. edges com _shared/webhook-auth.ts (aceita WEBHOOK_SECRET ou WEBHOOK_SECRET_NEXT) no ar;
--        gravar o valor novo em WEBHOOK_SECRET_NEXT.
--     2. vault.update_secret(<id de cron_webhook_secret>, <novo>) — crons passam a mandar o novo.
--     3. conferir 1 execução de cada job com 200; então WEBHOOK_SECRET := novo; remover WEBHOOK_SECRET_NEXT.
--     4. Bearer do ig-collect (cron_ig_collect_bearer / env IG_COLLECT_SECRET): trocar na env e no Vault juntos.
--   Depois da rotação: purgar cron.job_run_details dos jobs 1,2,9,11,16,17,18,21,22,25,26,34,37
--   (o command antigo, com o valor, está copiado em cada linha).
--
-- PROVA PÓS-APPLY (anotar ts_apply = now() no momento do apply)
--   Baseline (antes):
--     select count(*) filter (where status_code = 401) as r401, count(*) as total
--       from net._http_response where created > now() - interval '6 hours';
--   Depois, janela de 60 min:
--     select status_code, count(*) from net._http_response where created > :ts_apply group by 1;
--     select jobid, status, count(*) from cron.job_run_details
--      where start_time > :ts_apply and jobid in (2,9,11,16,17,18,21,22,25,26,37) group by 1,2;
--   Quando cada job prova: 9/11 em +5 min (11 roda */15; 9 no minuto 5 de hora par) · 16/17 em +15 min
--   (min 40 / min 25) · 18/21/22 em +30 min (*/30 / min 35 / min 15 de hora par) · 26 em +60 min (min 50) ·
--   25 no próximo */15 · 2 conforme schedule (0,6,12,18h — está INATIVO, só prova se reativado) ·
--   37 no dia seguinte (04:00 UTC).
--   1 e 34 estão INATIVOS: sem prova até reativar.
--   Critério: zero 401 na janela e número de 200 ≥ número de execuções succeeded dos jobs acima.
--
-- REVERSÃO
--   cron.alter_job(jobid, command := <command antigo>) — o antigo tem o segredo; recuperar pelo Vault:
--   replace(command_novo, '(select decrypted_secret ... = ''cron_webhook_secret'')', quote_literal(<valor do vault>)).
--   Não recomendado: reexpõe o segredo. Job 2: voltar para current_setting('app.ig_collect_secret', true).
--
-- RISCO OPERACIONAL
--   Apagar/renomear o secret no Vault → header vira null → edge devolve 401 em silêncio (net.http_post é assíncrono).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $z94$
declare
  c_nome_webhook constant text := 'cron_webhook_secret';
  c_nome_bearer  constant text := 'cron_ig_collect_bearer';
  c_jobs_webhook constant bigint[] := array[9,11,16,17,18,21,22,25,26,34,37];
  c_guarda constant jsonb := '{
    "1":"6c56a2c3d9d5d33ae601d75ef016256e",  "2":"28460b2e0becbdb5f001b303438d2a47",
    "9":"23b18378e9d9d5df1bff9ea8c7d04579",
    "11":"00bee290956fe03975b38fd8e1afa87e", "16":"6847184bf5bbc3bd249a90229a6281d3",
    "17":"ef892f4c353387ae3f58f944721d3930", "18":"2cdaae106845af9ce6f9f7d9feb6ca33",
    "21":"93472a1683320c421cd446546f2541e1", "22":"5c7820a68fce2d69bbd3b9772339b064",
    "25":"ba5b825167f2957a6be0fae583b7a935", "26":"21ae264889d9f8e55488fdb751524e8a",
    "34":"d3e168c26f13329e4458d7c76f78b33d", "37":"1191c9eeba8ac5eff5eb5be18229389c"}';
  -- grupos: 1 e 2 = espaços em volta da vírgula; 3 = valor
  c_re_webhook constant text := '''x-webhook-secret''(\s*),(\s*)''([^'']+)''';
  c_re_bearer  constant text := '''Authorization''(\s*),(\s*)''Bearer ([^'']+)''';
  c_re_guc     constant text := 'current_setting\(\s*''app\.ig_collect_secret''\s*,\s*true\s*\)';
  c_ler_webhook constant text := '(select decrypted_secret from vault.decrypted_secrets where name = ''cron_webhook_secret'')';
  c_ler_bearer  constant text := '(select decrypted_secret from vault.decrypted_secrets where name = ''cron_ig_collect_bearer'')';
  v_webhook text;
  v_bearer  text;
  v_n       int;
  v_ids     bigint[];
  v_novo    text;
  v_h       jsonb;
  r         record;
  s         record;
begin
  -- 1. Guarda md5 do command vivo
  for r in select key::bigint as jobid, value as md5_esperado from jsonb_each_text(c_guarda) loop
    select md5(command) into v_novo from cron.job where jobid = r.jobid;
    if v_novo is null then
      raise exception 'z94: job % não existe mais', r.jobid;
    elsif v_novo <> r.md5_esperado then
      raise exception 'z94: command do job % mudou desde 29/09 — reler antes de aplicar', r.jobid;
    end if;
  end loop;

  -- 1b. Trava: o dono de cada job alvo precisa ler o Vault, senão o header vira null em produção
  for r in select jobid, username from cron.job
            where jobid in (select key::bigint from jsonb_each_text(c_guarda)) loop
    if not has_table_privilege(r.username, 'vault.decrypted_secrets', 'select') then
      raise exception 'z94: job % roda como %, que não lê vault.decrypted_secrets', r.jobid, r.username;
    end if;
  end loop;

  -- 1c. GUC: só o job 2 pode usá-la (senão o reset quebra outro consumidor)
  select array_agg(jobid order by jobid) into v_ids from cron.job where command ~* 'ig_collect_secret';
  if v_ids is distinct from array[2::bigint] then
    raise exception 'z94: jobs que usam app.ig_collect_secret = %, esperado {2}', v_ids;
  end if;
  if exists (select 1 from pg_proc where prosrc ilike '%ig_collect_secret%') then
    raise exception 'z94: há função usando app.ig_collect_secret — revisar antes do reset';
  end if;

  -- 2. Extrai os valores (só em variável; nunca em raise/notice)
  select count(distinct (regexp_match(command, c_re_webhook))[3]),
         min((regexp_match(command, c_re_webhook))[3]),
         array_agg(jobid order by jobid)
    into v_n, v_webhook, v_ids
    from cron.job where command ~ c_re_webhook;
  if v_n <> 1 then
    raise exception 'z94: esperado 1 valor distinto de x-webhook-secret, achei %', v_n;
  end if;
  if v_ids <> c_jobs_webhook then
    raise exception 'z94: jobs com x-webhook-secret literal = %, esperado %', v_ids, c_jobs_webhook;
  end if;

  select (regexp_match(command, c_re_bearer))[3] into v_bearer from cron.job where jobid = 1;
  if v_bearer is null then
    raise exception 'z94: job 1 sem Bearer literal';
  end if;

  -- 3. Vault: cria se não existe; reexecução com mesmo valor é aceita
  for s in select * from (values (c_nome_webhook, v_webhook,
                                  'Header x-webhook-secret dos crons de ingest (pg_cron -> edges; conferido contra WEBHOOK_SECRET). Movido de cron.job em 30/09/2026 (z94).'),
                                 (c_nome_bearer, v_bearer,
                                  'Bearer dos crons 1/2 ig-collect (edge confere IG_COLLECT_SECRET). Movido de cron.job em 30/09/2026 (z94).'))
                        as t(nome, valor, descricao) loop
    if exists (select 1 from vault.secrets where name = s.nome) then
      if not exists (select 1 from vault.decrypted_secrets
                      where name = s.nome and md5(decrypted_secret) = md5(s.valor)) then
        raise exception 'z94: Vault já tem % com OUTRO valor', s.nome;
      end if;
    elsif exists (select 1 from vault.decrypted_secrets where md5(decrypted_secret) = md5(s.valor)) then
      raise exception 'z94: valor de % já está no Vault com outro nome — decidir qual usar', s.nome;
    else
      perform vault.create_secret(s.valor, s.nome, s.descricao);
    end if;
  end loop;

  -- 4. Troca literal/GUC → leitura do Vault, pelo command vivo
  for r in select jobid, command from cron.job where jobid = any(c_jobs_webhook) order by jobid loop
    if (select count(*) from regexp_matches(r.command, c_re_webhook, 'g')) <> 1 then
      raise exception 'z94: job % tem o header x-webhook-secret mais de 1 vez', r.jobid;
    end if;
    v_novo := regexp_replace(r.command, c_re_webhook, '''x-webhook-secret''\1,\2' || c_ler_webhook);
    perform cron.alter_job(job_id := r.jobid, command := v_novo);
  end loop;

  select command into v_novo from cron.job where jobid = 1;
  if (select count(*) from regexp_matches(v_novo, c_re_bearer, 'g')) <> 1 then
    raise exception 'z94: job 1 tem o Bearer mais de 1 vez';
  end if;
  v_novo := regexp_replace(v_novo, c_re_bearer, '''Authorization''\1,\2''Bearer '' || ' || c_ler_bearer);
  perform cron.alter_job(job_id := 1, command := v_novo);

  select command into v_novo from cron.job where jobid = 2;
  if (select count(*) from regexp_matches(v_novo, c_re_guc, 'g')) <> 1 then
    raise exception 'z94: job 2 não tem current_setting(app.ig_collect_secret) exatamente 1 vez';
  end if;
  v_novo := regexp_replace(v_novo, c_re_guc, c_ler_bearer);
  perform cron.alter_job(job_id := 2, command := v_novo);

  -- 4b. GUC fora do banco. Só roda se estiver gravada (medido 29/09: 0 linhas em pg_db_role_setting).
  --     O reset incondicional falha como postgres (42501 "permission denied to set parameter", ensaio 29/09):
  --     se a GUC existir, a migration aborta aqui e o reset tem de ser feito pelo supabase_admin/suporte.
  if exists (select 1 from pg_db_role_setting where setconfig::text like '%ig_collect%') then
    execute 'alter database postgres reset app.ig_collect_secret';
  end if;

  -- 5. Pós-condição A
  if exists (select 1 from cron.job
              where position(v_webhook in command) > 0 or position(v_bearer in command) > 0
                 or command ~ c_re_webhook or command ~ c_re_bearer or command ~* 'ig_collect_secret') then
    raise exception 'z94: ainda há segredo literal ou GUC em cron.job';
  end if;
  if exists (select 1 from pg_db_role_setting where setconfig::text like '%ig_collect%') then
    raise exception 'z94: app.ig_collect_secret continua em pg_db_role_setting';
  end if;

  -- 6. Pós-condição B: executa o command novo com um eco no lugar de net.http_post (nada é chamado)
  --    duas assinaturas: body jsonb (12 jobs) e body bytea (job 2)
  create or replace function pg_temp.z94_http_post_eco(
    url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000)
  returns jsonb language sql as $f$ select headers $f$;
  create or replace function pg_temp.z94_http_post_eco(
    url text, body bytea, params jsonb default '{}'::jsonb,
    headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000)
  returns jsonb language sql as $f$ select headers $f$;

  for r in select jobid, command from cron.job
            where jobid = any(c_jobs_webhook || array[1,2]::bigint[]) order by jobid loop
    if position('net.http_post(' in r.command) = 0 then
      raise exception 'z94: job % não chama net.http_post( — eco não se aplica', r.jobid;
    end if;
    v_novo := replace(r.command, 'net.http_post(', 'pg_temp.z94_http_post_eco(');
    if lower(v_novo) ~ 'net\.' then
      raise exception 'z94: job % ainda chamaria net.* depois do eco — não executar', r.jobid;
    end if;
    execute v_novo into v_h;
    if r.jobid in (1, 2) then
      if md5(v_h->>'Authorization') is distinct from md5('Bearer ' || v_bearer) then
        raise exception 'z94: job % — Authorization novo difere do Bearer do job 1', r.jobid;
      end if;
    elsif md5(v_h->>'x-webhook-secret') is distinct from md5(v_webhook) then
      raise exception 'z94: job % — header novo difere do antigo', r.jobid;
    end if;
  end loop;

  drop function pg_temp.z94_http_post_eco(text, jsonb, jsonb, jsonb, integer);
  drop function pg_temp.z94_http_post_eco(text, bytea, jsonb, jsonb, integer);
  raise notice 'z94: 13 jobs lendo do Vault; headers conferidos por md5; GUC ausente';
end
$z94$;
