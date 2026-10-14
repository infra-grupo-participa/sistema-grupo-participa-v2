-- 20261014010300: dois crons nossos saem de minutos cheios (auditoria pelo guia do JP, item 10, parte nossa)
--
-- POR QUE: guia 6.5 e 8 ("cron novo = minuto vazio"). mensageria-planilha-sync (2-59/10) rodava junto com ops-vigia-10min em
--   TODA rodada; dados-hotmart-ao-vivo-limpar (05:37) junto com crm-whatsapp-reprocessar e os de cada minuto.
-- O QUE FAZ (cron.alter_job, só a agenda; comando, frequência e ativo não mudam):
--   mensageria-planilha-sync: 2-59/10 -> 6-59/10 (6/hora; coincide só com mensageria-fonte-sendflow 2x/hora e rotinas
--     diárias/semanais, não há minuto livre para um job de 10 em 10);
--   dados-hotmart-ao-vivo-limpar: 37 5 * * * -> 34 5 * * * (sem job de até 11/h nesse minuto).
-- FICA PARA O VICTOR (não mexido): data de fim de trafego-meta-hoje e de mensageria-planilha-sync depois do ATM 1 e da Black;
--   trafego-meta-hoje continua em :15/:45 (a validade de 75 min de dados_black_trafego conta com esse ritmo).
-- AS 5 PERGUNTAS: escala/índice não se aplicam; frequência igual; repetição nenhuma; reversão = 20261014010300_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
declare v_m bigint; v_h bigint;
begin
  select jobid into v_m from cron.job where jobname = 'mensageria-planilha-sync' and schedule = '2-59/10 * * * *';
  select jobid into v_h from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar' and schedule = '37 5 * * *';
  if v_m is null or v_h is null then
    raise exception '20261014010300: agenda viva diferente da esperada. Reler cron.job.';
  end if;
  perform cron.alter_job(job_id := v_m, schedule := '6-59/10 * * * *');
  perform cron.alter_job(job_id := v_h, schedule := '34 5 * * *');
end
$g$;
