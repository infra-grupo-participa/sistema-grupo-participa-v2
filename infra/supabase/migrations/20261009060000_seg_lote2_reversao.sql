-- Reversão de 20261009060000_seg_lote2_thb_alunos_perfis.sql
-- Devolve USING (true) às policies neutralizadas (achadas pelo comentário 'seg_lote2 20261009060000:%'),
-- remove as 2 policies novas e os 2 helpers. Nada de dado é tocado. ≈10 s, sem deploy.
-- ⚠️ Reabre a leitura da base inteira para qualquer login dos 7+ sistemas: só usar se algum leitor quebrou.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $rev$
declare
  r record;
  n int := 0;
begin
  for r in
    select pol.polname as policyname, c.relname as tablename
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace s on s.oid = c.relnamespace
     where s.nspname = 'public' and c.relname in ('thb_alunos', 'perfis')
       and obj_description(pol.oid, 'pg_policy') like 'seg_lote2 20261009060000:%'
  loop
    execute format('alter policy %I on public.%I using (true)', r.policyname, r.tablename);
    execute format('comment on policy %I on public.%I is null', r.policyname, r.tablename);
    n := n + 1;
  end loop;
  if n <> 3 then
    raise exception 'seg_lote2 reversão: esperava 3 policies marcadas (2 thb_alunos + 1 perfis), achei %', n;
  end if;
end
$rev$;

drop policy if exists thb_alunos_select_escopo on public.thb_alunos;
drop policy if exists perfis_select_escopo     on public.perfis;
drop function if exists public.gp_thb_alunos_do_ambiente();
drop function if exists public.gp_le_cadastro_interno();

commit;
