-- APLICADA em 14/10/2026 com a versão gravada 20261014150144 (o arquivo se chamava 20261014160450; renomeado conforme o guia 6.3).
-- Reversão de 20261014160450.
set local lock_timeout = '5s';
alter table fin.eventos drop column if exists captacao_inicio;
