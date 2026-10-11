-- Reversão de 20261011120000: desliga o sync da planilha de mensageria e tira o que a migration criou.
-- Os disparos que o sync gravou FICAM (são dado real da planilha); para tirá-los do dashboard, arquivar pela tela.
-- Antes de rodar, se quiser guardar quais disparos vieram da planilha:
--   select * from mkt_mensageria.planilha_linhas;
-- Desligar sem reverter (kill-switch): update mkt_mensageria.planilhas set ativa = false;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
select cron.unschedule('mensageria-planilha-sync') where exists (select 1 from cron.job where jobname = 'mensageria-planilha-sync');
drop function if exists mkt_mensageria.planilha_sync_receber(bigint, jsonb);
drop function if exists mkt_mensageria.planilha_sync_config();
drop function if exists mkt_mensageria.planilha_sync_chave();
drop function if exists mkt_mensageria.planilha_texto(text);
drop function if exists mkt_mensageria.planilha_hora(text);
drop function if exists mkt_mensageria.planilha_coluna(text);
drop table if exists mkt_mensageria.planilha_execucoes;
drop table if exists mkt_mensageria.planilha_linhas;
drop table if exists mkt_mensageria.planilhas;
delete from vault.secrets where name = 'mkt_msg_planilha_chave';
-- E-mail 40293 de volta para sem projeto (como a integração gravou).
update mkt_mensageria.disparos set projeto_id = null where id = 40293 and projeto_id = 75;
