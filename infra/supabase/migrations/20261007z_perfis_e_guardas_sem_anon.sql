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
