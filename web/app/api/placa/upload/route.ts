import { randomBytes } from 'node:crypto';
import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { isUuid } from '@/shared/infrastructure/http/validation';
import { PLACA_SESSION_COOKIE } from '@/shared/infrastructure/http/session-cookie';
import { PLACA_MIME_MAP, validateUpload } from '@/shared/infrastructure/http/upload';
import { SupabasePublicPlaca } from '@/modules/placas/infrastructure/supabase-public-placa';

// Porta de app/api/upload-placa-documento.php — upload de comprovante/declaração.
export async function POST(request: NextRequest) {
  const boot = bootstrapPublic(request, ['POST']);
  if (!boot.ok) return boot.response;

  sweepRateLimit();
  if (!rateLimitOk(clientIp(request), 'gp_upload_placa_rate_', 15, 300)) {
    return jsonError('Tente novamente em instantes.', 429);
  }

  const form = await request.formData().catch(() => null);
  if (!form) return jsonError('Não foi possível validar os dados enviados.', 400);

  const bodyToken = String(form.get('token') ?? '').trim();
  const token = (isUuid(bodyToken) ? bodyToken : request.cookies.get(PLACA_SESSION_COOKIE)?.value ?? '').toLowerCase();
  const kind = String(form.get('kind') ?? '').trim();
  if (!isUuid(token) || !['comprovante', 'declaracao'].includes(kind)) {
    return jsonError('Não foi possível validar os dados enviados.', 400);
  }

  const file = form.get('file');
  const validated = await validateUpload(file instanceof File ? file : null, PLACA_MIME_MAP, 10 * 1024 * 1024);
  if (!validated) return jsonError('Não foi possível validar os dados enviados.', 400);

  const gateway = new SupabasePublicPlaca();
  const sol = await gateway.loadForUpload(token);
  if (!sol || ['rejeitado', 'concluido', 'enviado'].includes(String(sol.status))) {
    return jsonError('Não foi possível concluir a operação.', 404);
  }

  // Upload preso ao step atual (reduz replay/IDOR).
  const step = Number(sol.step_index ?? 0);
  if ((kind === 'comprovante' && step > 4) || (kind === 'declaracao' && step > 5)) {
    return jsonError('Não foi possível concluir a operação.', 409);
  }

  const path = `placas/${token}/${kind}_${randomBytes(16).toString('hex')}.${validated.ext}`;
  const url = await gateway.uploadDocumento(path, validated.buffer, validated.mime);
  if (!url) return jsonError('Não foi possível concluir a operação.', 502);

  return jsonOk({ ok: true, url });
}
