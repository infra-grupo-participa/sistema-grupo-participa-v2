import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { onlyDigits, safeEmail } from '@/shared/infrastructure/http/validation';
import { clearPlacaCookie, resolvePlacaToken, setPlacaCookie } from '@/shared/infrastructure/http/session-cookie';
import { SupabasePublicPlaca, maskDocsForPublic } from '@/modules/placas/infrastructure/supabase-public-placa';
import { sanitizeFormPayload } from '@/modules/placas/application/sanitize-form';
import { validateFormProgress } from '@/modules/placas/domain/form-progress';
import { progressErrorMessage } from '@/modules/placas/application/progress-message';
import { getEmailContentByStatus, emailDynamicBoxes, type EmailTipo } from '@/modules/placas/application/email-content';
import { readPlacasConfig } from '@/modules/placas/infrastructure/supabase-config';
import { buildEmailTemplate } from '@/shared/infrastructure/email/template';
import { sendMail } from '@/shared/infrastructure/email/mailer';

// Porta de app/api/placa-public.php — fluxo público (token UUID, service_role server-side).

function todaySaoPaulo(): string {
  // Data de hoje no fuso America/Sao_Paulo (YYYY-MM-DD).
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());
}

/** Fecho do submit: confirmação de recebimento ou de cadastro (melhor-esforço, com override do admin). */
async function emailFechoSubmit(tipo: EmailTipo, email: string, nome: string, trackingLink: string): Promise<void> {
  try {
    const content = getEmailContentByStatus(tipo, {}, trackingLink);
    const { email_templates } = await readPlacasConfig();
    const ov = email_templates?.[tipo];
    if (ov) {
      if (ov.assunto?.trim()) content.assunto = ov.assunto.trim();
      if (ov.introducao?.trim()) content.templateData.introducao = ov.introducao.trim();
      if (ov.corpo_extra?.trim()) content.templateData.corpo_extra = emailDynamicBoxes(tipo, {}) + ov.corpo_extra.trim();
    }
    const html = buildEmailTemplate({ ...content.templateData, nome });
    await sendMail({ to: email, subject: content.assunto, html });
  } catch {
    /* e-mail é melhor-esforço — não bloqueia o submit */
  }
}

export async function GET(request: NextRequest) {
  const boot = bootstrapPublic(request, ['GET', 'POST']);
  if (!boot.ok) return boot.response;
  sweepRateLimit();
  if (!rateLimitOk(clientIp(request), 'gp_placa_public_rate_', 60, 300)) return jsonError('Tente novamente em instantes.', 429);

  const token = resolvePlacaToken(request);
  if (!token) return jsonError('Não foi possível concluir a operação.', 400);

  const gateway = new SupabasePublicPlaca();
  const row = await gateway.loadByToken(token);
  if (!row) return clearPlacaCookie(jsonError('Não foi possível concluir a operação.', 404));

  const payload: Record<string, unknown> = { ok: true, solicitacao: maskDocsForPublic(row) };

  if (request.nextUrl.searchParams.get('include_slots') === '1') {
    const today = todaySaoPaulo();
    const horarios = await gateway.loadActiveSlots(today);
    // Limite de busca de ocupados = maior slot_data + 1 dia.
    let bookedLimit: string | null = null;
    for (const s of horarios) {
      const d = String((s as Record<string, unknown>).slot_data ?? '');
      if (d && (!bookedLimit || d > bookedLimit)) bookedLimit = d;
    }
    payload.horarios = horarios;
    payload.booked_slots = await gateway.loadBookedSlots(bookedLimit);
  }

  return setPlacaCookie(jsonOk(payload), token);
}

export async function POST(request: NextRequest) {
  const boot = bootstrapPublic(request, ['GET', 'POST']);
  if (!boot.ok) return boot.response;
  sweepRateLimit();
  if (!rateLimitOk(clientIp(request), 'gp_placa_public_rate_', 60, 300)) return jsonError('Tente novamente em instantes.', 429);

  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  if (!body) return jsonError('Não foi possível concluir a operação.', 400);

  const action = String(body.action ?? 'save').trim();
  const token = resolvePlacaToken(request, body);
  const gateway = new SupabasePublicPlaca();

  // ── duplicate-check ──
  if (action === 'duplicate-check') {
    const field = String(body.field ?? '').trim();
    let value = String(body.value ?? '').trim();
    if (field === 'email') value = safeEmail(value);
    else if (field === 'documento_nf') value = onlyDigits(value);
    else return jsonError('Não foi possível concluir a operação.', 400);
    // includeRascunho=true: o save de nova solicitação considera rascunhos — o blur precisa
    // aplicar a MESMA regra, senão o usuário só descobre o bloqueio no 422 do final da etapa.
    const duplicate = value ? await gateway.duplicateExists(field as 'email' | 'documento_nf', value, token, true) : false;
    return jsonOk({ ok: true, duplicate });
  }

  // ── recover-session ──
  if (action === 'recover-session') {
    const email = safeEmail(String(body.email ?? '').trim());
    const documento = onlyDigits(body.documento_nf);
    if (!email || (documento.length !== 11 && documento.length !== 14)) {
      return jsonError('Não foi possível concluir a operação.', 400);
    }
    const row = await gateway.recoverSession(email, documento);
    if (!row) return jsonOk({ ok: true, found: false });
    return setPlacaCookie(
      jsonOk({ ok: true, found: true, solicitacao: maskDocsForPublic(row) }),
      String(row.token).toLowerCase(),
    );
  }

  // ── refazer (subiu de nível) ──
  if (action === 'refazer') {
    if (!token) return jsonError('Não foi possível concluir a operação.', 400);
    const res = await gateway.refazer(token);
    if (!res.ok) {
      if (res.reason === 'nao_refazivel') return jsonError('Esta solicitação ainda não pode ser refeita.', 409);
      if (res.reason === 'nivel_maximo') return jsonError('Você já está no nível máximo (Diamante Vermelho) — não há nível superior para refazer.', 409);
      if (res.reason === 'nao_encontrada') return clearPlacaCookie(jsonError('Não foi possível concluir a operação.', 404));
      return jsonError('Não foi possível iniciar o novo processo.', 502);
    }
    return setPlacaCookie(jsonOk({ ok: true, solicitacao: maskDocsForPublic(res.row) }), token);
  }

  if (action !== 'save') return jsonError('Não foi possível concluir a operação.', 400);

  // ── save ──
  const sanitized = sanitizeFormPayload(body);
  if (!sanitized.ok || !sanitized.payload) return jsonError('Não foi possível concluir a operação.', 400);
  const payload = sanitized.payload;

  const isNew = token === '';
  if (payload.email && (await gateway.duplicateExists('email', String(payload.email), token, isNew))) {
    return jsonError('Este e-mail já possui uma solicitação.', 422);
  }
  if (payload.documento_nf && (await gateway.duplicateExists('documento_nf', String(payload.documento_nf), token, isNew))) {
    return jsonError('Este documento já possui uma solicitação.', 422);
  }

  if (isNew) {
    const perr = validateFormProgress(payload);
    if (perr) return jsonError(progressErrorMessage(perr), 422);
    const created = await gateway.create(payload);
    if (!created) return jsonError('Não foi possível concluir a operação.', 502);
    const newToken = String(created.token).toLowerCase();
    // Vínculo antecipado com a central: já no cadastro sabemos se é aluno da base
    // (e-mail/documento) ou sem registro (possível ex-aluno).
    await gateway.vincularCentral(newToken, safeEmail(String(payload.email ?? '')), String(payload.documento_nf ?? ''));
    // Âncora multi-dispositivo: o link pessoal vai para o e-mail já na 1ª etapa —
    // o candidato pode continuar de qualquer aparelho mesmo sem o cookie desta sessão.
    const emailNovo = safeEmail(String(payload.email ?? ''));
    if (emailNovo) {
      await emailFechoSubmit('link_acesso', emailNovo, String(payload.nome ?? 'Candidato'), `${boot.origin.replace(/\/$/, '')}/solicitar-placa?token=${newToken}`);
    }
    return setPlacaCookie(
      jsonOk({ ok: true, token: newToken, status: created.status, step_index: created.step_index }),
      newToken,
    );
  }

  const existing = await gateway.loadByToken(token);
  if (!existing) return clearPlacaCookie(jsonError('Não foi possível concluir a operação.', 404));
  // Estados terminais só reabrem via RPC de refazer (fn_placas_refazer), que grava o piso
  // nivel_anterior. Bloquear a escrita direta aqui impede burlar o bloqueio de nível: sem
  // isso, uma chamada crua poderia re-salvar um cadastro_concluido sem passar pelo refazer.
  if (['rejeitado', 'concluido', 'cadastro_concluido'].includes(String(existing.status ?? ''))) {
    return jsonError('Não foi possível concluir a operação.', 409);
  }

  const perr = validateFormProgress({ ...payload, token }, existing);
  if (perr) return jsonError(progressErrorMessage(perr), 422);

  // Documentação entrando para análise (submit final ou reenvio de correção): acende a
  // notificação do admin — não-visto + topo da fila, com o badge "ação do aluno".
  const viraEnviado = payload.status === 'enviado' && String(existing.status ?? '') !== 'enviado';
  const reenvioCorrecao = existing.regularizacao_pendente === true && ('proof_url' in payload || 'declaracao_url' in payload);
  if (viraEnviado || reenvioCorrecao) {
    payload.admin_seen_at = null;
    payload.admin_attention_at = new Date().toISOString();
  }

  await gateway.updateByToken(token, payload);

  const emailDestino = safeEmail(String(payload.email ?? existing.email ?? ''));
  const nomeDestino = String(payload.nome ?? existing.nome ?? 'Candidato');
  const trackingLink = `${boot.origin.replace(/\/$/, '')}/solicitar-placa?token=${token}`;
  const jaEnviado = String(existing.status ?? '');

  if (payload.status === 'enviado' && Number(payload.step_index) === 6) {
    await gateway.promoteToAluno(token, payload);
    // Confirmação de recebimento — o candidato saía do funil sem nenhum protocolo/registro.
    if (emailDestino && jaEnviado !== 'enviado') await emailFechoSubmit('solicitacao_recebida', emailDestino, nomeDestino, trackingLink);
  } else if (payload.status === 'cadastro_concluido' && jaEnviado !== 'cadastro_concluido') {
    // Fecho do fluxo curto (nível abaixo de Ouro): registra o nível sem emissão de placa.
    if (emailDestino) await emailFechoSubmit('nivel_registrado', emailDestino, nomeDestino, trackingLink);
  }

  return setPlacaCookie(jsonOk({ ok: true, token, status: payload.status, step_index: payload.step_index }), token);
}
