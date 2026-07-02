import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk } from '@/shared/infrastructure/http/rate-limit';
import { safeEmail, isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { getEmailContentByStatus, emailDynamicBoxes, type EmailTipo, type EmailExtra } from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

const APP_BASE = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';
const TIPOS: EmailTipo[] = [
  'solicitacao_recebida',
  'docs_aprovados',
  'entrevista_agendada',
  'entrevista_finalizada',
  'placa_em_caminho',
  'placa_recebida',
  'retorno_auditoria',
  'nivel_registrado',
  'nao_compareceu',
  'solicitacao_rejeitada',
];

function safeInternalLink(url: string): string {
  const u = String(url ?? '').trim();
  if (!u) return '';
  try {
    const parsed = new URL(u, APP_BASE);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed.toString() : '';
  } catch {
    return '';
  }
}

// Porta de app/api/send-status-email.php — disparo dos e-mails do fluxo (admin).
export async function POST(request: NextRequest) {
  const user = await getCurrentUser();
  if (!user || (!ehAdminOuAcima(user) && !podeEditar(user, 'placas'))) {
    return jsonError('Não autorizado.', 403);
  }

  // Rota dispara e-mail para endereço arbitrário: limita por usuário para conter abuso/spam.
  if (!rateLimitOk(user.id, 'gp_email_status_rate_', 30, 300)) {
    return jsonError('Muitas requisições. Tente novamente em instantes.', 429);
  }

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body) return jsonError('Não foi possível concluir a operação.', 400);

  const email = safeEmail(String(body.email ?? ''));
  const tipo = String(body.tipo ?? '') as EmailTipo;
  if (!email || !TIPOS.includes(tipo)) return jsonError('Não foi possível concluir a operação.', 400);

  const token = String(body.token ?? '').trim();
  if (token && !isUuid(token)) return jsonError('Não foi possível concluir a operação.', 400);

  const trackingLink = token ? `${APP_BASE}/solicitar-placa?token=${encodeURIComponent(token)}` : '';
  const tokenLink = safeInternalLink(String(body.token_link ?? ''));
  let ctaLink = trackingLink;
  if ((tipo === 'docs_aprovados' || tipo === 'retorno_auditoria') && tokenLink) ctaLink = tokenLink;
  else if (!ctaLink && tokenLink) ctaLink = tokenLink;

  const extra: EmailExtra = {
    entrevista_data: body.entrevista_data ? String(body.entrevista_data) : undefined,
    entrevista_hora: body.entrevista_hora ? String(body.entrevista_hora) : undefined,
    zoom_link: body.zoom_link ? String(body.zoom_link) : undefined,
    codigo_rastreio: body.codigo_rastreio ? String(body.codigo_rastreio) : undefined,
    motivo_retorno: body.motivo_retorno ? String(body.motivo_retorno) : undefined,
  };
  const content = getEmailContentByStatus(tipo, extra, ctaLink);

  // Override editável pelo admin (thb_placas_config → email_templates).
  const { email_templates } = await readPlacasConfig();
  const ov = email_templates?.[tipo];
  if (ov) {
    if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
    if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
    // O corpo customizado substitui o texto estático, mas re-injetamos os blocos dinâmicos
    // (entrevista/rastreio/motivo) para não perder o conteúdo variável do e-mail.
    if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes(tipo, extra) + ov.corpo_extra.trim();
  }

  const html = buildEmailTemplate({ ...content.templateData, nome: String(body.nome ?? 'Candidato') });
  const sent = await sendMail({ to: email, subject: content.assunto, html });
  return jsonOk({ ok: sent });
}
