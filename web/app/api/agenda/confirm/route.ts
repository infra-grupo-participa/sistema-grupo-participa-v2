import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { isDateIso, isTimeHm } from '@/shared/infrastructure/http/validation';
import { resolvePlacaToken } from '@/shared/infrastructure/http/session-cookie';
import { withSlotLock } from '@/shared/infrastructure/http/slot-lock';
import { SupabaseAgenda } from '@/modules/placas/infrastructure/supabase-agenda';
import { ZoomMeetingProvider } from '@/modules/placas/infrastructure/zoom-meeting';
import { sendMail } from '@/shared/infrastructure/email/mailer';
import { buildSlotStart, conflictsForSlot, rescheduleBlockReason } from '@/modules/placas/domain/agendamento';

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function gcalLink(nome: string, data: string, hora: string, zoomLink: string | null): string {
  const start = data.replace(/-/g, '') + 'T' + hora.replace(':', '') + '00';
  const h = parseInt(hora.split(':')[0], 10);
  const end = data.replace(/-/g, '') + 'T' + String(h + 1).padStart(2, '0') + hora.split(':')[1] + '00';
  const details = zoomLink
    ? `Entrevista - Treinamento em Holding Familiar.\n\nLink Zoom:\n${zoomLink}`
    : 'Entrevista - Treinamento em Holding Familiar.\n\nO link da reunião será enviado em breve.';
  let url =
    'https://calendar.google.com/calendar/render?action=TEMPLATE' +
    `&text=${encodeURIComponent('Entrevista ' + (nome || 'Candidato') + ' - Treinamento em Holding Familiar')}` +
    `&dates=${start}/${end}` +
    `&details=${encodeURIComponent(details)}`;
  if (zoomLink) url += `&location=${encodeURIComponent(zoomLink)}`;
  return url;
}

// Porta de app/api/confirm-horario.php — confirma horário, cria Zoom e notifica admin.
export async function POST(request: NextRequest) {
  const boot = bootstrapPublic(request, ['POST']);
  if (!boot.ok) return boot.response;
  const origin = boot.origin.replace(/\/$/, '');
  const sessionLink = `${origin}/solicitar-placa`;

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body) return jsonError('Não foi possível concluir a operação.', 400);

  const token = resolvePlacaToken(request, body);
  const data = String(body.data ?? '').trim();
  const hora = String(body.hora ?? '').trim();
  if (!token || !isDateIso(data) || !isTimeHm(hora)) return jsonError('Não foi possível concluir a operação.', 400);

  sweepRateLimit();
  if (!rateLimitOk(`${clientIp(request)}|${token}`, 'gp_confirm_rate_', 12, 300)) {
    return jsonError('Tente novamente em instantes.', 429);
  }

  const now = new Date();
  const start = buildSlotStart(data, hora);
  if (!start) return jsonError('Não foi possível concluir a operação.', 400);

  const agenda = new SupabaseAgenda();
  const sol = await agenda.loadByToken(token);
  if (!sol) return jsonError('Não foi possível concluir a operação.', 404);

  // Guardas de (re)agendamento (status válido, não finalizada, não passada, fora de 24h).
  if (rescheduleBlockReason(sol, now) !== null) {
    return jsonError('Não foi possível concluir a operação.', 409, { session_link: sessionLink });
  }

  const slotHour = hora.slice(0, 5);
  const result = await withSlotLock(`${data} ${slotHour}`, async () => {
    if (!(await agenda.slotIsActive(data, slotHour))) {
      return jsonError('Não foi possível concluir a operação.', 409, { session_link: sessionLink });
    }
    const busy = await agenda.loadBusyRows(data);
    if (busy.some((row) => conflictsForSlot(row, token, data, slotHour, now))) {
      return jsonError('Não foi possível concluir a operação.', 409, { session_link: sessionLink });
    }

    const meeting = await new ZoomMeetingProvider().createMeeting({
      topic: `Entrevista ${sol.nome ?? ''} - Treinamento em Holding Familiar`,
      startIso: `${data}T${slotHour}:00`,
      durationMin: 60,
    });
    const zoomLink = meeting?.joinUrl ?? null;

    const ok = await agenda.confirm(String(sol.id), {
      entrevista_data: data,
      entrevista_hora: hora,
      entrevista_link: zoomLink,
      meet_link: zoomLink,
    });
    if (!ok) return jsonError('Não foi possível concluir a operação.', 502);
    if (sol.aluno_id) await agenda.syncAuditoriaStep(String(sol.aluno_id), 2);

    // Notifica admin (melhor-esforço).
    const adminEmail = process.env.ADMIN_EMAIL || 'contato@grupoparticipa.app.br';
    const dataFmt = data.split('-').reverse().join('/');
    const zoomBtn = zoomLink
      ? `<p><a href="${escapeHtml(zoomLink)}" target="_blank" style="background:#2D8CFF;color:#fff;text-decoration:none;padding:12px 25px;border-radius:5px;font-weight:bold;display:inline-block">Acessar Sala (Zoom)</a></p>` // hex-ok: e-mail
      : '<p style="color:#c00;font-weight:bold;">⚠ Link Zoom não foi gerado — verificar manualmente.</p>'; // hex-ok: e-mail
    await sendMail({
      to: adminEmail,
      subject: `Candidato agendou entrevista — ${dataFmt} às ${hora}`,
      html:
        `<div style="font-family:Arial,sans-serif;color:#333;max-width:600px;margin:0 auto;padding:20px;">` + // hex-ok: e-mail
        `<h2 style="color:#F29725;">Candidato agendou entrevista</h2>` + // hex-ok: e-mail
        `<div style="background:#f8f9fa;border-left:4px solid #F29725;padding:15px;margin:20px 0;">` + // hex-ok: e-mail
        `<p style="margin:0"><strong>Candidato:</strong> ${escapeHtml(String(sol.nome ?? 'Candidato'))}</p>` +
        `<p style="margin:5px 0 0"><strong>E-mail:</strong> ${escapeHtml(String(sol.email ?? ''))}</p>` +
        `<p style="margin:5px 0 0"><strong>Data:</strong> ${dataFmt}</p>` +
        `<p style="margin:5px 0 0"><strong>Hora:</strong> ${escapeHtml(hora)}</p></div>${zoomBtn}</div>`,
    }).catch(() => false);

    return jsonOk({
      ok: true,
      zoom_link: zoomLink,
      zoom_pending: !zoomLink,
      gcal_link: gcalLink(String(sol.nome ?? ''), data, hora, zoomLink),
      data,
      hora,
      session_link: sessionLink,
      status: 'docs_aprovados',
      auditoria_step: 2,
      workflow_state: 'entrevista_agendada',
      workflow_state_label: 'Entrevista Agendada',
    });
  });

  if (result === null) return jsonError('Não foi possível concluir a operação.', 409, { session_link: sessionLink });
  return result;
}
