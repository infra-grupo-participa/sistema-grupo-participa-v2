-- 20261003g — Arquiva os backups de thb_alunos que estão em public (passo 7 do plano)
--
-- O QUE FAZ
--   As 18 tabelas de backup em public (nome com _bkp_ ou _bak_, jun–jul/2026): 15 de thb_alunos (com dado pessoal) e 3 de
--   ativações (ativacoes, hm/ht_ativacao_logs, 01/07). Todas legíveis por anon via grant herdado. Vão para o schema
--   arquivo (alter table … set schema). Nada é apagado. O schema arquivo não tem USAGE para public/anon/authenticated
--   (fora da API) e as tabelas perdem os grants herdados de public (anon/authenticated/PUBLIC). Cada tabela ganha o
--   prefixo '20261003g: movida de public' no comentário (o comentário original fica depois de ' | ').
--
-- GUARDAS (abortam antes de mover)
--   - exatamente 18 candidatas (base mudou = parar e conferir a lista no ensaio);
--   - nenhum dependente no banco: view/matview (pg_rewrite), FK de outra tabela, função cujo corpo cite o nome,
--     job do pg_cron cujo comando cite o nome;
--   - nenhuma tabela homônima já em arquivo.
--   Dependente FORA do banco (script, planilha, n8n) não é detectável aqui: a reversão é 1 comando.
--
-- AS 5 PERGUNTAS
--   escala: 18 tabelas, só catálogo (set schema não reescreve dado). índice: nenhum. frequência: 1 vez.
--   repetição: n/a. reversão: bloco no fim (set schema public nas tabelas com o comentário desta migration).
--   Lock: ACCESS EXCLUSIVE em cada backup até o commit (ninguém deveria usá-los; lock_timeout 3s).
--
-- ENSAIO: infra/supabase/migrations/20261003g_ensaio.sql. ORDEM: independente das 20261003a–f.

set local lock_timeout = '3s';

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

-- ─── REVERSÃO (NÃO executar junto; testada no ensaio) ───────────────────────────────────────────────────────────
-- do $rev$
-- declare r record;
-- begin
--   for r in select c.relname, obj_description(c.oid, 'pg_class') as cmt from pg_class c
--             where c.relnamespace = 'arquivo'::regnamespace and obj_description(c.oid, 'pg_class') like '20261003g:%' loop
--     execute format('alter table arquivo.%I set schema public', r.relname);
--     execute format('comment on table public.%I is %L', r.relname, nullif(substr(r.cmt, length('20261003g: movida de public | ') + 1), ''));
--   end loop;
-- end $rev$;
-- -- (grants de anon/authenticated NÃO voltam: backup com dado pessoal não deve ficar legível pela API)
