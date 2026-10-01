-- 20261005b — Agenda o lembrete de entrevista de placa (pg_cron → ops.cron_post → POST /api/cron/interview-reminder).
-- Medido em 01/10/2026: 0 de 40 entrevistas com reminder_sent_at (nada agendava a rota).
--
-- 🔑 Sem configuração manual: a chave do cron NASCE no Vault (aleatória, 32 bytes) e ninguém a vê.
--    O banco a envia no Bearer; a rota confere chamando fn_placas_cron_chave_ok (service_role) —
--    o app não precisa da env CRON_SECRET (se existir, continua valendo como alternativa).
--
-- Rota: web/app/api/cron/interview-reminder/route.ts — GET e POST, 401 sem chave válida.
-- Janela: entrevistas com início entre +3h30 e +4h30 e reminder_sent_at nulo; a rota RESERVA cada
--   linha antes de enviar (update ... where reminder_sent_at is null), então execuções sobrepostas não duplicam.
-- Frequência: a cada 15 min. Timeout 60 s (e-mails em série). ops.cron_post registra em ops.rotina_chamada.

-- 1) Chave aleatória no Vault (idempotente: não troca uma chave já existente).
do $mig$
begin
  if not exists (select 1 from vault.secrets where name = 'placas_cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'),
                                'placas_cron_secret', 'Bearer do cron de lembrete de placa (gerado no banco)');
  end if;
end
$mig$;

-- 2) Conferência da chave pelo app. Só service_role executa; a chave nunca sai do banco.
--    Compara hashes (sha256) para não vazar prefixo por tempo de resposta.
create or replace function public.fn_placas_cron_chave_ok(p_chave text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_chave text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    return false;
  end if;
  if p_chave is null or length(p_chave) <> 64 then
    return false;
  end if;
  select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'placas_cron_secret';
  if v_chave is null then
    return false;
  end if;
  return sha256(convert_to(p_chave, 'UTF8')) = sha256(convert_to(v_chave, 'UTF8'));
end
$fn$;

revoke all on function public.fn_placas_cron_chave_ok(text) from public, anon, authenticated;
grant execute on function public.fn_placas_cron_chave_ok(text) to service_role;

-- 3) Agendamento.
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
--   drop function if exists public.fn_placas_cron_chave_ok(text);
--   delete from vault.secrets where name = 'placas_cron_secret';
--   -- (opcional) delete from ops.rotina where jobname = 'placas-lembrete-entrevista';
