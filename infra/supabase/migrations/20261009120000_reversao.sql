-- Reversão do 20261009120000: volta dados.cadastro ao corpo de 09/10 (md5 a2387c9c…) e tira o GRANT.
begin;
create or replace function dados.cadastro(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  r dados.dashboards;
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  select * into r from dados.dashboards d where d.chave = p_chave and d.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  if not dados.pode_ver(p_chave) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  return r;
end
$function$;
revoke execute on function public.dados_atm_resumo(text, date, date) from service_role;
commit;
