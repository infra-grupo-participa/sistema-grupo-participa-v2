-- Reversão de 20261009220000: tira a RPC da lista de disparos (não há dado próprio; nada mais muda).
set local lock_timeout = '5s';
set local statement_timeout = '30s';
drop function if exists public.dados_atm_disparos_lista(text, date, date);
