-- 20261005r (pré): índice de telefone em public.compradores, criado SEM travar escrita.
-- Roda sozinho, fora de transação (create index concurrently não aceita begin). Depois, a 20261005r confere que existe e
-- é válido. Medido: busca por fone_key em compradores era Seq Scan de 26.851 linhas (420 ms) → Index Scan 0,02 ms.
-- Reversão: drop index concurrently if exists public.ix_compradores_fone_key;
create index concurrently if not exists ix_compradores_fone_key
  on public.compradores (controle.fone_key((telefone)::text)) where telefone is not null;
