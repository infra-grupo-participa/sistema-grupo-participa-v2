-- Reversão de 20261014160500. Só funciona se nada apontar para o evento (FK restrict).
set local lock_timeout = '5s';
delete from fin.eventos where chave = 'atm-2-2026-09';
