begin;
revoke execute on function public.dados_atm_leads(text, date, date, boolean) from service_role;
commit;
