-- Reversão de 20261014160450.
set local lock_timeout = '5s';
alter table fin.eventos drop column if exists captacao_inicio;
