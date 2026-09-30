-- 20261003d — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada.
-- A rotina (antiga e nova) RODA aqui dentro e é desfeita (a antiga num bloco com exceção; a nova no rollback final).
-- Esperados:
--   0.corpo_vivo_md5 = t · 0.job = active f (se t, a migration aborta na guarda — resultado correto)
--   0.regra_antiga_mudaria = o que a 0045 mudaria hoje, por classe (cancelado/sem_acesso/… entram aí)
--   1.calc_linhas = n, n, n (1 linha por ativo) · 1.preservados = por motivo
--   2.rodada1_vs_previsto ok = t · 2.mudou_por_classe = só 'comum' (cancelado/sem_acesso/revogado/manual = 0)
--   2.historico_novas = linhas do trigger de histórico (situação/status mudaram) · 2.rodada2 = 0 · 2.job_depois active f
--   3.grants = anon f / authenticated f / service_role: calculada f, rotina t
--   3.authenticated_calculada = 42501 · 3.authenticated_rotina = 42501

begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to authenticated, anon;
create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;
create function pg_temp.z_err(p_passo text, p_sql text) returns void language plpgsql as $f$
begin
  execute p_sql;
  insert into pg_temp._z_out (passo, linha) values (p_passo, 'SEM ERRO');
exception when others then
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;
create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;
grant execute on function pg_temp.z_q(text, text), pg_temp.z_err(text, text), pg_temp.z_explain(text, text) to authenticated, anon;
-- papéis: equipe (dev/admin @advmais) e não-equipe (perfil ativo que não passa em gp_eh_equipe)
select set_config('z.eq', (select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
                             and p.cargo in ('dev', 'admin') order by p.id limit 1), true);

-- ─── 0. ANTES ───────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('0.corpo_vivo_md5', $q$select md5(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s', '', 'g')) = '1193539e1d62e23a5ee8f64f8d75c7dd' igual_0045
  from pg_proc where oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure$q$);
select pg_temp.z_q('0.job', $q$select jobid, jobname, schedule, active from cron.job where command ilike '%fn_recalcular_situacao_acesso%'$q$);
create temp table _z_sit on commit drop as
  select a.id, a.cancelado_em is not null as cancelado, a.situacao_acesso, a.status_acesso,
         case when a.cancelado_em is not null then 'cancelado'
              when a.situacao_acesso = 'sem_acesso' then 'sem_acesso'
              when a.acessos_revogados_em is not null then 'acessos_revogados'
              when nullif(btrim(a.tratamento_manual::text), '') is not null then 'tratamento_manual'
              else 'comum' end as classe
    from public.thb_alunos a;
select pg_temp.z_q('0.classes', $q$select classe, count(*) from _z_sit group by 1 order by 1$q$);

-- 0.1 regra ANTIGA (corpo vivo, 0045) rodada e desfeita dentro de um bloco com exceção: o que ela mudaria, por classe
do $z$
declare v text;
begin
  begin
    perform public.fn_recalcular_situacao_acesso();
    select string_agg(x.classe || '=' || x.n, ' ') into v
      from (select s.classe, count(*) n from public.thb_alunos a join _z_sit s on s.id = a.id
             where a.situacao_acesso is distinct from s.situacao_acesso or a.status_acesso is distinct from s.status_acesso
             group by 1 order by 1) x;
    raise exception 'ZOLD %', coalesce(v, 'nenhuma');
  exception when raise_exception then
    if sqlerrm like 'ZOLD %' then
      insert into pg_temp._z_out (passo, linha) values ('0.regra_antiga_mudaria', substr(sqlerrm, 6));
    else
      raise;
    end if;
  end;
end $z$;

-- ─── Migration (cópia literal do corpo da 20261003d) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_src   text;
  v_n     int;
  v_falta text;
begin
  -- 0.1 o job da rotina tem que estar DESLIGADO (religar é decisão à parte)
  select count(*) into v_n from cron.job j where j.command ilike '%fn_recalcular_situacao_acesso%' and j.active;
  if v_n > 0 then
    raise exception '20261003d: job do cron com fn_recalcular_situacao_acesso está ATIVO (%): desligar ou decidir antes', v_n;
  end if;
  -- 0.2 corpo vivo = 0045 (md5 sem comentários e sem espaços) ou já esta versão
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.fn_recalcular_situacao_acesso()');
  if v_src is null then
    raise exception '20261003d: public.fn_recalcular_situacao_acesso() não existe';
  end if;
  if md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g')) <> '1193539e1d62e23a5ee8f64f8d75c7dd'
     and position('fn_aluno_situacao_calculada' in v_src) = 0 then
    raise exception '20261003d: corpo vivo de fn_recalcular_situacao_acesso difere da 0045 (md5 normalizado %) — parar e comparar',
      md5(regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s', '', 'g'));
  end if;
  if pg_get_function_result('public.fn_recalcular_situacao_acesso()'::regprocedure) <> 'integer' then
    raise exception '20261003d: fn_recalcular_situacao_acesso não devolve integer';
  end if;
  -- 0.3 colunas
  select string_agg(x.c, ', ') into v_falta
    from unnest(array['id','eh_socio','regra_acesso','data_expiracao','situacao_acesso','status_acesso','atualizado_em',
                      'acessos_revogados_em','tratamento_manual','cancelado_em']) x(c)
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = 'thb_alunos' and c.column_name = x.c);
  if v_falta is not null then
    raise exception '20261003d: thb_alunos sem coluna(s): %', v_falta;
  end if;
  -- 0.4 ACL da rotina, para a conferência
  perform set_config('z20261003d.acl',
    (select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>')
       from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure), false);
end $guarda$;

-- ─── 1. Regra pura ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_situacao_calculada()
returns table (aluno_id uuid, situacao text, status text, preservado boolean, motivo_preserva text)
language sql
stable
as $fn$
  select a.id,
         (case
            when a.eh_socio or coalesce(a.regra_acesso, '') = 'Acompanha titular' then 'acompanha_titular'
            when a.data_expiracao is null                     then a.situacao_acesso  -- sem base: preserva
            when a.data_expiracao <  current_date             then 'vencido'
            when a.data_expiracao <= current_date + 30        then 'a_vencer'
            else 'em_dia'
          end)::text,
         (case
            when a.status_acesso = 'gratuidade'               then 'gratuidade'
            when a.eh_socio or coalesce(a.regra_acesso, '') = 'Acompanha titular' then a.status_acesso
            when a.data_expiracao is null                     then a.status_acesso
            when a.data_expiracao <  current_date             then 'vencido'
            when a.status_acesso = 'renovado'                 then 'renovado'
            else 'vigente'
          end)::text,
         (m.motivo is not null),
         m.motivo
    from public.thb_alunos a
   cross join lateral (
     select case when a.situacao_acesso = 'sem_acesso'                     then 'sem_acesso'
                 when a.acessos_revogados_em is not null                   then 'acessos_revogados'
                 when nullif(btrim(a.tratamento_manual::text), '') is not null then 'tratamento_manual'
            end as motivo) m
   where a.cancelado_em is null
$fn$;

comment on function public.fn_aluno_situacao_calculada() is
  '20261003d: situação/status de acesso calculados (regra da 0045) para alunos ativos, com preservado/motivo '
  '(sem_acesso, acessos_revogados, tratamento_manual). Interna: sem EXECUTE para public/anon/authenticated.';

revoke all on function public.fn_aluno_situacao_calculada() from public, anon, authenticated;

-- ─── 2. Rotina lê a regra pura ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_recalcular_situacao_acesso()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_mudados integer;
begin
  -- guarda: rotina de sistema (cron como postgres, ou service_role). Nunca pela API pública.
  if coalesce(auth.role(), '') in ('anon', 'authenticated') then
    raise exception 'fn_recalcular_situacao_acesso: rotina de sistema' using errcode = '42501';
  end if;

  -- regra em public.fn_aluno_situacao_calculada() (20261003d): só ativos; preserva sem_acesso/revogado/manual
  update public.thb_alunos a
     set situacao_acesso = c.situacao,
         status_acesso   = c.status,
         atualizado_em   = now()
    from public.fn_aluno_situacao_calculada() c
   where a.id = c.aluno_id
     and not c.preservado
     and (a.situacao_acesso is distinct from c.situacao
       or a.status_acesso   is distinct from c.status);

  get diagnostics v_mudados = row_count;

  if v_mudados > 0 then
    insert into public.thb_system_events (tipo, fonte, titulo, detalhe)
    values ('info', 'cron', 'Situação de acesso recalculada',
            jsonb_build_object('alunos_atualizados', v_mudados));
  end if;

  return v_mudados;
end
$fn$;

-- ─── 3. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
declare v_acl text;
begin
  select coalesce(array_to_string(array(select x::text from unnest(p.proacl) x order by 1), ','), '<null>') into v_acl
    from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure;
  if v_acl is distinct from current_setting('z20261003d.acl', true) then
    raise exception '20261003d: ACL da rotina mudou: antes % / depois %', current_setting('z20261003d.acl', true), v_acl;
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.fn_recalcular_situacao_acesso()'::regprocedure
                    and p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']) then
    raise exception '20261003d: rotina sem SECURITY DEFINER/search_path';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_situacao_calculada()'::regprocedure
                and (p.prosecdef or p.proconfig is not null or p.provolatile <> 's'
                     or p.prolang <> (select oid from pg_language where lanname = 'sql'))) then
    raise exception '20261003d: fn_aluno_situacao_calculada deixou de ser inlinável';
  end if;
  if exists (select 1 from unnest(array['public.fn_aluno_situacao_calculada()', 'public.fn_recalcular_situacao_acesso()']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
                 or exists (select 1 from pg_proc p where p.oid = f::regprocedure
                              and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) g
                                                                where g.grantee = 0 and g.privilege_type = 'EXECUTE')))) then
    raise exception '20261003d: função executável por PUBLIC/anon/authenticated';
  end if;
  if exists (select 1 from cron.job j where j.command ilike '%fn_recalcular_situacao_acesso%' and j.active) then
    raise exception '20261003d: job ficou ativo';
  end if;
end $confere$;

-- ─── 1. Regra nova, sem gravar ──────────────────────────────────────────────────────────────────────────────────────
create temp table _z_calc on commit drop as select * from public.fn_aluno_situacao_calculada();
select pg_temp.z_q('1.calc_linhas', $q$select count(*), count(distinct aluno_id), (select count(*) from public.thb_alunos where cancelado_em is null) ativos from _z_calc$q$);
select pg_temp.z_q('1.preservados', $q$select motivo_preserva, count(*) from _z_calc where preservado group by 1 order by 1$q$);
select pg_temp.z_q('1.transicoes', $q$select s.situacao_acesso || ' → ' || c.situacao, s.status_acesso || ' → ' || c.status, count(*)
  from _z_calc c join _z_sit s on s.id = c.aluno_id
 where not c.preservado and (s.situacao_acesso is distinct from c.situacao or s.status_acesso is distinct from c.status)
 group by 1, 2 order by 3 desc$q$);
select set_config('z.previsto', (select count(*)::text from _z_calc c join _z_sit s on s.id = c.aluno_id
  where not c.preservado and (s.situacao_acesso is distinct from c.situacao or s.status_acesso is distinct from c.status)), true);
select pg_temp.z_q('1.previsto', $q$select current_setting('z.previsto')$q$);
select pg_temp.z_explain('1.explain_calculada', 'select count(*) from public.fn_aluno_situacao_calculada()');

-- ─── 2. Rotina nova dentro do rollback ─────────────────────────────────────────────────────────────────────────────
select set_config('z.hist0', (select count(*)::text from public.thb_alunos_historico), true);
select set_config('z.rodada1', public.fn_recalcular_situacao_acesso()::text, true);
select pg_temp.z_q('2.rodada1_vs_previsto', $q$select current_setting('z.rodada1') rodada1, current_setting('z.previsto') previsto,
  current_setting('z.rodada1') = current_setting('z.previsto') ok$q$);
select pg_temp.z_q('2.mudou_por_classe', $q$select s.classe, count(*) from public.thb_alunos a join _z_sit s on s.id = a.id
  where a.situacao_acesso is distinct from s.situacao_acesso or a.status_acesso is distinct from s.status_acesso group by 1 order by 1$q$);
select pg_temp.z_q('2.historico_novas', $q$select count(*) - current_setting('z.hist0')::bigint from public.thb_alunos_historico$q$);
select pg_temp.z_q('2.rodada2', $q$select public.fn_recalcular_situacao_acesso()$q$);
select pg_temp.z_q('2.job_depois', $q$select jobid, active from cron.job where command ilike '%fn_recalcular_situacao_acesso%'$q$);

-- ─── 3. Permissões ──────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('3.grants', $q$select f, r, has_function_privilege(r, f, 'execute') from unnest(array['public.fn_aluno_situacao_calculada()','public.fn_recalcular_situacao_acesso()']) f, unnest(array['anon','authenticated','service_role']) r order by 1, 2$q$);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select pg_temp.z_err('3.authenticated_calculada', 'select count(*) from public.fn_aluno_situacao_calculada()');
select pg_temp.z_err('3.authenticated_rotina', 'select public.fn_recalcular_situacao_acesso()');
reset role;

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003d',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
