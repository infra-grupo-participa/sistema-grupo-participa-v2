import { after, type NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { isDateIso, isTimeHm, safeEmail } from '@/shared/infrastructure/http/validation';
import { resolvePlacaToken } from '@/shared/infrastructure/http/session-cookie';
import { withSlotLock } from '@/shared/infrastructure/http/slot-lock';
import { SupabaseAgenda } from '@/modules/placas/infrastructure/supabase-agenda';
import { ZoomMeetingProvider } from '@/modules/placas/infrastructure/zoom-meeting';
import { sendMail } from '@/shared/infrastructure/email/mailer';
import { buildGcalLink, buildSlotStart, conflictsForSlot, rescheduleBlockReason } from '@/modules/placas/domain/agendamento';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';
import { logFunilPlacaAgendado } from '@/modules/placas/infrastructure/supabase-public-placa';
import { logSystemEvent } from '@/shared/infrastructure/observability/system-events';

/**
 * Apaga a sala Zoom DEPOIS da resposta (after): não segura a trava do slot nem o candidato/admin.
 * deleteMeeting nunca lança e devolve false na falha — aí a sala órfã vira evento rastreável.
 */
function apagarSalaDepois(
  zoom: ZoomMeetingProvider,
  meetingId: string,
  motivo: 'reagendamento' | 'conflito' | 'falha_gravacao',
  ctx: { solicitacao_id: unknown; aluno_id: unknown; data: string; hora: string },
): void {
  after(async () => {
    const ok = await zoom.deleteMeeting(meetingId).catch(() => false);
    if (ok) return;
    await logSystemEvent({
      tipo: 'error',
      fonte: 'agenda_confirm',
      titulo: 'Sala Zoom órfã — falha ao apagar (apagar manualmente no Zoom)',
      detalhe: { meeting_id: meetingId, motivo, solicitacao_id: ctx.solicitacao_id, data: ctx.data, hora: ctx.hora },
      aluno_id: ctx.aluno_id ? String(ctx.aluno_id) : null,
    });
  });
}

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');


// Porta de app/api/confirm-horario.php — confirma horário, cria Zoom e notifica admin.
export async function POST(request: NextRequest) {
  const boot = bootstrapPublic(request, ['POST']);
  if (!boot.ok) return boot.response;
  const origin = boot.origin.replace(/\/$/, '');
  // session_link volta só na resposta JSON ao próprio cliente (Origin já validado); o link
  // de e-mail usa placaTrackingLink (NEXT_PUBLIC_APP_URL), nunca o Host da requisição.
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

    const zoom = new ZoomMeetingProvider();
    const meeting = await zoom.createMeeting({
      topic: `Entrevista ${sol.nome ?? ''} - Time Holding Brasil`,
      startIso: `${data}T${slotHour}:00`,
      durationMin: 60,
    });
    const zoomLink = meeting?.joinUrl ?? null;
    const meetingId = meeting?.meetingId ?? null;
    if (!zoomLink) {
      // Causa-raiz (HTTP/timeout) já foi logada pelo provider; aqui fica o contexto do candidato.
      await logSystemEvent({
        tipo: 'warn',
        fonte: 'agenda_confirm',
        titulo: 'Entrevista agendada SEM link Zoom — enviar link manualmente',
        detalhe: { solicitacao_id: sol.id, data, hora }, // sem nome/e-mail: thb_system_events não guarda PII
        aluno_id: sol.aluno_id ? String(sol.aluno_id) : null,
      });
    }

    const confirmed = await agenda.confirm(String(sol.id), {
      entrevista_data: data,
      entrevista_hora: hora,
      entrevista_link: zoomLink,
      meet_link: zoomLink,
      zoom_meeting_id: meetingId,
    });
    const salaCtx = { solicitacao_id: sol.id, aluno_id: sol.aluno_id, data, hora };
    // Gravação não aconteceu: a sala recém-criada ficaria órfã no Zoom.
    if (!confirmed.ok && meetingId) apagarSalaDepois(zoom, meetingId, confirmed.conflict ? 'conflito' : 'falha_gravacao', salaCtx);
    if (confirmed.conflict) return jsonError('Este horário acabou de ser reservado por outra pessoa. Escolha outro.', 409, { session_link: sessionLink });
    if (!confirmed.ok) {
      await logSystemEvent({
        tipo: 'error',
        fonte: 'agenda_confirm',
        titulo: 'Falha ao salvar o agendamento no banco (HTTP 502 ao candidato)',
        detalhe: { solicitacao_id: sol.id, data, hora }, // sem nome/e-mail: thb_system_events não guarda PII
        aluno_id: sol.aluno_id ? String(sol.aluno_id) : null,
      });
      return jsonError('Não foi possível concluir a operação.', 502);
    }
    // Reagendamento: a sala da marcação anterior não é mais de ninguém.
    if (confirmed.previousMeetingId) apagarSalaDepois(zoom, confirmed.previousMeetingId, 'reagendamento', salaCtx);
    if (sol.aluno_id) await agenda.syncAuditoriaStep(String(sol.aluno_id), 2, { data, hora });
    await logFunilPlacaAgendado({
      solicitacao_id: String(sol.id),
      aluno_id: sol.aluno_id ? String(sol.aluno_id) : null,
      detalhe: { data, hora, origem: 'aluno', zoom_pending: !zoomLink },
    });

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

    // Confirmação ao CANDIDATO (melhor-esforço) — o link do Zoom vai por e-mail além da tela.
    // email_enviado: a tela só afirma "enviamos por e-mail" quando o envio foi confirmado.
    const candidatoEmail = safeEmail(String(sol.email ?? ''));
    const emailEnviado = candidatoEmail
      ? (
          await enviarEmailPlaca({
            tipo: 'entrevista_agendada',
            to: candidatoEmail,
            solicitacaoId: String(sol.id),
            nome: String(sol.nome ?? 'Candidato'),
            token,
            extra: { entrevista_data: data, entrevista_hora: hora, zoom_link: zoomLink || undefined },
          })
        ).sent
      : false;

    return jsonOk({
      ok: true,
      zoom_link: zoomLink,
      zoom_pending: !zoomLink,
      gcal_link: buildGcalLink(String(sol.nome ?? ''), data, hora, zoomLink),
      data,
      hora,
      session_link: sessionLink,
      status: 'docs_aprovados',
      auditoria_step: 2,
      workflow_state: 'entrevista_agendada',
      workflow_state_label: 'Entrevista Agendada',
      email_enviado: emailEnviado,
    });
  });

  if (result === null) return jsonError('Não foi possível concluir a operação.', 409, { session_link: sessionLink });
  return result;
}
