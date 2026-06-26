import type { NextRequest } from 'next/server';
import { bootstrapPublic, clientIp, jsonError, jsonOk } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { onlyDigits } from '@/shared/infrastructure/http/validation';
import { ViaCepLookup } from '@/modules/placas/infrastructure/viacep';

// Porta de app/api/cep.php — GET ?cep=XXXXXXXX, rate limit 60/5min por IP.
export async function GET(request: NextRequest) {
  const boot = bootstrapPublic(request, ['GET']);
  if (!boot.ok) return boot.response;

  sweepRateLimit();
  if (!rateLimitOk(clientIp(request), 'gp_cep_rate_', 60, 300)) {
    return jsonError('Tente novamente em instantes.', 429);
  }

  const cep = onlyDigits(request.nextUrl.searchParams.get('cep'));
  if (cep.length !== 8) return jsonError('Não foi possível concluir a operação.', 400);

  const result = await new ViaCepLookup().buscar(cep).catch(() => null);
  if (!result) return jsonError('Não foi possível concluir a operação.', 404);

  return jsonOk(result);
}
