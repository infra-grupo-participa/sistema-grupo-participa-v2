-- Reversão de 20261016230250. Fora de transação (um statement por chamada). ANTES, reverter a 20261016230255 (as funções novas usam o
-- índice único como árbitro do on conflict; sem ele o webhook falha com "there is no unique or exclusion constraint").
create index concurrently if not exists eventos_hotmart_ref_idx on pessoas.eventos (ref_id, tipo) where ref_tipo = 'hotmart.transacao';

drop index concurrently if exists pessoas.eventos_hotmart_ref_unico;
