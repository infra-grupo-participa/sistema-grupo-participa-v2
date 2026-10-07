-- F4 do CRM (WhatsApp oficial via Infobip) — LIGAR, passos 1 e 2 (07/10/2026).
-- Decisão do Arthur: o número +55 21 98754-5211 (sender 5521987545211), já API oficial na Infobip, fica SÓ para o
-- Comercial e passa a ser o WhatsApp do CRM. Os outros números da conta Infobip não são tocados.
--
-- 1. Cadastra o número em crm.numero_whatsapp e aponta crm.config.whatsapp_numero_id para ele.
-- 2. Cria no Vault crm_whatsapp_webhook_chave e crm_whatsapp_envio_chave com 32 bytes aleatórios GERADOS NO BANCO
--    (o valor nunca aparece neste arquivo, no chat nem em log). infobip_api_key já existia.
-- Não liga nada: whatsapp_ligado e envio_ligado continuam false.
-- Reversão: update crm.config set whatsapp_numero_id = null; update crm.numero_whatsapp set ativo = false
--   where numero = '5521987545211'; delete from vault.secrets where name in ('crm_whatsapp_webhook_chave','crm_whatsapp_envio_chave').

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $guarda$
begin
  if to_regclass('crm.numero_whatsapp') is null then raise exception 'F4 não aplicada'; end if;
  if exists (select 1 from crm.numero_whatsapp) then raise exception 'crm.numero_whatsapp já tem número'; end if;
  if (select c.whatsapp_numero_id from crm.config c) is not null then raise exception 'crm.config já aponta para um número'; end if;
  if coalesce((select c.whatsapp_ligado or c.envio_ligado from crm.config c), true) then
    raise exception 'whatsapp_ligado/envio_ligado deveriam estar false';
  end if;
  if exists (select 1 from vault.secrets where name in ('crm_whatsapp_webhook_chave', 'crm_whatsapp_envio_chave')) then
    raise exception 'segredos crm_whatsapp_* já existem';
  end if;
  if not exists (select 1 from vault.secrets where name = 'infobip_api_key') then raise exception 'Vault sem infobip_api_key'; end if;
end
$guarda$;

insert into crm.numero_whatsapp (numero, nome) values ('5521987545211', 'Comercial oficial');
update crm.config set whatsapp_numero_id = (select id from crm.numero_whatsapp where numero = '5521987545211');

select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_whatsapp_webhook_chave',
                           'CRM F4: senha do webhook da Infobip (Basic auth ou header x-crm-chave). Gerada no banco.');
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'crm_whatsapp_envio_chave',
                           'CRM F4: header x-crm-chave do cron para a Edge crm-whatsapp-enviar. Gerada no banco.');
