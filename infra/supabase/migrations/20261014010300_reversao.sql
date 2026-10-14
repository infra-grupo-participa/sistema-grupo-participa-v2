-- Reversão de 20261014010300: agendas de antes.
set local lock_timeout = '5s';
do $g$
begin
  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'mensageria-planilha-sync'), schedule := '2-59/10 * * * *');
  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'), schedule := '37 5 * * *');
end
$g$;
