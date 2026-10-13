-- Reversão de 20261013200000 (lista do pré-checkout da Sessão de Viabilidade do ATM).
-- A migration só criou public.dados_atm_pre_checkout(text, date, date, boolean); nenhuma função, view ou tabela existente mudou.
-- Depois de reverter, o modal do card "Pré-checkout" deixa de ter a lista (a chamada dá 404 no PostgREST); o card continua,
-- porque o número vem de public.dados_atm_resumo.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_atm_pre_checkout(text, date, date, boolean);

do $p$
begin
  if to_regprocedure('public.dados_atm_pre_checkout(text,date,date,boolean)') is not null then
    raise exception 'reversão: public.dados_atm_pre_checkout ainda existe';
  end if;
end
$p$;

notify pgrst, 'reload schema';
