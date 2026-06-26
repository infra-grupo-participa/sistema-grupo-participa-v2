import type { NextRequest } from 'next/server';
import { jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { safeEmail, isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { getEmailContentByStatus, type EmailTipo } from '@/modules/placas/application/email-content';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

const APP_BASE = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';
const TIPOS: EmailTipo[] = [
  'docs_aprovados',
  'entrevista_agendada',
  'entrevista_finalizada',
  'placa_em_caminho',
  'retorno_auditoria',
  'nivel_registrado',
  'nao_compareceu',
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

  const content = getEmailContentByStatus(tipo, {
    entrevista_data: body.entrevista_data ? String(body.entrevista_data) : undefined,
    entrevista_hora: body.entrevista_hora ? String(body.entrevista_hora) : undefined,
    zoom_link: body.zoom_link ? String(body.zoom_link) : undefined,
    codigo_rastreio: body.codigo_rastreio ? String(body.codigo_rastreio) : undefined,
    motivo_retorno: body.motivo_retorno ? String(body.motivo_retorno) : undefined,
  }, ctaLink);

  const html = buildEmailTemplate({ ...content.templateData, nome: String(body.nome ?? 'Candidato') });
  const sent = await sendMail({ to: email, subject: content.assunto, html });
  return jsonOk({ ok: sent });
}
