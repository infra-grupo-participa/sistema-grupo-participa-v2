-- APLICADA em 14/10/2026 ~15:22 UTC com a versão gravada 20261014152242 (o arquivo se chamava 20261014210300; renomeado conforme o guia 6.3).
-- Reversão de 20261014152242 (rotinas de manter vivo). Não apaga dado carregado.
set local lock_timeout = '5s';
select cron.unschedule(j.jobid) from cron.job j where j.jobname in ('pessoas-incremental', 'pessoas-ac-delta');
drop function if exists pessoas.carga_incremental(integer);
delete from pessoas.carga_chave where fonte in ('incremental', 'activecampaign_delta') and por like 'migration 20261014152242%';
