-- 20261001c — Vigia das rotinas (3/5): os crons HTTP passam a chamar ops.cron_post('<jobname>', ...).
--
-- O QUE MUDA: só o nome da função chamada. url, headers (Vault, pós-z94), body, timeout: idênticos.
--   net.http_post(  →  ops.cron_post('<jobname>',
--   Prova no ensaio: o command novo e o antigo são EXECUTADOS com ecos em pg_temp (nada é chamado) e o
--   resultado (url, body, params, headers, timeout) tem o mesmo md5; o md5 do header é conferido à parte.
--
-- ESCOPO (cron.job lido em 30/09 00:45 UTC, pós-z94)
--   1 6 7 9 11 16 17 18 21 22 25 26 34 37 56   (1, 6 e 34 inativos: reescritos igual, sem efeito até religar)
--   FORA: 2 ig-collect-quad-daily — inativo e passa body ::bytea, que net.http_post (0.19.5) não aceita
--         (só existe a versão jsonb). Já falharia hoje se religado; o wrapper não muda isso. Fica sem_rastreio.
--
-- GUARDAS
--   md5 do command vivo de cada job (30/09, pós-z94). Mudou → aborta, nada é alterado.
--   O conjunto de jobs com net.http_post( é exatamente {escopo} ∪ {2}. Job HTTP novo → aborta (decidir à mão).
--   'net.http_post(' aparece exatamente 1 vez (sensível e insensível a caixa).
--   command_antes não tem segredo: nenhum valor do Vault (≥ 8 chars) dentro dele, nenhum header de
--   segredo com literal, nenhum 'Bearer <literal>', nenhum literal com 32+ chars de token, nenhum JWT
--   (eyJ + 20) e nenhum bearer seguido de 20+ chars — os dois últimos sem depender de aspas.
--   Dono de cada job tem USAGE em ops e INSERT em ops.rotina_chamada (senão o registro some em silêncio).
--   Eco: confere que não sobra net.*/ops.* ANTES de cada execute (antigo e novo).
--   Dono de cada job pode executar ops.cron_post.
--
-- REVERSÃO (sem segredo: o command_antes já lê do Vault)
--   do $$ declare r record; begin
--     for r in select j.jobid, o.command_antes from ops.rotina o join cron.job j using (jobname)
--               where o.command_antes is not null and j.command ~ 'ops\.cron_post\(' loop
--       perform cron.alter_job(job_id := r.jobid, command := r.command_antes);
--     end loop; end $$;

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $c$
declare
  c_guarda constant jsonb := '{
    "1":"9eb8809bf845f4982e969cfa9bed8d86",  "6":"ff3dcaf8f1cf41b7e04fd170d8be9ace",
    "7":"aa5885b256daf8e4cd687496af02b35e",  "9":"a0fd2853970cf4f25a612f1ef77674f1",
    "11":"98f0f7f490dd46669990e5ad751f82ae", "16":"383426dc0cc3f8ecbb9f5ff9628d7e17",
    "17":"070933d60a91b966e1d513875c328d9d", "18":"c1ca79509d5fbe827f75d034ffc3a6fc",
    "21":"050b105c46b49648e83a9fc140f822e2", "22":"ddc27c00356defbd973d8e1be10e35a6",
    "25":"2eda6579644674e9b69cbc0ca86f702c", "26":"d86b2c5469eadf879ad76f3ce8f83a16",
    "34":"c25092c6b0067611e8165c7f587a7069", "37":"4bca786ab5ad8c6dd3143765bf7f0301",
    "56":"b212300affeb87efd6bba5cea9c50edf"}';
  c_fora constant bigint[] := array[2];
  v_ids   bigint[];
  v_md5   text;
  v_novo  text;
  v_velho jsonb;
  v_eco   jsonb;
  v_eco_velho text;
  v_eco_novo  text;
  v_n     int := 0;
  r       record;
begin
  -- 1. Conjunto de jobs HTTP
  select array_agg(jobid order by jobid) into v_ids from cron.job where command ~* 'net\.http_post\(';
  if v_ids is distinct from (select array_agg(x order by x)
                               from (select key::bigint x from jsonb_each_text(c_guarda)
                                     union select unnest(c_fora)) s) then
    raise exception '20261001c: jobs com net.http_post = %, diferente do escopo lido em 30/09', v_ids;
  end if;

  -- 2. Ecos (nada sai do banco). Mesmos defaults de net.http_post 0.19.5.
  create or replace function pg_temp.c_net_eco(
    url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer default 5000)
  returns jsonb language sql as $e$
    select jsonb_build_object('url', url, 'body', body, 'params', params, 'headers', headers, 't', timeout_milliseconds)
  $e$;
  create or replace function pg_temp.c_ops_eco(
    p_job text, url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
    headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer default 5000)
  returns jsonb language sql as $e$
    select jsonb_build_object('job', p_job, 'url', url, 'body', body, 'params', params, 'headers', headers, 't', timeout_milliseconds)
  $e$;

  for r in select j.jobid, j.jobname, j.username, j.command, g.value as md5_esperado
             from cron.job j join jsonb_each_text(c_guarda) g on g.key::bigint = j.jobid
            order by j.jobid loop
    -- 3. Guardas
    if md5(r.command) <> r.md5_esperado then
      raise exception '20261001c: command do job % mudou desde 30/09 — reler antes de aplicar', r.jobid;
    end if;
    if (select count(*) from regexp_matches(r.command, 'net\.http_post\(', 'g')) <> 1
       or (select count(*) from regexp_matches(r.command, 'net\.http_post\(', 'gi')) <> 1 then
      raise exception '20261001c: job % não tem net.http_post( exatamente 1 vez', r.jobid;
    end if;
    if exists (select 1 from vault.decrypted_secrets s
                where length(s.decrypted_secret) >= 8 and position(s.decrypted_secret in r.command) > 0)
       or r.command ~* '''(x-webhook-secret|x-sync-chave|apikey)''\s*,\s*'''
       or r.command ~ '''Bearer [^'']+'''
       or r.command ~ '''[A-Za-z0-9_\-\.]{32,}'''
       or r.command ~ 'eyJ[A-Za-z0-9_-]{20,}'
       or r.command ~* 'bearer\s+[A-Za-z0-9_\-\.]{20,}' then
      raise exception '20261001c: job % tem segredo literal no command — não copiar para ops.rotina', r.jobid;
    end if;
    if not has_function_privilege(r.username, 'ops.cron_post(text, text, jsonb, jsonb, jsonb, integer)', 'execute')
       or not has_schema_privilege(r.username, 'ops', 'usage')
       or not has_table_privilege(r.username, 'ops.rotina_chamada', 'insert') then
      raise exception '20261001c: job % roda como %, que não executa ops.cron_post', r.jobid, r.username;
    end if;

    -- 4. Command novo
    v_novo := replace(r.command, 'net.http_post(', 'ops.cron_post(' || quote_literal(r.jobname) || ', ');

    -- 5. Prova: executa antigo e novo com eco e compara
    v_eco_velho := replace(r.command, 'net.http_post(', 'pg_temp.c_net_eco(');
    v_eco_novo  := replace(v_novo, 'ops.cron_post(', 'pg_temp.c_ops_eco(');
    if lower(v_eco_velho) ~ '(net|ops)\.' or lower(v_eco_novo) ~ '(net|ops)\.' then
      raise exception '20261001c: job % ainda chamaria net.*/ops.* depois do eco — não executar', r.jobid;
    end if;
    execute v_eco_velho into v_velho;
    execute v_eco_novo into v_eco;
    if v_eco->>'job' is distinct from r.jobname
       or md5((v_eco - 'job')::text) is distinct from md5(v_velho::text)
       or md5((v_eco->'headers')::text) is distinct from md5((v_velho->'headers')::text) then
      raise exception '20261001c: job % — chamada nova difere da antiga', r.jobid;
    end if;

    -- 6. Guarda o antes e troca
    update ops.rotina set command_antes = r.command where jobname = r.jobname;
    if not found then
      raise exception '20261001c: job % (%) sem linha em ops.rotina — aplicar a 20261001b antes', r.jobid, r.jobname;
    end if;
    perform cron.alter_job(job_id := r.jobid, command := v_novo);
    v_n := v_n + 1;
  end loop;

  -- 7. Pós-condição
  if v_n <> 15 then
    raise exception '20261001c: reescrevi % jobs, esperado 15', v_n;
  end if;
  select array_agg(jobid order by jobid) into v_ids from cron.job where command ~* 'net\.http_post\(';
  if v_ids is distinct from c_fora then
    raise exception '20261001c: sobrou net.http_post em %', v_ids;
  end if;
  select md5(string_agg(md5(command), '' order by jobid)) into v_md5 from cron.job where command ~ 'ops\.cron_post\(';
  drop function pg_temp.c_net_eco(text, jsonb, jsonb, jsonb, integer);
  drop function pg_temp.c_ops_eco(text, text, jsonb, jsonb, jsonb, integer);
  raise notice '20261001c: 15 jobs no wrapper; chamadas conferidas por eco; md5 do conjunto novo = %', v_md5;
end
$c$;
