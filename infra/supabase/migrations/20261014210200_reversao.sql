-- Reversão de 20261014210200 (carga da planilha de ativação). NÃO apaga pessoa nem evento já carregado; medir antes com
--   select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.planilha_linha';
set local lock_timeout = '5s';
drop function if exists pessoas.carga_planilha_pessoas(bigint, integer);
drop function if exists pessoas.carga_planilha_estagio(bigint, text, jsonb);
drop table if exists pessoas.planilha_linha;
delete from pessoas.carga_chave where fonte = 'ativacao_planilha' and por = 'migration 20261014210200';
