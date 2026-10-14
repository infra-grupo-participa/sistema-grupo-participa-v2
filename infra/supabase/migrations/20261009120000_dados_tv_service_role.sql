-- 20261009120000 — TV (dashboard-ht) lê o resumo do ATM com a chave de serviço
-- Ver 20261009120000.explain.md. Pedido do Victor em 09/10/2026, com o JP.
begin;

-- Guarda: só aplica sobre o corpo lido em 09/10/2026.
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.cadastro(text)'::regprocedure)
     <> 'a2387c9cd74ea08327b430b32576e00c' then
    raise exception 'dados.cadastro mudou desde a leitura; revisar antes de aplicar';
  end if;
end $$;

-- A chave de serviço já ignora RLS e é admin do banco; aqui ela só deixa de ser barrada pela
-- checagem de "pessoa da equipe logada" (auth.uid), que ela não tem. A pessoa logada segue igual.
create or replace function dados.cadastro(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  r dados.dashboards;
  v_servico boolean := coalesce((select auth.role()), '') = 'service_role';
begin
  if not v_servico and not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  select * into r from dados.dashboards d where d.chave = p_chave and d.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  if not v_servico and not dados.pode_ver(p_chave) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return r;
end
$function$;

grant execute on function public.dados_atm_resumo(text, date, date) to service_role;

commit;
