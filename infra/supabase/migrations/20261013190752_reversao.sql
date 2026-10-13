-- Reversão de 20261013190752 (lista de vendas da Sessão de Viabilidade do ATM).
-- A migration só criou public.dados_atm_sv_vendas(text, boolean); nenhuma função, view ou tabela existente mudou.
-- Depois de reverter, a seção "Sessão de Viabilidade" do front deixa de ter a lista (a chamada dá 404 no PostgREST).

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_atm_sv_vendas(text, boolean);

do $p$
begin
  if to_regprocedure('public.dados_atm_sv_vendas(text,boolean)') is not null then
    raise exception 'reversão: public.dados_atm_sv_vendas ainda existe';
  end if;
end
$p$;

notify pgrst, 'reload schema';
