import { after, type NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isDateIso, isTimeHm, isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { SupabaseAgenda } from '@/modules/placas/infrastructure/supabase-agenda';
import { ZoomMeetingProvider } from '@/modules/placas/infrastructure/zoom-meeting';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';
import { logSystemEvent } from '@/shared/infrastructure/observability/system-events';

/**
 * Apaga a sala Zoom DEPOIS da resposta (after): não segura a resposta ao admin.
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
      fonte: 'agenda_admin',
      titulo: 'Sala Zoom órfã — falha ao apagar (apagar manualmente no Zoom)',
      detalhe: { meeting_id: meetingId, motivo, solicitacao_id: ctx.solicitacao_id, data: ctx.data, hora: ctx.hora },
      aluno_id: ctx.aluno_id ? String(ctx.aluno_id) : null,
    });
  });
}

// Agendamento MANUAL de entrevista pelo admin (porta do gerarCalendlyLink/edição de entrevista
// do legado): define data/hora, cria a sala Zoom e opcionalmente notifica o candidato.
// O caminho normal continua sendo o auto-agendamento do candidato em /agendar-entrevista.
export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || (!ehAdminOuAcima(user) && !podeEditar(user, 'placas'))) {
    return jsonError('Não autorizado.', 403);
  }

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const id = String(body?.id ?? '');
  const data = String(body?.data ?? '').trim();
  const hora = String(body?.hora ?? '').trim().slice(0, 5);
  const enviarEmail = body?.enviar_email !== false;
  if (!isUuid(id) || !isDateIso(data) || !isTimeHm(hora)) {
    return jsonError('Informe data (AAAA-MM-DD) e hora (HH:MM) válidas.', 400);
  }

  const agenda = new SupabaseAgenda();
  const { data: sol } = await createAdminSupabase()
    .from('thb_placas_solicitacoes')
    .select('id, aluno_id, token, nome, email, status')
    .eq('id', id)
    .maybeSingle();
  if (!sol) return jsonError('Solicitação não encontrada.', 404);
  if (['rejeitado', 'concluido'].includes(String(sol.status ?? ''))) {
    return jsonError('Processo finalizado — não é possível agendar entrevista.', 409);
  }

  const zoom = new ZoomMeetingProvider();
  const meeting = await zoom.createMeeting({
    topic: `Entrevista ${sol.nome ?? ''} - Time Holding Brasil`,
    startIso: `${data}T${hora}:00`,
    durationMin: 60,
  });
  const zoomLink = meeting?.joinUrl ?? null;
  const meetingId = meeting?.meetingId ?? null;
  if (!zoomLink) {
    // Causa-raiz (HTTP/timeout) já foi logada pelo provider; aqui fica o contexto do candidato.
    await logSystemEvent({
      tipo: 'warn',
      fonte: 'agenda_admin',
      titulo: 'Entrevista agendada pelo admin SEM link Zoom — enviar link manualmente',
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
  if (confirmed.conflict) return jsonError('Já existe uma entrevista nesse horário. Escolha outro.', 409);
  if (!confirmed.ok) {
    await logSystemEvent({
      tipo: 'error',
      fonte: 'agenda_admin',
      titulo: 'Falha ao salvar agendamento manual no banco',
      detalhe: { solicitacao_id: sol.id, data, hora }, // sem nome/e-mail: thb_system_events não guarda PII
      aluno_id: sol.aluno_id ? String(sol.aluno_id) : null,
    });
    return jsonError('Não foi possível salvar o agendamento.', 502);
  }
  // Reagendamento: a sala da marcação anterior não é mais de ninguém.
  if (confirmed.previousMeetingId) apagarSalaDepois(zoom, confirmed.previousMeetingId, 'reagendamento', salaCtx);
  if (sol.aluno_id) await agenda.syncAuditoriaStep(String(sol.aluno_id), 2, { data, hora });

  // sent: o admin só vê "e-mail enviado" quando o envio foi confirmado (link via placaTrackingLink).
  let sent = false;
  if (enviarEmail) {
    const to = safeEmail(String(sol.email ?? ''));
    if (to) {
      const r = await enviarEmailPlaca({
        tipo: 'entrevista_agendada',
        to,
        nome: String(sol.nome ?? 'Candidato'),
        token: String(sol.token ?? ''),
        solicitacaoId: String(sol.id),
        extra: { entrevista_data: data, entrevista_hora: hora, zoom_link: zoomLink || undefined },
      });
      sent = r.sent;
    }
  }

  return jsonOk({ ok: true, zoom_link: zoomLink, zoom_pending: !zoomLink, data, hora, sent });
}
