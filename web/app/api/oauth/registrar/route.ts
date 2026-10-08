import { type NextRequest } from 'next/server';
import { clientIp } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { registrarCliente } from '@/modules/comercial/application/mcp-oauth';
import { SupabaseMcpOAuth } from '@/modules/comercial/infrastructure/supabase-mcp-oauth';
import { jsonOAuth, preflightOAuth } from '@/modules/comercial/infrastructure/oauth-http';

export const dynamic = 'force-dynamic';

// Registro dinâmico de cliente OAuth (RFC 7591) do MCP do Comercial. Público (proxy): o Claude se registra sozinho.
// Só aceita redirect do Claude ou localhost (domain/mcp-oauth.ts). Teto: 10/h por IP aqui e 200/dia no banco.
const LIMITE_CORPO = 8 * 1024;

export async function POST(req: NextRequest) {
  sweepRateLimit();
  if (!rateLimitOk(clientIp(req), 'gp_oauth_reg_', 10, 3600)) {
    return jsonOAuth({ error: 'slow_down', error_description: 'Muitos registros. Tente mais tarde.' }, 429, { 'Retry-After': '3600' });
  }
  const bruto = await req.text();
  if (bruto.length > LIMITE_CORPO) return jsonOAuth({ error: 'invalid_client_metadata', error_description: 'Corpo grande demais.' }, 413);
  let corpo: unknown;
  try {
    corpo = JSON.parse(bruto);
  } catch {
    return jsonOAuth({ error: 'invalid_client_metadata', error_description: 'JSON inválido.' }, 400);
  }
  try {
    const r = await registrarCliente(corpo, new SupabaseMcpOAuth());
    return jsonOAuth(r.corpo, r.status);
  } catch (e) {
    console.error('[oauth/registrar] falha', e instanceof Error ? e.message : 'erro');
    return jsonOAuth({ error: 'temporarily_unavailable', error_description: 'Tente de novo em instantes.' }, 503);
  }
}

export const OPTIONS = preflightOAuth;
