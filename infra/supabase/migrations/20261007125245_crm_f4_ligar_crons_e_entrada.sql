-- F4 do CRM — LIGAR, passos 5, 6 e 7 (crons) + entrada do WhatsApp (07/10/2026).
-- Crons HTTP pelo ops.cron_post (ADR 0001), segredo lido do Vault no command (nunca no texto):
--   crm-whatsapp-enviar     * * * * *   só chama a Edge quando crm.whatsapp_fila_tem() — que já exige whatsapp_ligado E
--                                        envio_ligado. Com envio_ligado=false (como fica aqui) o cron roda 0,4 ms e não faz HTTP.
--   crm-whatsapp-templates  15 6 * * *  sincroniza templates do sender (só LEITURA na Infobip).
--   crm-whatsapp-reprocessar */10       SQL puro: processa eventos brutos pendentes (no-op com whatsapp_ligado=false).
-- Liga a ENTRADA: whatsapp_ligado = true. O ENVIO continua desligado (envio_ligado = false) até o teste real com o Arthur.
-- Reversão: update crm.config set whatsapp_ligado = false;
--   select cron.unschedule('crm-whatsapp-enviar'); select cron.unschedule('crm-whatsapp-templates');
--   select cron.unschedule('crm-whatsapp-reprocessar');

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $guarda$
begin
  if exists (select 1 from cron.job where jobname in ('crm-whatsapp-enviar', 'crm-whatsapp-templates', 'crm-whatsapp-reprocessar')) then
    raise exception 'crons crm-whatsapp-* já existem';
  end if;
  if (select c.whatsapp_numero_id from crm.config c) is null then raise exception 'número do CRM não cadastrado'; end if;
  if coalesce((select c.envio_ligado from crm.config c), true) then raise exception 'envio_ligado deveria estar false'; end if;
  if (select count(*) from vault.secrets where name in ('infobip_api_key', 'crm_whatsapp_webhook_chave', 'crm_whatsapp_envio_chave')) <> 3 then
    raise exception 'segredos da F4 ausentes no Vault';
  end if;
  if to_regprocedure('ops.cron_post(text,text,jsonb,jsonb,jsonb,integer)') is null then raise exception 'ops.cron_post ausente'; end if;
end
$guarda$;

select cron.schedule('crm-whatsapp-enviar', '* * * * *', $c$ select ops.cron_post('crm-whatsapp-enviar',
  url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
  headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
             (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
  body := '{"acao":"enviar"}'::jsonb, timeout_milliseconds := 60000) where crm.whatsapp_fila_tem() $c$);

select cron.schedule('crm-whatsapp-templates', '15 6 * * *', $c$ select ops.cron_post('crm-whatsapp-templates',
  url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/crm-whatsapp-enviar',
  headers := jsonb_build_object('Content-Type','application/json','x-crm-chave',
             (select decrypted_secret from vault.decrypted_secrets where name = 'crm_whatsapp_envio_chave')),
  body := '{"acao":"templates"}'::jsonb, timeout_milliseconds := 30000) $c$);

select cron.schedule('crm-whatsapp-reprocessar', '*/10 * * * *', 'select crm.whatsapp_reprocessar()');

update crm.config set whatsapp_ligado = true;
