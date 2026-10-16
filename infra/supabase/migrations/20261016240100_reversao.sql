-- Reversão de 20261016240100: tira o cron e as linhas do vigia. Não toca na cópia nem no segredo (isso é 20261016240000_reversao.sql).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select cron.unschedule('dados-relatorio-planilha-sync') where exists (select 1 from cron.job where jobname = 'dados-relatorio-planilha-sync');
delete from ops.rotina_estado where jobname = 'dados-relatorio-planilha-sync';
delete from ops.rotina where jobname = 'dados-relatorio-planilha-sync';

do $c$
begin
  if exists (select 1 from cron.job where jobname = 'dados-relatorio-planilha-sync') or exists (select 1 from ops.rotina where jobname = 'dados-relatorio-planilha-sync') then
    raise exception 'reversão de 20261016240100 incompleta';
  end if;
end
$c$;
