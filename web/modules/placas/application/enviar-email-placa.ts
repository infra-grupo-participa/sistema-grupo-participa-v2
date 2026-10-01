// Envio único dos e-mails transacionais de placa: conteúdo + override do admin + template + Resend.
// Substitui a cópia espalhada em /api/placa, /api/agenda/confirm, /api/admin/placas/entrevista,
// /api/cron/interview-reminder e /api/email/status.

import {
  emailDynamicBoxes,
  getEmailContentByStatus,
  type EmailExtra,
  type EmailTipo,
} from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMailDetalhado } from '@/shared/infrastructure/email/mailer';
import { placaTrackingLink } from '@/shared/infrastructure/http/security';
import { logSystemEvent, snippet } from '@/shared/infrastructure/observability/system-events';
import { dominioEmail, mascararEmails } from '@/shared/infrastructure/observability/pii';

export interface EnviarEmailPlacaInput {
  tipo: EmailTipo;
  to: string;
  nome: string;
  token: string;
  extra?: EmailExtra;
  /** CTA explícito (ex.: link de agendamento já validado). Ausente → link de acompanhamento do token. */
  ctaLink?: string;
  /** Só para a trilha de falha (thb_system_events guarda o id, nunca e-mail/nome/token). */
  solicitacaoId?: string;
}

export interface EnviarEmailPlacaResult {
  ok: boolean;
  sent: boolean;
  id?: string;
  erro?: string;
}

export async function enviarEmailPlaca(input: EnviarEmailPlacaInput): Promise<EnviarEmailPlacaResult> {
  const { tipo, to, nome, token } = input;
  const extra = input.extra ?? {};
  try {
    const content = getEmailContentByStatus(tipo, extra, input.ctaLink ?? placaTrackingLink(token));
    const { email_templates } = await readPlacasConfig();
    const ov = email_templates?.[tipo];
    if (ov) {
      if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
      if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
      // Corpo customizado substitui o estático, mas re-injeta os blocos dinâmicos.
      if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes(tipo, extra) + ov.corpo_extra.trim();
    }
    const html = buildEmailTemplate({ ...content.templateData, nome });
    const r = await sendMailDetalhado({ to, subject: content.assunto, html });
    if (r.ok) return { ok: true, sent: true, id: r.id };
    await registrarFalha(tipo, to, input.solicitacaoId, r.erro ?? 'falha desconhecida');
    return { ok: false, sent: false, erro: r.erro };
  } catch (err) {
    const erro = snippet(err instanceof Error ? `${err.name}: ${err.message}` : String(err));
    await registrarFalha(tipo, to, input.solicitacaoId, erro);
    return { ok: false, sent: false, erro };
  }
}

async function registrarFalha(tipo: EmailTipo, to: string, solicitacaoId: string | undefined, erro: string): Promise<void> {
  await logSystemEvent({
    tipo: 'error',
    fonte: 'placas-email',
    titulo: `E-mail de placa não enviado (${tipo})`,
    detalhe: { tipo, solicitacao_id: solicitacaoId ?? null, para_dominio: dominioEmail(to), erro: mascararEmails(erro) },
  });
}
