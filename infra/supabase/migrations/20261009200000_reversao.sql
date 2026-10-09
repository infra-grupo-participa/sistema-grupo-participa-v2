-- Reversão de 20261009200000 (histórico por edição). Apaga a RPC e a tabela, com a carga dos ATMs JUL/26 e SET/26 e
-- qualquer edição registrada depois pelo passo do .explain.md (seção 4). A carga dos dois ATMs volta rodando a migration
-- de novo; uma edição registrada depois NÃO volta: exportar dados.edicoes_historico antes de rodar.
-- Rodada dentro do ensaio 20261009200000_ensaio.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

drop function if exists public.dados_historico_edicoes(text);
drop table if exists dados.edicoes_historico;

notify pgrst, 'reload schema';
