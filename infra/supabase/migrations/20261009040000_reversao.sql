-- Reversão de 20261009040000 (saturação no vigia). Devolve o command do job 68 a 'select ops.vigiar()' e remove as
-- funções. Reverter 20261009041000 ANTES (usa ops.fmt_num e ops.banco_alerta) — a guarda aborta se não.
-- Dados ficam (ops.banco_alerta, ops.config.saturacao_*): nada se apaga.
-- Remoção total, só se decidido: drop table ops.banco_alerta; alter table ops.config drop column saturacao_enviar, ...;
-- Desligar só o envio, sem reverter: update ops.config set saturacao_enviar = false where id;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $pre$
begin
  if to_regprocedure('ops.consumo_semanal()') is not null then
    raise exception 'reverter 20261009041000 antes';
  end if;
end
$pre$;

select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'ops-vigia-10min'),
                      command := 'select ops.vigiar()');
drop function if exists ops.ciclo();
drop function if exists ops.vigiar_saturacao();
drop function if exists ops.saturacao_avaliar(jsonb);
drop function if exists ops.saturacao_medir();
drop function if exists ops.fmt_dur(interval);
drop function if exists ops.fmt_num(numeric);

do $pos$
begin
  if not exists (select 1 from cron.job where jobname = 'ops-vigia-10min' and command = 'select ops.vigiar()') then
    raise exception 'job 68 não voltou para select ops.vigiar()';
  end if;
end
$pos$;
