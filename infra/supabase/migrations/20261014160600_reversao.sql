-- Reversão de 20261014160600.
set local lock_timeout = '5s';
update fin.eventos set inicio = date '2026-03-14', chave = 'ht20-2026-03', observacao = null where id = 57;
