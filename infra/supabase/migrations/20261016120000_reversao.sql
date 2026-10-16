-- Reversão de 20261016120000 (pessoas-incremental por fonte). Não apaga dado carregado nem as linhas de pessoas.carga_execucao.
-- Rodar com o job pessoas-incremental desligado ou fora do :50.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- o job volta a chamar a função antiga (que continua no banco)
select cron.alter_job(j.jobid, command := $c$ set statement_timeout = '120s'; select pessoas.carga_incremental(200) $c$)
  from cron.job j where j.jobname = 'pessoas-incremental';
drop procedure if exists pessoas.carga_incremental_rodar(integer, integer, integer);
drop function if exists pessoas.carga_incremental_fonte(text, integer);
-- datas de fim como estavam (incremental sem fim; delta em 2026-12-31)
update pessoas.carga_chave set ate = null, por = 'reversão de 20261016120000', em = now() where fonte = 'incremental';
update pessoas.carga_chave set ate = date '2026-12-31', por = 'reversão de 20261016120000', em = now() where fonte = 'activecampaign_delta';

do $g$
begin
  if to_regprocedure('pessoas.carga_incremental(integer)') is null then
    raise exception 'reversão 20261016120000: a função antiga pessoas.carga_incremental sumiu.';
  end if;
  if (select command from cron.job where jobname = 'pessoas-incremental') not like '%pessoas.carga_incremental(200)%' then
    raise exception 'reversão 20261016120000: o job não voltou ao comando antigo.';
  end if;
end
$g$;
-- depois: delete from supabase_migrations.schema_migrations where version = '20261016120000';
-- as linhas de saúde (fonte 'incremental') e de erro por fonte ficam em pessoas.carga_execucao como histórico.
