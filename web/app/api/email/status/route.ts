import type { NextRequest } from 'next/server';
import { jsonError, jsonOk, placaTrackingLink, publicAppBaseUrl } from '@/shared/infrastructure/http/security';
import { rateLimitOk } from '@/shared/infrastructure/http/rate-limit';
import { safeEmail, isUuid } from '@/shared/infrastructure/http/validation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { ehAdminOuAcima, podeEditar } from '@/shared/domain/auth';
import { linkZoomSeguro, type EmailTipo, type EmailExtra } from '@/modules/placas/application/email-content';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';

const TIPOS: EmailTipo[] = [
  'solicitacao_recebida',
  'docs_aprovados',
  'entrevista_agendada',
  'entrevista_finalizada',
  'placa_em_caminho',
  'placa_recebida',
  'retorno_auditoria',
  'nivel_registrado',
  'lembrete_entrevista',
  'nao_compareceu',
  'solicitacao_rejeitada',
];

/**
 * CTA vindo do cliente: só caminho relativo ("/x", nunca "//host" nem "/\host") ou URL absoluta
 * no host do próprio app (publicAppBaseUrl). Qualquer outra coisa → '' (cai no link de acompanhamento).
 */
function safeInternalLink(url: string): string {
  const u = String(url ?? '').trim();
  if (!u) return '';
  // Barra invertida e caracteres de controle/espaço: o parser de URL normaliza "\" em "/" → host externo.
  if (/[\\\s\u0000-\u001f\u007f]/.test(u)) return '';
  const base = publicAppBaseUrl();
  const relativo = u.startsWith('/');
  if (relativo && u.startsWith('//')) return '';
  try {
    const parsed = new URL(u, base);
    if (!['http:', 'https:'].includes(parsed.protocol)) return '';
    if (parsed.username || parsed.password) return '';
    if (parsed.origin !== new URL(base).origin) return '';
    if (!relativo && !/^https?:\/\//i.test(u)) return '';
    return parsed.toString();
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

  const trackingLink = token ? placaTrackingLink(token) : '';
  const tokenLink = safeInternalLink(String(body.token_link ?? ''));
  let ctaLink = trackingLink;
  if ((tipo === 'docs_aprovados' || tipo === 'retorno_auditoria') && tokenLink) ctaLink = tokenLink;
  else if (!ctaLink && tokenLink) ctaLink = tokenLink;

  const extra: EmailExtra = {
    entrevista_data: body.entrevista_data ? String(body.entrevista_data) : undefined,
    entrevista_hora: body.entrevista_hora ? String(body.entrevista_hora) : undefined,
    // Sala só se for zoom.us em https; qualquer outra coisa é ignorada (não vira link no e-mail).
    zoom_link: linkZoomSeguro(body.zoom_link ? String(body.zoom_link) : '') ?? undefined,
    codigo_rastreio: body.codigo_rastreio ? String(body.codigo_rastreio) : undefined,
    motivo_retorno: body.motivo_retorno ? String(body.motivo_retorno) : undefined,
  };

  const r = await enviarEmailPlaca({
    tipo,
    to: email,
    nome: String(body.nome ?? 'Candidato'),
    token,
    extra,
    ctaLink,
  });
  // `ok` mantido: o painel (placas-admin-data.sendStatusEmail) lê `ok === true` como "enviado".
  return jsonOk({ ok: r.sent, sent: r.sent });
}
