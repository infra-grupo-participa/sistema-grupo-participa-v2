-- 20261007a: CRM Comercial: liga o aviso automático de prazos (F2, 20261005t / 20261006041654).
--
-- O QUE FAZ: crm.config.notificacao_cron_ligado = true e agenda crm.notificar_prazos() a cada 5 min (frequência e nome
--   documentados na F2: 20261005t.explain.md, "cron.schedule('crm-notificar-prazos', '*/5 * * * *', ...)").
--   Cron SQL (não HTTP): ops.cron_post não se aplica. O vigia (ADR 0001) registra rotina nova sozinho pelo schedule.
-- MASSA (07/10/2026, rodada manual em rollback): 970 negócios abertos, 9 com prazo crítico estourado, 7 com dono →
--   7 notificações prazo_estourado para 2 vendedores (máx 5 para um), 0 atividade_vencendo. Dedupe por ref_id
--   (negócio + etapa_desde): a 2ª rodada não repete.
-- REVERSÃO: bloco comentado no fim (kill-switch no banco: a função devolve 0 com a flag false).

do $guarda$
begin
  if md5(pg_get_functiondef('crm.notificar_prazos()'::regprocedure)) <> '6a64b7228c3169737aa10489246a7168' then
    raise exception '20261007a: corpo vivo de crm.notificar_prazos mudou (md5); reler antes de ligar';
  end if;
  if coalesce((select c.notificacao_cron_ligado from crm.config c), true) then
    raise exception '20261007a: notificacao_cron_ligado já está true (ou config ausente)';
  end if;
  if exists (select 1 from cron.job where jobname = 'crm-notificar-prazos' or command ilike '%notificar_prazos%') then
    raise exception '20261007a: já existe cron de prazos';
  end if;
end
$guarda$;

update crm.config set notificacao_cron_ligado = true where not notificacao_cron_ligado;

select cron.schedule('crm-notificar-prazos', '*/5 * * * *', 'select crm.notificar_prazos()');

-- ─── REVERSÃO (não roda) ───
-- update crm.config set notificacao_cron_ligado = false;
-- select cron.unschedule('crm-notificar-prazos');
