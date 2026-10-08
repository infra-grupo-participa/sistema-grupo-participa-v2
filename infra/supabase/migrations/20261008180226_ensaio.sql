-- Ensaio de 20261008180226_crm_evolution_credenciais_servidor — termina em ROLLBACK.
-- Esperado (rodado em 08/10/2026 em produção, antes de aplicar):
--   authenticated_executa = false (42501) · anon_executa = false (42501)
--   service_role_url_ok = true · service_role_chave_presente = true (só o comprimento; o valor nunca é impresso)
--   proacl = {postgres=X/postgres,service_role=X/postgres} · pub_has_exec = false
begin;
set local lock_timeout = '3s'; set local statement_timeout = '15s';
create function public.crm_evolution_credenciais()
returns table (url text, api_key text)
language sql stable security definer set search_path = ''
as $$ select c.url, c.api_key from crm.evolution_credenciais() c $$;
revoke all on function public.crm_evolution_credenciais() from public, anon, authenticated;
grant execute on function public.crm_evolution_credenciais() to service_role;
create temp table _r(t text, ok boolean) on commit drop;
grant all on _r to anon, authenticated, service_role;
do $$ begin
  begin set local role authenticated; perform public.crm_evolution_credenciais(); reset role; insert into _r values ('authenticated_executa', true);
  exception when insufficient_privilege then reset role; insert into _r values ('authenticated_executa', false); end;
  begin set local role anon; perform public.crm_evolution_credenciais(); reset role; insert into _r values ('anon_executa', true);
  exception when insufficient_privilege then reset role; insert into _r values ('anon_executa', false); end;
end $$;
set local role service_role;
insert into _r select 'service_role_url_ok', url = 'https://wa.grupoparticipa.app.br' from public.crm_evolution_credenciais();
insert into _r select 'service_role_chave_presente', coalesce(length(api_key),0) >= 16 from public.crm_evolution_credenciais();
reset role;
insert into _r select 'proacl:'||proacl::text, null from pg_proc where oid='public.crm_evolution_credenciais()'::regprocedure;
insert into _r select 'pub_has_exec', has_function_privilege('public','public.crm_evolution_credenciais()','execute');
select * from _r;
rollback;
