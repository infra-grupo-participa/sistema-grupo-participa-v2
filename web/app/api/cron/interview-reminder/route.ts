import { timingSafeEqual } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, placaTrackingLink } from '@/shared/infrastructure/http/security';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { buildSlotStart } from '@/modules/placas/domain/agendamento';
import { getEmailContentByStatus, emailDynamicBoxes, type EmailExtra } from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

export const dynamic = 'force-dynamic';

// Porta de send-interview-reminder.php — lembrete ~4h antes da entrevista.
// Janela larga (3h30–4h30) para tolerar cron de até 1h. GET ou POST (ops.cron_post) com
// Authorization: Bearer $CRON_SECRET.
// Sem e-mail duplo: cada linha é REIVINDICADA atomicamente antes do envio
//   UPDATE ... SET reminder_sent_at = now() WHERE id = $1 AND reminder_sent_at IS NULL RETURNING id
// — duas execuções sobrepostas não enviam 2x: só quem reivindicou envia. Falha no envio
// devolve reminder_sent_at a null (só se ainda for o carimbo desta execução) para a próxima passagem.
const WINDOW_MIN_MS = 3.5 * 60 * 60 * 1000;
const WINDOW_MAX_MS = 4.5 * 60 * 60 * 1000;

// Comparação em tempo constante: a rota é chamada pela internet.
function mesmoSegredo(recebido: string, esperado: string): boolean {
  const a = Buffer.from(recebido);
  const b = Buffer.from(esperado);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function handle(request: NextRequest) {
  const secret = process.env.CRON_SECRET || '';
  const auth = request.headers.get('authorization') || '';
  if (!secret || !mesmoSegredo(auth, `Bearer ${secret}`)) return jsonError('Não autorizado.', 401);

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

  const { email_templates } = await readPlacasConfig();
  let enviados = 0;
  let falhas = 0;
  let jaReivindicados = 0;

  for (const s of alvo) {
    const to = String(s.email ?? '').trim();
    if (!to) continue;

    // Reivindicação atômica: só segue quem efetivamente trocou null → carimbo.
    const carimbo = new Date().toISOString();
    const { data: claimed, error: claimErr } = await admin
      .from('thb_placas_solicitacoes')
      .update({ reminder_sent_at: carimbo })
      .eq('id', s.id)
      .eq('auditoria_step', 2)
      .is('reminder_sent_at', null)
      .select('id, reminder_sent_at');
    if (claimErr) {
      falhas++;
      continue;
    }
    if (!claimed || claimed.length === 0) {
      jaReivindicados++;
      continue;
    }
    const carimboGravado = String(claimed[0].reminder_sent_at ?? carimbo);

    const extra: EmailExtra = {
      entrevista_data: String(s.entrevista_data).slice(0, 10),
      entrevista_hora: String(s.entrevista_hora).slice(0, 5),
    };
    const content = getEmailContentByStatus('lembrete_entrevista', extra, placaTrackingLink(String(s.token)));
    const ov = email_templates?.['lembrete_entrevista'];
    if (ov) {
      if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
      if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
      if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes('lembrete_entrevista', extra) + ov.corpo_extra.trim();
    }
    const html = buildEmailTemplate({ ...content.templateData, nome: String(s.nome ?? 'Candidato') });
    const ok = await sendMail({ to, subject: content.assunto, html }).catch(() => false);
    if (ok) {
      enviados++;
    } else {
      falhas++;
      // Devolve a linha para a próxima passagem — só se o carimbo ainda for o nosso.
      await admin
        .from('thb_placas_solicitacoes')
        .update({ reminder_sent_at: null })
        .eq('id', s.id)
        .eq('reminder_sent_at', carimboGravado);
    }
  }

  return jsonOk({ ok: true, candidatos: alvo.length, enviados, falhas, ja_reivindicados: jaReivindicados });
}

export async function GET(request: NextRequest) {
  return handle(request);
}

/** ops.cron_post (vigia de rotinas) só faz POST — mesma lógica e mesmo Bearer do GET. */
export async function POST(request: NextRequest) {
  return handle(request);
}
