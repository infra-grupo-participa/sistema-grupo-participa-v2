-- 20261014180200: liga o job dados-grupo-foto (jobid 223) só na janela do export diário (ok do Victor, 14/10 ~21h45:
-- "ligar só o ATM agora"). Agenda 1-59/2 2,3 * * * (UTC) = de 23h01 a 00h59 BRT: o export abre às 23h (grupo_foto_ciclo
-- só reserva/chama às 23h BRT) e o download e processamento correm nos ciclos seguintes. Fora dessa janela o job não roda.
-- Antes era 1-59/2 * * * * (o dia todo). Hoje só o ATM 10/26 tem foto_ate (até 15/10); a Black entra quando a conta 2536
-- estiver nos grupos.
-- Reversão (desligar): select cron.alter_job(job_id := 223, schedule := '1-59/2 * * * *', active := false);
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_ciclo()'::regprocedure)
      is distinct from 'ed7918e918881a71c0a42c9d391e7c81' then
    raise exception '20261014180200: grupo_foto_ciclo não é o da 20261014180000';
  end if;
  if (select count(*) from cron.job where jobid = 223 and jobname = 'dados-grupo-foto' and not active) <> 1 then
    raise exception '20261014180200: job 223 não está como esperado (desligado)';
  end if;
  if (select count(*) from dados.dashboard_grupos where foto_ate is not null) <> 1 then
    raise exception '20261014180200: era esperada só 1 campanha com foto_ate (ATM 10/26)';
  end if;
end
$g$;
select cron.alter_job(job_id := 223, schedule := '1-59/2 2,3 * * *', active := true);
