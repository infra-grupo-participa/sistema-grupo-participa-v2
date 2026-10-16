-- APLICADA em 14/10/2026 com a versão gravada 20261014150148 (o arquivo se chamava 20261014160500; renomeado conforme o guia 6.3).
-- Reversão de 20261014160500. Só funciona se nada apontar para o evento (FK restrict).
set local lock_timeout = '5s';
delete from fin.eventos where chave = 'atm-2-2026-09';
