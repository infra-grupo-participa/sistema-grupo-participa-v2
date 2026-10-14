-- Reversão de 20261014210300 (rotinas de manter vivo). Não apaga dado carregado.
set local lock_timeout = '5s';
select cron.unschedule(j.jobid) from cron.job j where j.jobname in ('pessoas-incremental', 'pessoas-ac-delta');
drop function if exists pessoas.carga_incremental(integer);
delete from pessoas.carga_chave where fonte in ('incremental', 'activecampaign_delta') and por like 'migration 20261014210300%';
