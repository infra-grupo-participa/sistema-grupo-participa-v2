-- 20261005b — Agenda o lembrete de entrevista de placa (pg_cron → ops.cron_post → POST /api/cron/interview-reminder).
-- NÃO APLICADO. Medido em 01/10/2026: 0 de 40 entrevistas com reminder_sent_at (nada agendava a rota).
--
-- Rota: web/app/api/cron/interview-reminder/route.ts — GET e POST, Authorization: Bearer $CRON_SECRET (401 sem ele).
-- Janela da rota: entrevistas com início entre +3h30 e +4h30 (1 h de largura) e reminder_sent_at nulo.
-- Frequência: a cada 15 min → 4 passagens por janela. A rota RESERVA cada entrevista antes de enviar
--   (update ... where reminder_sent_at is null returning), então execuções sobrepostas não mandam 2 e-mails.
--
-- PRÉ-REQUISITOS (fora deste arquivo; nenhum segredo vai em arquivo):
--   1. Vault: cadastrar o segredo `placas_cron_secret` com o MESMO valor da env CRON_SECRET do app (Hostinger).
--        select vault.create_secret('<valor>', 'placas_cron_secret', 'Bearer do cron de placas');
--   2. Env CRON_SECRET definida no servidor do app (a rota responde 401 enquanto estiver vazia;
--      /api/health logado como dev mostra o booleano).
--   Sem o segredo no Vault o job NÃO dispara (where exists) — falha fechada, sem enviar "Bearer " vazio.
--
-- Timeout 60 s: a rota envia e-mails em série. Segredo lido do Vault no command, nunca literal.
-- ops.cron_post registra o request_id em ops.rotina_chamada → o vigia acompanha sucesso/falha.

do $mig$
begin
  if exists (select 1 from cron.job where jobname = 'placas-lembrete-entrevista') then
    perform cron.unschedule('placas-lembrete-entrevista');
  end if;

  perform cron.schedule('placas-lembrete-entrevista', '*/15 * * * *', $cron$
    select ops.cron_post(
      'placas-lembrete-entrevista',
      url := 'https://grupoparticipa.app.br/api/cron/interview-reminder',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || s.decrypted_secret),
      timeout_milliseconds := 60000)
    from vault.decrypted_secrets s
    where s.name = 'placas_cron_secret'
  $cron$);
end
$mig$;

-- REVERSÃO:
--   select cron.unschedule('placas-lembrete-entrevista');
--   -- (opcional) delete from ops.rotina where jobname = 'placas-lembrete-entrevista';
