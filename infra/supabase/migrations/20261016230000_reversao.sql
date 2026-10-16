-- Reversão de 20261016230000 (índice eventos_hotmart_ref_idx). Fora de transação (um statement por chamada).
-- Sem o índice a carga e o webhook voltam a varrer a tabela por transação (correto, só lento).
drop index concurrently if exists pessoas.eventos_hotmart_ref_idx;
