import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { isDateIso, isTimeHm, isUuid, safeEmail } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { SupabaseAgenda } from '@/modules/placas/infrastructure/supabase-agenda';
import { ZoomMeetingProvider } from '@/modules/placas/infrastructure/zoom-meeting';
import { getEmailContentByStatus, emailDynamicBoxes, type EmailExtra } from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

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

  const meeting = await new ZoomMeetingProvider().createMeeting({
    topic: `Entrevista ${sol.nome ?? ''} - Treinamento em Holding Familiar`,
    startIso: `${data}T${hora}:00`,
    durationMin: 60,
  });
  const zoomLink = meeting?.joinUrl ?? null;

  const confirmed = await agenda.confirm(String(sol.id), {
    entrevista_data: data,
    entrevista_hora: hora,
    entrevista_link: zoomLink,
    meet_link: zoomLink,
  });
  if (confirmed.conflict) return jsonError('Já existe uma entrevista nesse horário. Escolha outro.', 409);
  if (!confirmed.ok) return jsonError('Não foi possível salvar o agendamento.', 502);
  if (sol.aluno_id) await agenda.syncAuditoriaStep(String(sol.aluno_id), 2);

  if (enviarEmail) {
    const to = safeEmail(String(sol.email ?? ''));
    if (to) {
      try {
        const appBase = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';
        const extra: EmailExtra = { entrevista_data: data, entrevista_hora: hora, zoom_link: zoomLink || undefined };
        const content = getEmailContentByStatus('entrevista_agendada', extra, `${appBase}/solicitar-placa?token=${sol.token}`);
        const { email_templates } = await readPlacasConfig();
        const ov = email_templates?.['entrevista_agendada'];
        if (ov) {
          if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
          if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
          if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes('entrevista_agendada', extra) + ov.corpo_extra.trim();
        }
        const html = buildEmailTemplate({ ...content.templateData, nome: String(sol.nome ?? 'Candidato') });
        await sendMail({ to, subject: content.assunto, html });
      } catch { /* e-mail é melhor-esforço */ }
    }
  }

  return jsonOk({ ok: true, zoom_link: zoomLink, zoom_pending: !zoomLink, data, hora });
}
