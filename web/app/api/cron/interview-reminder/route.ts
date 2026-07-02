import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { buildSlotStart } from '@/modules/placas/domain/agendamento';
import { getEmailContentByStatus, emailDynamicBoxes, type EmailExtra } from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

export const dynamic = 'force-dynamic';

// Porta de send-interview-reminder.php — lembrete ~4h antes da entrevista.
// Idempotente via reminder_sent_at; janela larga (3h30–4h30) para tolerar cron de até 1h.
// Agendar na infra (Hostinger cron / GitHub Actions): GET a cada 15–30min com
// Authorization: Bearer $CRON_SECRET.
const WINDOW_MIN_MS = 3.5 * 60 * 60 * 1000;
const WINDOW_MAX_MS = 4.5 * 60 * 60 * 1000;

export async function GET(request: NextRequest) {
  const secret = process.env.CRON_SECRET || '';
  const auth = request.headers.get('authorization') || '';
  if (!secret || auth !== `Bearer ${secret}`) return jsonError('Não autorizado.', 401);

  const admin = createAdminSupabase();
  const { data, error } = await admin
    .from('thb_placas_solicitacoes')
    .select('id, token, nome, email, entrevista_data, entrevista_hora, auditoria_step, reminder_sent_at')
    .eq('auditoria_step', 2)
    .is('reminder_sent_at', null)
    .not('entrevista_data', 'is', null)
    .not('entrevista_hora', 'is', null);
  if (error) return jsonError('Não foi possível consultar as entrevistas.', 502);

  const now = Date.now();
  const alvo = (data ?? []).filter((s) => {
    const start = buildSlotStart(String(s.entrevista_data), String(s.entrevista_hora));
    if (!start) return false;
    const diff = start.getTime() - now;
    return diff >= WINDOW_MIN_MS && diff <= WINDOW_MAX_MS;
  });

  const appBase = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';
  const { email_templates } = await readPlacasConfig();
  let enviados = 0;

  for (const s of alvo) {
    const to = String(s.email ?? '').trim();
    if (!to) continue;
    const extra: EmailExtra = {
      entrevista_data: String(s.entrevista_data).slice(0, 10),
      entrevista_hora: String(s.entrevista_hora).slice(0, 5),
    };
    const content = getEmailContentByStatus('lembrete_entrevista', extra, `${appBase}/solicitar-placa?token=${s.token}`);
    const ov = email_templates?.['lembrete_entrevista'];
    if (ov) {
      if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
      if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
      if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes('lembrete_entrevista', extra) + ov.corpo_extra.trim();
    }
    const html = buildEmailTemplate({ ...content.templateData, nome: String(s.nome ?? 'Candidato') });
    const ok = await sendMail({ to, subject: content.assunto, html }).catch(() => false);
    if (ok) {
      // Marca ANTES de qualquer nova execução ver a linha — garante no máximo 1 lembrete.
      await admin.from('thb_placas_solicitacoes').update({ reminder_sent_at: new Date().toISOString() }).eq('id', s.id);
      enviados++;
    }
  }

  return jsonOk({ ok: true, candidatos: alvo.length, enviados });
}
