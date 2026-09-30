-- 20261003g — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada.
-- Esperados:
--   0.candidatas / 0.total = 18 tabelas (15 thb_alunos parece_thb_alunos = t + 3 de ativações de 01/07)
--   0.dependentes = view 0 · fk 0 · funcao 0 (qualquer > 0: a migration aborta — resultado correto, reportar)
--   1.movidas = 18 · 0 · 18 · 1.schema = f, f, (service_role informativo)
--   1.anon_le / 1.authenticated_le = 42501 · 1.authenticated_public = 42P01 (não está mais em public)
--   2.revertida = 18 em public · 0 em arquivo · 18 com o comentário original
--
-- RESULTADO (30/09/2026, produção). 1ª rodada: a guarda abortou com 18 candidatas (esperado 15) — além dos 15
-- thb_alunos_* havia 3 backups de ativações de 01/07, também com SELECT para anon. Decisão: fechar a classe, arquivar
-- os 18. 2ª rodada: 0.total (18, 15 thb_alunos, 18 anon_le) · dependentes view 0 · fk 0 · função 0 · arquivo não existia
--   1.movidas (18, 0, 18) · 1.schema anon f, authenticated f, service_role f · anon_le / authenticated_le = 42501
--   authenticated_public = 42P01 · 2.revertida (18, 0, 18). Aplicada em seguida.

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
create temp table _z_bkp on commit drop as
select c.oid, c.relname, c.reltuples::bigint as linhas_est, obj_description(c.oid, 'pg_class') as cmt,
       exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'socio_de_aluno_id' and not a.attisdropped) as parece_thb_alunos,
       has_table_privilege('anon', c.oid, 'select') as anon_le
  from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
   and (c.relname like '%\_bkp\_%' or c.relname like '%\_bak\_%');
select pg_temp.z_q('0.candidatas', $q$select relname, linhas_est, parece_thb_alunos, anon_le from _z_bkp order by relname$q$);
select pg_temp.z_q('0.total', $q$select count(*), count(*) filter (where parece_thb_alunos) thb_alunos, count(*) filter (where anon_le) anon_le from _z_bkp$q$);
select pg_temp.z_q('0.dependentes', $q$select 'view' tipo, count(*) from pg_depend d join pg_rewrite rw on rw.oid = d.objid
   where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
     and d.refobjid in (select oid from _z_bkp) and rw.ev_class <> d.refobjid
  union all
  select 'fk', count(*) from pg_constraint k where k.contype = 'f' and k.confrelid in (select oid from _z_bkp)
     and k.conrelid not in (select oid from _z_bkp)
  union all
  select 'funcao', count(*) from pg_proc p join _z_bkp b on p.prosrc ilike '%' || b.relname || '%'
   where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)$q$);
select pg_temp.z_q('0.arquivo_existe', $q$select to_regnamespace('arquivo') is not null$q$);

-- ─── Migration (cópia literal do corpo da 20261003g) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas + movimento (um bloco: a lista é calculada uma vez) ─────────────────────────────────────────────────
create schema if not exists arquivo;
revoke all on schema arquivo from public, anon, authenticated;
comment on schema arquivo is
  'Tabelas arquivadas (backups). Sem USAGE para public/anon/authenticated; fora da API. Nunca DROP sem decisão do dono.';

do $g$
declare
  v_alvo  oid[];
  v_n     int;
  v_dep   text;
  r       record;
begin
  if exists (select 1 from pg_class c where c.relnamespace = 'arquivo'::regnamespace
                and obj_description(c.oid, 'pg_class') like '20261003g:%') then
    raise exception '20261003g: já aplicada (há tabela em arquivo com o comentário desta migration)';
  end if;

  select array_agg(c.oid order by c.relname) into v_alvo
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
     and (c.relname like '%\_bkp\_%' or c.relname like '%\_bak\_%');
  v_n := coalesce(cardinality(v_alvo), 0);
  if v_n <> 18 then
    raise exception '20261003g: % tabelas de backup em public (esperado 18) — conferir a lista no ensaio', v_n;
  end if;

  -- dependentes: views/matviews de OUTRA relação, FK de outra tabela, função que cita o nome, job do cron
  select string_agg(distinct x.d, '; ') into v_dep
    from (
      select format('view %s → %s', rw.ev_class::regclass, d.refobjid::regclass) as d
        from pg_depend d
        join pg_rewrite rw on rw.oid = d.objid
       where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
         and d.refobjid = any (v_alvo) and rw.ev_class <> d.refobjid
      union all
      select format('fk %s → %s', k.conrelid::regclass, k.confrelid::regclass)
        from pg_constraint k
       where k.contype = 'f' and k.confrelid = any (v_alvo) and not (k.conrelid = any (v_alvo))
      union all
      select format('função %s cita %s', p.oid::regprocedure, c.relname)
        from pg_proc p
        join pg_class c on c.oid = any (v_alvo)
       where p.pronamespace not in ('pg_catalog'::regnamespace, 'information_schema'::regnamespace)
         and p.prosrc ilike '%' || c.relname || '%'
    ) x;
  if v_dep is null and to_regclass('cron.job') is not null then
    execute $q$select string_agg(format('cron %s cita %s', j.jobid, c.relname), '; ')
                from cron.job j join pg_class c on c.oid = any ($1) where j.command ilike '%' || c.relname || '%'$q$
      into v_dep using v_alvo;
  end if;
  if v_dep is not null then
    raise exception '20261003g: há dependente das tabelas de backup: %', v_dep;
  end if;

  if exists (select 1 from pg_class a join pg_class c on c.relname = a.relname
              where a.relnamespace = 'arquivo'::regnamespace and c.oid = any (v_alvo)) then
    raise exception '20261003g: já existe em arquivo tabela com o mesmo nome de um backup';
  end if;

  -- movimento
  for r in select c.oid, c.relname, obj_description(c.oid, 'pg_class') as cmt
             from pg_class c where c.oid = any (v_alvo) order by c.relname loop
    execute format('revoke all on table public.%I from public, anon, authenticated', r.relname);
    execute format('alter table public.%I set schema arquivo', r.relname);
    execute format('comment on table arquivo.%I is %L', r.relname,
                   '20261003g: movida de public' || coalesce(' | ' || r.cmt, ''));
  end loop;
end $g$;

-- ─── 1. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  if (select count(*) from pg_class c where c.relnamespace = 'arquivo'::regnamespace
         and obj_description(c.oid, 'pg_class') like '20261003g:%') <> 18 then
    raise exception '20261003g: esperadas 18 tabelas movidas';
  end if;
  if exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
                and (c.relname like '%\_bkp\_%' or c.relname like '%\_bak\_%')) then
    raise exception '20261003g: ainda há backup em public';
  end if;
  if has_schema_privilege('anon', 'arquivo', 'usage') or has_schema_privilege('authenticated', 'arquivo', 'usage') then
    raise exception '20261003g: schema arquivo com USAGE para anon/authenticated';
  end if;
  if exists (select 1 from pg_class c, unnest(array['anon', 'authenticated']) r
              where c.relnamespace = 'arquivo'::regnamespace and obj_description(c.oid, 'pg_class') like '20261003g:%'
                and has_table_privilege(r, c.oid, 'select')) then
    raise exception '20261003g: tabela arquivada com SELECT para anon/authenticated';
  end if;
end $confere$;

-- ─── 1. Depois de mover ─────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('1.movidas', $q$select count(*) filter (where c.relnamespace = 'arquivo'::regnamespace) em_arquivo,
  count(*) filter (where c.relnamespace = 'public'::regnamespace) em_public,
  count(*) filter (where c.relnamespace = 'arquivo'::regnamespace and c.reltuples::bigint = b.linhas_est) linhas_iguais
  from _z_bkp b join pg_class c on c.oid = b.oid$q$);
select pg_temp.z_q('1.schema', $q$select r, has_schema_privilege(r, 'arquivo', 'usage') from unnest(array['anon', 'authenticated', 'service_role']) r$q$);
select set_config('z.t1', (select relname from _z_bkp order by relname limit 1), true);
set local role anon;
select pg_temp.z_err('1.anon_le', format('select count(*) from arquivo.%I', current_setting('z.t1')));
reset role;
set local role authenticated;
select pg_temp.z_err('1.authenticated_le', format('select count(*) from arquivo.%I', current_setting('z.t1')));
select pg_temp.z_err('1.authenticated_public', format('select count(*) from public.%I', current_setting('z.t1')));
reset role;

-- ─── 2. Reversão (o bloco comentado no fim da migration, executado aqui) ───────────────────────────────────────────
do $rev$
declare r record;
begin
  for r in select c.relname, obj_description(c.oid, 'pg_class') as cmt from pg_class c
            where c.relnamespace = 'arquivo'::regnamespace and obj_description(c.oid, 'pg_class') like '20261003g:%' loop
    execute format('alter table arquivo.%I set schema public', r.relname);
    execute format('comment on table public.%I is %L', r.relname, nullif(substr(r.cmt, length('20261003g: movida de public | ') + 1), ''));
  end loop;
end $rev$;
-- (grants de anon/authenticated NÃO voltam: backup com dado pessoal não deve ficar legível pela API)
select pg_temp.z_q('2.revertida', $q$select count(*) filter (where c.relnamespace = 'public'::regnamespace) em_public,
  count(*) filter (where c.relnamespace = 'arquivo'::regnamespace) em_arquivo,
  count(*) filter (where obj_description(c.oid, 'pg_class') is not distinct from b.cmt) comentario_original
  from _z_bkp b join pg_class c on c.oid = b.oid$q$);

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003g',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
