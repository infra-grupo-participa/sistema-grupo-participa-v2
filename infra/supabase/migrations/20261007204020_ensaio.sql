-- Ensaio de 20261007z_perfis_e_guardas_sem_anon.sql: sonda de 32 guardas antes, 2 passadas, sonda depois, provas, ROLLBACK e sonda de novo.
-- Transação desfeita: nada persiste.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;
create function pg_temp.sonda(p_id uuid) returns jsonb language plpgsql as $s$
declare j jsonb; k text; a record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  j := jsonb_build_object(
    'equipe', public.gp_eh_equipe(), 'admin', public.gp_is_admin(),
    'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'cpf', public.gp_pode_ver_cpf(),
    'crm_gestor', crm.eh_gestor(), 'crm_comercial', crm.eh_comercial(), 'crm_catalogar', crm.pode_catalogar(),
    'remocao', public.ra_pode_ver(), 'pedidos', public.pa_pode_pedir(), 'placas', public.gp_pode_editar('placas'),
    'base_pessoas', pessoas.pode_ver(), 'gps_eh_equipe', gps.eh_equipe(), 'pa_pode_ver_doc', public.pa_pode_ver_doc(), 'alunos_ver_sensivel', public.tem_permissao(p_id, 'alunos.ver_sensivel'),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'gps', public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar('educacional', null), false),
    'ver_financeiro', public.gp_acesso_pode_ver('financeiro', null));
  for a in select d.key as dep, null::text as ar from acesso.departamento d union all select ar2.departamento, ar2.key from acesso.area ar2 loop
    j := j || jsonb_build_object('ed:' || a.dep || coalesce('/' || a.ar, ''), public.gp_acesso_pode_editar(a.dep, a.ar));
  end loop;
  return j;
end $s$;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 100);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.sonda(uuid), pg_temp.tenta(uuid, text) to authenticated;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '1 antes', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';

create function pg_temp.varre_anon() returns jsonb language plpgsql as $v$
declare r record; v_ok int := 0; v_err jsonb := '[]';
begin
  for r in select c.oid::regclass::text t from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where c.relkind in ('r', 'v', 'm', 'p') and n.nspname not in ('pg_catalog', 'information_schema', 'pg_toast')
              and has_schema_privilege('anon', n.oid, 'USAGE') and has_table_privilege('anon', c.oid, 'SELECT') loop
    begin
      execute format('set local role anon; select 1 from %s limit 1; reset role;', r.t);
      v_ok := v_ok + 1;
    exception when others then
      reset role;
      if sqlstate = '42501' and sqlerrm ~ 'function' then v_err := v_err || to_jsonb(r.t || ': ' || sqlerrm); else v_ok := v_ok + 1; end if;
    end;
  end loop;
  return jsonb_build_object('tabelas_lidas', v_ok, 'erros_de_funcao', v_err);
end $v$;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
insert into pg_temp._z_out (passo, linha) select 'z varredura como anon antes', pg_temp.varre_anon()::text;
select set_config('request.jwt.claims', '{}', true);

-- ===== PASSADA 1 =====
-- 20261007z: níveis de acesso, card 17tya50fkgz: permissões abertas em public.perfis e nas guardas.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007z_ensaio.sql (2 passadas, sonda de 32 guardas, varredura como anon, rollback).
--   Relatório: 20261007z.explain.md.
--
-- POR QUE (achado do pentester, "fora do escopo" na fase 3; inventário em 07/10/2026 no explain)
--   (a) INSERT em public.perfis para anon/authenticated: JÁ NÃO EXISTE (conferido: perfis só dá SELECT por coluna e
--       UPDATE em nome/avatar_url/atualizado_em a authenticated). Quem cria perfil é public.handle_new_user e
--       public.gps_handle_new_user, ambos SECURITY DEFINER, dono postgres. Nada a revogar de INSERT. Mas o PG 17 dá
--       MAINTAIN (VACUUM, ANALYZE, LOCK TABLE, REINDEX) a authenticated em perfis: revogado aqui.
--   (b) gp_is_admin(), gp_pode_editar(text), gp_pode_ver_financeiro(), gp_pode_operar_financeiro() executáveis por anon
--       (as duas primeiras pelo grant a PUBLIC). Inventário: nenhuma das 98 policies que as citam é avaliada como anon
--       (79 não valem para anon; 19 em tabelas sem privilégio de anon); nenhuma view as cita; das 14 funções SECURITY
--       INVOKER que as chamam, as 4 que anon executa são funções de GATILHO em gps.etapa1_clientes e gps.membros, onde
--       anon não escreve; o código dos repos não as chama como anon; pg_stat_statements (desde 19/08/2026) não tem
--       nenhuma chamada de anon, só de authenticated e postgres.
--
-- O QUE FAZ
--   1. revoke maintain on public.perfis from authenticated, anon.
--   2. As 4 funções: revoke execute from public, anon. Nas duas que dependiam de PUBLIC (gp_is_admin, gp_pode_editar),
--      grant execute explícito a TODOS os outros papéis que existem hoje (os mesmos que tinham pelo PUBLIC), para que só o
--      anon perca. As duas de financeiro já não tinham PUBLIC: só perdem o anon.
--
-- AS 5 PERGUNTAS
--   escala: 1 tabela, 4 funções. frequência: nenhuma mudança de custo. reversão: bloco REVERSÃO / rollback-permissoes.sql.
--
-- IDEMPOTENTE: revoke e grant são idempotentes.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- gp_is_admin() está na guarda da blindagem (grant/revoke é DDL nela)
do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso (20261007z): tirar execute de anon das guardas e MAINTAIN de perfis');
  end if;
end
$bl$;

-- 0. Premissa: ninguém além de postgres e service_role insere em perfis pela API
do $g$
begin
  if has_table_privilege('anon', 'public.perfis', 'INSERT') or has_table_privilege('authenticated', 'public.perfis', 'INSERT') then
    raise exception '20261007z: apareceu INSERT em perfis para anon/authenticated. Reler antes.';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.handle_new_user()'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.gps_handle_new_user()'::regprocedure) then
    raise exception '20261007z: handle_new_user/gps_handle_new_user deixaram de ser SECURITY DEFINER';
  end if;
end
$g$;

-- 1. MAINTAIN em perfis
revoke maintain on public.perfis from authenticated, anon;

-- 2. Guardas sem anon
revoke execute on function public.gp_is_admin(), public.gp_pode_editar(text),
  public.gp_pode_ver_financeiro(), public.gp_pode_operar_financeiro() from public, anon;
do $gr$
declare r record;
begin
  for r in select rolname from pg_roles where rolname !~ '^pg_' and rolname not in ('anon', 'postgres') loop
    execute format('grant execute on function public.gp_is_admin(), public.gp_pode_editar(text) to %I', r.rolname);
  end loop;
end
$gr$;
grant execute on function public.gp_pode_ver_financeiro(), public.gp_pode_operar_financeiro() to authenticated, service_role;

-- 3. Pós-condição
do $c$
declare f text;
begin
  foreach f in array array['public.gp_is_admin()', 'public.gp_pode_editar(text)', 'public.gp_pode_ver_financeiro()',
                           'public.gp_pode_operar_financeiro()'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception '20261007z: anon ainda executa %', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') or not has_function_privilege('service_role', f, 'execute') then
      raise exception '20261007z: authenticated/service_role perderam %', f;
    end if;
  end loop;
  if not has_function_privilege('disparos_app', 'public.gp_is_admin()', 'execute') then
    raise exception '20261007z: disparos_app perdeu gp_is_admin (tinha pelo PUBLIC)';
  end if;
  if has_table_privilege('authenticated', 'public.perfis', 'MAINTAIN') then
    raise exception '20261007z: authenticated ainda tem MAINTAIN em perfis';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/niveis-de-acesso/rollback-permissoes.sql (cérebro), ensaiado em 20261007z_ensaio.sql.

-- ===== PASSADA 2 =====
-- 20261007z: níveis de acesso, card 17tya50fkgz: permissões abertas em public.perfis e nas guardas.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007z_ensaio.sql (2 passadas, sonda de 32 guardas, varredura como anon, rollback).
--   Relatório: 20261007z.explain.md.
--
-- POR QUE (achado do pentester, "fora do escopo" na fase 3; inventário em 07/10/2026 no explain)
--   (a) INSERT em public.perfis para anon/authenticated: JÁ NÃO EXISTE (conferido: perfis só dá SELECT por coluna e
--       UPDATE em nome/avatar_url/atualizado_em a authenticated). Quem cria perfil é public.handle_new_user e
--       public.gps_handle_new_user, ambos SECURITY DEFINER, dono postgres. Nada a revogar de INSERT. Mas o PG 17 dá
--       MAINTAIN (VACUUM, ANALYZE, LOCK TABLE, REINDEX) a authenticated em perfis: revogado aqui.
--   (b) gp_is_admin(), gp_pode_editar(text), gp_pode_ver_financeiro(), gp_pode_operar_financeiro() executáveis por anon
--       (as duas primeiras pelo grant a PUBLIC). Inventário: nenhuma das 98 policies que as citam é avaliada como anon
--       (79 não valem para anon; 19 em tabelas sem privilégio de anon); nenhuma view as cita; das 14 funções SECURITY
--       INVOKER que as chamam, as 4 que anon executa são funções de GATILHO em gps.etapa1_clientes e gps.membros, onde
--       anon não escreve; o código dos repos não as chama como anon; pg_stat_statements (desde 19/08/2026) não tem
--       nenhuma chamada de anon, só de authenticated e postgres.
--
-- O QUE FAZ
--   1. revoke maintain on public.perfis from authenticated, anon.
--   2. As 4 funções: revoke execute from public, anon. Nas duas que dependiam de PUBLIC (gp_is_admin, gp_pode_editar),
--      grant execute explícito a TODOS os outros papéis que existem hoje (os mesmos que tinham pelo PUBLIC), para que só o
--      anon perca. As duas de financeiro já não tinham PUBLIC: só perdem o anon.
--
-- AS 5 PERGUNTAS
--   escala: 1 tabela, 4 funções. frequência: nenhuma mudança de custo. reversão: bloco REVERSÃO / rollback-permissoes.sql.
--
-- IDEMPOTENTE: revoke e grant são idempotentes.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- gp_is_admin() está na guarda da blindagem (grant/revoke é DDL nela)
do $bl$
begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('níveis de acesso (20261007z): tirar execute de anon das guardas e MAINTAIN de perfis');
  end if;
end
$bl$;

-- 0. Premissa: ninguém além de postgres e service_role insere em perfis pela API
do $g$
begin
  if has_table_privilege('anon', 'public.perfis', 'INSERT') or has_table_privilege('authenticated', 'public.perfis', 'INSERT') then
    raise exception '20261007z: apareceu INSERT em perfis para anon/authenticated. Reler antes.';
  end if;
  if not (select prosecdef from pg_proc where oid = 'public.handle_new_user()'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.gps_handle_new_user()'::regprocedure) then
    raise exception '20261007z: handle_new_user/gps_handle_new_user deixaram de ser SECURITY DEFINER';
  end if;
end
$g$;

-- 1. MAINTAIN em perfis
revoke maintain on public.perfis from authenticated, anon;

-- 2. Guardas sem anon
revoke execute on function public.gp_is_admin(), public.gp_pode_editar(text),
  public.gp_pode_ver_financeiro(), public.gp_pode_operar_financeiro() from public, anon;
do $gr$
declare r record;
begin
  for r in select rolname from pg_roles where rolname !~ '^pg_' and rolname not in ('anon', 'postgres') loop
    execute format('grant execute on function public.gp_is_admin(), public.gp_pode_editar(text) to %I', r.rolname);
  end loop;
end
$gr$;
grant execute on function public.gp_pode_ver_financeiro(), public.gp_pode_operar_financeiro() to authenticated, service_role;

-- 3. Pós-condição
do $c$
declare f text;
begin
  foreach f in array array['public.gp_is_admin()', 'public.gp_pode_editar(text)', 'public.gp_pode_ver_financeiro()',
                           'public.gp_pode_operar_financeiro()'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception '20261007z: anon ainda executa %', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') or not has_function_privilege('service_role', f, 'execute') then
      raise exception '20261007z: authenticated/service_role perderam %', f;
    end if;
  end loop;
  if not has_function_privilege('disparos_app', 'public.gp_is_admin()', 'execute') then
    raise exception '20261007z: disparos_app perdeu gp_is_admin (tinha pelo PUBLIC)';
  end if;
  if has_table_privilege('authenticated', 'public.perfis', 'MAINTAIN') then
    raise exception '20261007z: authenticated ainda tem MAINTAIN em perfis';
  end if;
end
$c$;

-- REVERSÃO: .maestri/entregas/niveis-de-acesso/rollback-permissoes.sql (cérebro), ensaiado em 20261007z_ensaio.sql.

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '2 depois', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '2 depois') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;

-- ===== PROVAS =====
-- varredura: como anon, ler cada tabela/view que anon pode ler (antes da migration a lista é a mesma; aqui depois)

select set_config('request.jwt.claims', '{"role":"anon"}', true);
insert into pg_temp._z_out (passo, linha) select 'z varredura como anon depois', pg_temp.varre_anon()::text;
set local role anon;
do $t$ begin perform public.gp_is_admin(); insert into pg_temp._z_out (passo, linha) values ('z anon chama gp_is_admin', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('z anon chama gp_is_admin', sqlstate || ' ' || sqlerrm); end $t$;
do $t$ begin perform public.gp_pode_ver_financeiro(); insert into pg_temp._z_out (passo, linha) values ('z anon chama gp_pode_ver_financeiro', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('z anon chama gp_pode_ver_financeiro', sqlstate || ' ' || sqlerrm); end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"caf36b74-0441-4f0b-b2a6-b3af88705f02","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'z authenticated (Caio) chama as 4', jsonb_build_object('admin', public.gp_is_admin(), 'editar_placas', public.gp_pode_editar('placas'), 'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro())::text;
do $t$ begin lock table public.perfis in access exclusive mode nowait; insert into pg_temp._z_out (passo, linha) values ('z authenticated LOCK ACCESS EXCLUSIVE em perfis', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('z authenticated LOCK ACCESS EXCLUSIVE em perfis', sqlstate || ' ' || sqlerrm); end $t$;
reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select 'z acls', (select jsonb_agg(p.oid::regprocedure::text || ' ' || p.proacl::text) from pg_proc p where p.oid in ('public.gp_pode_ver_financeiro()'::regprocedure))::text;

-- ===== ROLLBACK =====
-- Rollback da migration 20261007z_perfis_e_guardas_sem_anon. Numa transação (aplica_sql.py aplicar). Volta exatamente as
-- permissões de antes: PUBLIC executa gp_is_admin e gp_pode_editar; anon executa as duas de financeiro; authenticated tem
-- MAINTAIN em perfis. Os grants explícitos acrescentados aos outros papéis saem.
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $bl$ begin
  if to_regprocedure('blindagem.autorizar_guarda(text)') is not null then
    perform blindagem.autorizar_guarda('rollback das permissões (20261007z): devolve execute de PUBLIC/anon e MAINTAIN');
  end if;
end $bl$;
do $gr$ declare r record; begin
  for r in select rolname from pg_roles where rolname !~ '^pg_' and rolname not in ('anon', 'postgres', 'authenticated', 'service_role') loop
    execute format('revoke execute on function public.gp_is_admin(), public.gp_pode_editar(text) from %I', r.rolname);
  end loop;
end $gr$;
grant execute on function public.gp_is_admin(), public.gp_pode_editar(text) to public;
grant execute on function public.gp_pode_ver_financeiro(), public.gp_pode_operar_financeiro() to anon;
grant maintain on public.perfis to authenticated;

select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '3 depois do rollback', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), pg_temp.sonda(p.id)) from public.perfis p where p.status = 'ativo';
insert into pg_temp._z_out (passo, linha) select 'diferencas depois do rollback', coalesce((select jsonb_agg(jsonb_build_object('perfil', x.key, 'guarda', g.key, 'antes', g.value, 'depois', y.j -> x.key -> g.key)) from (select linha::jsonb j from pg_temp._z_out where passo = '1 antes') xa cross join lateral jsonb_each(xa.j) x cross join lateral jsonb_each(x.value) g cross join (select linha::jsonb j from pg_temp._z_out where passo = '3 depois do rollback') y where (y.j -> x.key -> g.key) is distinct from g.value), '[]')::text;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
insert into pg_temp._z_out (passo, linha) select 'z varredura como anon depois do rollback', pg_temp.varre_anon()::text;
insert into pg_temp._z_out (passo, linha) select 'z acls depois do rollback', (select jsonb_agg(p.oid::regprocedure::text || ' ' || p.proacl::text order by 1) from pg_proc p where p.oid in ('public.gp_is_admin()'::regprocedure, 'public.gp_pode_ver_financeiro()'::regprocedure))::text || ' | maintain auth perfis: ' || has_table_privilege('authenticated', 'public.perfis', 'MAINTAIN');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
