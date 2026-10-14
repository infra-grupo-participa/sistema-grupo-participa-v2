-- Reversão de 20261014160000 (fin.eventos.chave). Nada mais lê a coluna até a 20261014160100 ser aplicada:
-- reverter 160100 e 160200 antes desta.
set local lock_timeout = '5s';
drop index if exists fin.eventos_chave_key;
alter table fin.eventos drop column if exists chave;
