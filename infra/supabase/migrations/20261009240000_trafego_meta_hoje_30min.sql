-- 20261009240000: coleta Meta Ads do dia corrente a cada 30 minutos (job trafego-meta-hoje)
--
-- STATUS: ver 20261009240000.explain.md.
-- POR QUE: pedido do Victor (09/10/2026, card 17tya50fugc): "preciso q seja mais atual, q rode a cada alguns minutos,
--   sei la 30min". Hoje a coleta roda 1x/dia (trafego-meta, '30 9 * * *', relê 3 dias).
-- O QUE FAZ: agenda 'trafego-meta-hoje' em '15,45 * * * *' (a cada 30 min, fora dos minutos :00/:30 para não
--   coincidir com o diário das 09:30), chamando a mesma Edge pelo mesmo caminho do job diário (ops.cron_post, chave do
--   Vault trafego_coleta_chave) com body {"so_hoje": true}. É o job que a 20261006i já previa (comentário LIGAR).
--   O diário das 09:30 continua igual (relê 3 dias e corrige atribuição atrasada).
-- MEDIDO ANTES (09/10/2026): 15 contas; rodada só de hoje = 34 s, 10 linhas, 10 totais; ~1% da cota por hora de
--   ads_insights por chamada (cabeçalho x-business-use-case-usage, tier development_access); receivers idempotentes.
-- AS 5 PERGUNTAS: escala ~45 chamadas à API por rodada; índice: PK (campanha_id, dia) e (campanha_id); frequência 48
--   rodadas/dia; repetição: upsert idempotente; reversão: 20261009240000_reversao.sql (cron.unschedule).
-- IDEMPOTENTE: cron.schedule com o mesmo nome substitui o job.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if not exists (select 1 from cron.job where jobname = 'trafego-meta' and active) then
    raise exception '20261009240000: o job diário trafego-meta não está ativo; conferir antes de ligar o de 30 min';
  end if;
  if not exists (select 1 from vault.secrets where name = 'trafego_coleta_chave') then
    raise exception '20261009240000: falta o segredo trafego_coleta_chave';
  end if;
end
$g$;

select cron.schedule('trafego-meta-hoje', '15,45 * * * *', $c$
  select ops.cron_post('trafego-meta-hoje',
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/trafego-meta',
    body := '{"so_hoje": true}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'trafego_coleta_chave')),
    timeout_milliseconds := 150000)
$c$);

do $c$
begin
  if not exists (select 1 from cron.job where jobname = 'trafego-meta-hoje' and active and schedule = '15,45 * * * *') then
    raise exception '20261009240000: job não ficou agendado';
  end if;
end
$c$;
