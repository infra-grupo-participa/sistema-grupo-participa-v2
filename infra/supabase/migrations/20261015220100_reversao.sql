-- Reversão de 20261015220100 (coleta da aba Lives da Black): tira o cron, as linhas do vigia e o segredo do header.
-- Não apaga nada coletado (isso é 20261015220000_reversao.sql) e não mexe na chave da YouTube (dados_black_youtube_api_key).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select cron.unschedule('black-youtube') where exists (select 1 from cron.job where jobname = 'black-youtube');
delete from ops.rotina_estado where jobname = 'black-youtube';
delete from ops.rotina where jobname = 'black-youtube';
delete from vault.secrets where name = 'dados_black_youtube_chave';

do $c$
begin
  if exists (select 1 from cron.job where jobname = 'black-youtube') or exists (select 1 from ops.rotina where jobname = 'black-youtube')
     or exists (select 1 from vault.secrets where name = 'dados_black_youtube_chave') then
    raise exception 'reversão de 20261015220100 incompleta';
  end if;
end
$c$;
