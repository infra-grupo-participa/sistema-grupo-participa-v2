-- Reversão de 20261009041000 (consumo semanal). Desliga o job e remove as funções.
-- Dados ficam (ops.consumo_semana, ops.config.consumo_*, linhas consumo_semanal em ops.banco_alerta): nada se apaga.
-- Remoção total, só se decidido: drop table ops.consumo_semana;
--   alter table ops.config drop column consumo_enviar, drop column consumo_cursor_runid;
-- Desligar sem reverter: update ops.config set consumo_enviar = false where id;  (o relatório segue só no banco)
set local lock_timeout = '3s';
set local statement_timeout = '20s';

select cron.unschedule('ops-consumo-semanal')
 where exists (select 1 from cron.job where jobname = 'ops-consumo-semanal');
drop function if exists ops.consumo_semanal();
drop function if exists ops.consulta_curta_redigida(text, bigint);
drop function if exists ops.consulta_curta(text, bigint);
drop function if exists ops.fmt_ms(double precision);
drop function if exists ops.fmt_var(double precision, double precision);
