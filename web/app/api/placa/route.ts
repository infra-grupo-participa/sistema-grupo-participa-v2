import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { onlyDigits, safeEmail } from '@/shared/infrastructure/http/validation';
import {
  clearPlacaCookie,
  failedTokenIsCookie,
  resolvePlacaTokenSource,
  setPlacaCookie,
  type ResolvedPlacaToken,
} from '@/shared/infrastructure/http/session-cookie';
import { SupabasePublicPlaca, logFunilPlacaSubmit, maskDocsForPublic } from '@/modules/placas/infrastructure/supabase-public-placa';
import { sanitizeFormPayload } from '@/modules/placas/application/sanitize-form';
import { validateFormProgress } from '@/modules/placas/domain/form-progress';
import { progressErrorMessage } from '@/modules/placas/application/progress-message';
import type { EmailTipo } from '@/modules/placas/application/email-content';
import { enviarEmailPlaca } from '@/modules/placas/application/enviar-email-placa';

// Porta de app/api/placa-public.php — fluxo público (token UUID, service_role server-side).

function todaySaoPaulo(): string {
  // Data de hoje no fuso America/Sao_Paulo (YYYY-MM-DD).
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());
}

/** Fecho do submit: confirmação de recebimento ou de cadastro (melhor-esforço, com override do admin). */
async function emailFechoSubmit(tipo: EmailTipo, email: string, nome: string, token: string): Promise<boolean> {
  // e-mail é melhor-esforço — não bloqueia o submit; enviarEmailPlaca nunca lança e registra a falha.
  return (await enviarEmailPlaca({ tipo, to: email, nome, token })).sent;
}

/**
 * 404 de token inexistente. Contrato: { error, token_invalido: true, token_fonte, sessao_preservada }.
 * O cookie só é apagado quando o token que falhou ERA o do cookie — UUID inválido vindo da
 * URL/body não derruba a sessão válida guardada no cookie.
 */
function tokenNotFound(r: ResolvedPlacaToken, cookieTambemFalhou = false) {
  const doCookie = cookieTambemFalhou || failedTokenIsCookie(r);
  const res = jsonOk(
    {
      error: 'Não foi possível concluir a operação.',
      token_invalido: true,
      token_fonte: r.source,
      sessao_preservada: !doCookie && r.cookieToken !== '',
    },
    404,
  );
  return doCookie ? clearPlacaCookie(res) : res;
}

export async function GET(request: NextRequest) {
  const boot = bootstrapPublic(request, ['GET', 'POST']);
  if (!boot.ok) return boot.response;
  sweepRateLimit();
  if (!rateLimitOk(clientIp(request), 'gp_placa_public_rate_', 60, 300)) return jsonError('Tente novamente em instantes.', 429);

  const resolved = resolvePlacaTokenSource(request);
  if (!resolved.token) return jsonError('Não foi possível concluir a operação.', 400);

  const gateway = new SupabasePublicPlaca();
  let token = resolved.token;
  let row = await gateway.loadByToken(token);
  let urlInvalida = false;
  if (!row && resolved.source === 'query' && resolved.cookieToken && resolved.cookieToken !== token) {
    // Link com UUID inexistente + cookie de sessão: GET é só leitura, então cai para a
    // sessão do cookie em vez de derrubá-la. O front recebe token_url_invalido + o token real.
    const fromCookie = await gateway.loadByToken(resolved.cookieToken);
    if (fromCookie) {
      row = fromCookie;
      token = resolved.cookieToken;
      urlInvalida = true;
    } else {
      // Os dois falharam: o cookie também é lixo — pode limpar.
      return tokenNotFound(resolved, true);
    }
  }
  if (!row) return tokenNotFound(resolved);

  const payload: Record<string, unknown> = { ok: true, solicitacao: maskDocsForPublic(row) };
  if (urlInvalida) {
    payload.token_url_invalido = true;
    payload.token_fonte = 'cookie';
    payload.token = token;
  }

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
  const resolved = resolvePlacaTokenSource(request, body);
  const token = resolved.token;
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
      if (res.reason === 'nao_encontrada') return tokenNotFound(resolved);
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
    // email_enviado: a tela só afirma "enviamos o link" quando o envio foi confirmado.
    const emailEnviado = emailNovo
      ? await emailFechoSubmit('link_acesso', emailNovo, String(payload.nome ?? 'Candidato'), newToken)
      : false;
    return setPlacaCookie(
      jsonOk({ ok: true, token: newToken, status: created.status, step_index: created.step_index, email_enviado: emailEnviado }),
      newToken,
    );
  }

  const existing = await gateway.loadByToken(token);
  if (!existing) return tokenNotFound(resolved);
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

  const gravado = await gateway.updateByToken(token, payload);
  // Falha já virou evento no gateway; o candidato não pode receber ok com nada salvo.
  if (!gravado.ok) return jsonError('Não conseguimos salvar seus dados agora. Tente novamente em instantes.', 502);

  const emailDestino = safeEmail(String(payload.email ?? existing.email ?? ''));
  const nomeDestino = String(payload.nome ?? existing.nome ?? 'Candidato');
  const jaEnviado = String(existing.status ?? '');

  if (payload.status === 'enviado' && Number(payload.step_index) === 6) {
    await gateway.promoteToAluno(token, payload);
    // Confirmação de recebimento — o candidato saía do funil sem nenhum protocolo/registro.
    if (jaEnviado !== 'enviado') {
      await logFunilPlacaSubmit({
        solicitacao_id: String(existing.id ?? ''),
        aluno_id: existing.aluno_id ? String(existing.aluno_id) : null,
        detalhe: { origem: 'aluno', nivel: payload.nivel ?? existing.nivel ?? null },
      });
      // Link de e-mail: enviarEmailPlaca usa placaTrackingLink (NEXT_PUBLIC_APP_URL), nunca o Host da requisição.
      if (emailDestino) await emailFechoSubmit('solicitacao_recebida', emailDestino, nomeDestino, token);
    }
  } else if (payload.status === 'cadastro_concluido' && jaEnviado !== 'cadastro_concluido') {
    // Fecho do fluxo curto (nível abaixo de Ouro): registra o nível sem emissão de placa.
    if (emailDestino) await emailFechoSubmit('nivel_registrado', emailDestino, nomeDestino, token);
  }

  return setPlacaCookie(jsonOk({ ok: true, token, status: payload.status, step_index: payload.step_index }), token);
}
