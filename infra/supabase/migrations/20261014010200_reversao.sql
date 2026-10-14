-- Reversão de 20261014010200
set local lock_timeout = '5s';
drop index if exists mkt_mensageria.planilhas_projeto_id_idx;
