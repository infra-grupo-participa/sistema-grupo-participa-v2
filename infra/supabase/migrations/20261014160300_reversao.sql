-- Reversão de 20261014160300 (fora de transação).
drop index concurrently if exists pessoas.eventos_fonte_unico;
drop index concurrently if exists pessoas.eventos_evento_idx;
drop index concurrently if exists pessoas.eventos_turma_idx;
