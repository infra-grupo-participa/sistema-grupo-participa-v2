-- 20261016240100: liga a cópia da aba Relatório (cron dados-relatorio-planilha-sync → Edge dados-planilha-relatorio).
--
-- STATUS: APLICADA em 16/10/2026 13:21 UTC (aplica_sql.py aplicar, transação única, registrada em schema_migrations), depois de 20261016240000, da Edge publicada e de uma
--   rodada manual com sucesso (ver 20261016240000.explain.md). Sem a Edge no ar o cron recebe 404 e o vigia abre incidente.
-- COMO VOLTAR: 20261016240100_reversao.sql. Desligar sem apagar: select cron.alter_job((select jobid from cron.job where jobname = 'dados-relatorio-planilha-sync'), active := false);
-- O QUE FAZ
--   a. Cron dados-relatorio-planilha-sync, a cada 5 minutos nos minutos 2, 7, 12... (2-59/5; a mensageria-planilha-sync roda nos
--      minutos 6, 16, 26... desde a 20261014010300 e as duas Edges leem o Google com a mesma conta de serviço: os minutos
--      2, 7, 12, 17... nunca coincidem com os dela),
--      pelo ops.cron_post (regra 11 do CLAUDE.md), header x-sync-chave do Vault (dados_relatorio_planilha_chave).
--   b. Linha do vigia escrita à mão (ops.rotina / ops.rotina_estado): intervalo 5 min, 3 falhas seguidas ou 30 min sem
--      sucesso abrem incidente, 3 sucessos fecham.
-- AS 5 PERGUNTAS
--   escala: 1 planilha, 1 aba, 1 chamada à Google Sheets API (values.batchGet) + 1 token por rodada.
--   índice: nenhum (a Edge lê a config de uma tabela de 1 linha).
--   frequência: 288 chamadas por dia (cota do Google: 300 leituras por minuto por projeto; a rodada usa 1).
--   repetição: uma rodada por 5 minutos, não por tela. A tela lê o banco.
--   reversão: cron.unschedule ou active := false.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $guarda$
begin
  if to_regclass('dados.relatorio_planilha') is null or to_regprocedure('dados.relatorio_planilha_gravar(text,jsonb,text)') is null then
    raise exception '20261016240100: aplique antes 20261016240000 (dados.relatorio_planilha ausente)';
  end if;
end
$guarda$;

do $cron$
begin
  if to_regnamespace('cron') is null or to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null
     or to_regclass('vault.decrypted_secrets') is null then
    raise notice '20261016240100: pg_cron, ops.cron_post ou Vault ausente; cron dados-relatorio-planilha-sync NÃO agendado';
    return;
  end if;
  perform cron.schedule('dados-relatorio-planilha-sync', '2-59/5 * * * *', $c$
    select ops.cron_post('dados-relatorio-planilha-sync',
      url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/dados-planilha-relatorio',
      body := '{}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'dados_relatorio_planilha_chave')),
      timeout_milliseconds := 60000)
  $c$);
  insert into ops.rotina (jobname, n_falhas, janela, k_ok, intervalo, intervalo_fonte)
  values ('dados-relatorio-planilha-sync', 3, interval '30 minutes', 3, interval '5 minutes', 'manual')
  on conflict (jobname) do nothing;
  insert into ops.rotina_estado (jobname) values ('dados-relatorio-planilha-sync') on conflict (jobname) do nothing;
end
$cron$;

do $conf$
begin
  if to_regnamespace('cron') is null then return; end if;
  if (select count(*) from cron.job where jobname = 'dados-relatorio-planilha-sync' and schedule = '2-59/5 * * * *' and active
         and command like '%ops.cron_post(''dados-relatorio-planilha-sync''%'
         and command like '%dados_relatorio_planilha_chave%') <> 1 then
    raise exception '20261016240100: cron dados-relatorio-planilha-sync ausente ou fora do padrão';
  end if;
  if (select count(*) from ops.rotina where jobname = 'dados-relatorio-planilha-sync') <> 1 then
    raise exception '20261016240100: linha do vigia ausente';
  end if;
end
$conf$;
