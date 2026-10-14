-- TV do dashboard-ht conta o ingresso no grupo pelos leads ("Entrou no grupo?" = sim).
-- Pedido do Victor (09/10/2026). Ver 20261009130000.explain.md.
begin;
grant execute on function public.dados_atm_leads(text, date, date, boolean) to service_role;
commit;
