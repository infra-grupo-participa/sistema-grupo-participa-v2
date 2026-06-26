import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { onlyDigits, safeEmail } from '@/shared/infrastructure/http/validation';
import { clearPlacaCookie, resolvePlacaToken, setPlacaCookie } from '@/shared/infrastructure/http/session-cookie';
import { SupabasePublicPlaca, maskDocsForPublic } from '@/modules/placas/infrastructure/supabase-public-placa';
import { sanitizeFormPayload } from '@/modules/placas/application/sanitize-form';
import { validateFormProgress } from '@/modules/placas/domain/form-progress';

// Porta de app/api/placa-public.php — fluxo público (token UUID, service_role server-side).

function todaySaoPaulo(): string {
  // Data de hoje no fuso America/Sao_Paulo (YYYY-MM-DD).
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());
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
    const duplicate = value ? await gateway.duplicateExists(field as 'email' | 'documento_nf', value, token, false) : false;
    return jsonOk({ ok: true, duplicate });
  }

  // ── recover-session ──
  if (action === 'recover-session') {
    const email = safeEmail(String(body.email ?? '').trim());
    const documento = onlyDigits(body.documento_nf);
    if (!email || (documento !== '' && documento.length !== 11 && documento.length !== 14) || documento === '') {
      return jsonError('Não foi possível concluir a operação.', 400);
    }
    const row = await gateway.recoverSession(email, documento);
    if (!row) return jsonOk({ ok: true, found: false });
    return setPlacaCookie(
      jsonOk({ ok: true, found: true, solicitacao: maskDocsForPublic(row) }),
      String(row.token).toLowerCase(),
    );
  }

  if (action !== 'save') return jsonError('Não foi possível concluir a operação.', 400);

  // ── save ──
  const sanitized = sanitizeFormPayload(body);
  if (!sanitized.ok || !sanitized.payload) return jsonError('Não foi possível concluir a operação.', 400);
  const payload = sanitized.payload;

  const isNew = token === '';
  if (payload.email && (await gateway.duplicateExists('email', String(payload.email), token, isNew))) {
    return jsonError('Não foi possível concluir a operação.', 422);
  }
  if (payload.documento_nf && (await gateway.duplicateExists('documento_nf', String(payload.documento_nf), token, isNew))) {
    return jsonError('Não foi possível concluir a operação.', 422);
  }

  if (isNew) {
    if (validateFormProgress(payload)) return jsonError('Não foi possível concluir a operação.', 422);
    const created = await gateway.create(payload);
    if (!created) return jsonError('Não foi possível concluir a operação.', 502);
    const newToken = String(created.token).toLowerCase();
    return setPlacaCookie(
      jsonOk({ ok: true, token: newToken, status: created.status, step_index: created.step_index }),
      newToken,
    );
  }

  const existing = await gateway.loadByToken(token);
  if (!existing) return clearPlacaCookie(jsonError('Não foi possível concluir a operação.', 404));
  if (['rejeitado', 'concluido'].includes(String(existing.status ?? ''))) return jsonError('Não foi possível concluir a operação.', 409);

  if (validateFormProgress({ ...payload, token }, existing)) return jsonError('Não foi possível concluir a operação.', 422);

  await gateway.updateByToken(token, payload);

  if (payload.status === 'enviado' && Number(payload.step_index) === 6) {
    await gateway.promoteToAluno(token, payload);
  }

  return setPlacaCookie(jsonOk({ ok: true, token, status: payload.status, step_index: payload.step_index }), token);
}
