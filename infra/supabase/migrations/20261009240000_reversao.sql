-- Reversão de 20261009240000: desliga a coleta de 30 em 30 min. O diário (trafego-meta, 09:30 UTC) continua.
select cron.unschedule('trafego-meta-hoje') where exists (select 1 from cron.job where jobname = 'trafego-meta-hoje');
