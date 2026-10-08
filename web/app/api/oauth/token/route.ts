import { type NextRequest } from 'next/server';
import { clientIp } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { emitirToken } from '@/modules/comercial/application/mcp-oauth';
import { criptoNode, SupabaseMcpOAuth } from '@/modules/comercial/infrastructure/supabase-mcp-oauth';
import { jsonOAuth, preflightOAuth } from '@/modules/comercial/infrastructure/oauth-http';

export const dynamic = 'force-dynamic';

// Token endpoint do OAuth do MCP (authorization_code + PKCE S256, refresh_token rotativo). Público (proxy): a prova é
// o código de uso único + code_verifier, ou o refresh. Os tokens saem 1 vez; o banco guarda só os hashes.
const LIMITE_CORPO = 8 * 1024;

async function lerFormulario(req: NextRequest): Promise<Record<string, string | undefined> | null> {
  const bruto = await req.text();
  if (bruto.length > LIMITE_CORPO) return null;
  const tipo = (req.headers.get('content-type') || '').toLowerCase();
  if (tipo.includes('application/json')) {
    try {
      const o = JSON.parse(bruto) as unknown;
      if (!o || typeof o !== 'object' || Array.isArray(o)) return null;
      return Object.fromEntries(Object.entries(o).filter(([, v]) => typeof v === 'string')) as Record<string, string>;
    } catch {
      return null;
    }
  }
  return Object.fromEntries(new URLSearchParams(bruto));
}

export async function POST(req: NextRequest) {
  sweepRateLimit();
  if (!rateLimitOk(clientIp(req), 'gp_oauth_tok_', 60, 60)) {
    return jsonOAuth({ error: 'slow_down', error_description: 'Muitas requisições.' }, 429, { 'Retry-After': '60' });
  }
  const form = await lerFormulario(req);
  if (!form) return jsonOAuth({ error: 'invalid_request', error_description: 'Corpo inválido.' }, 400);
  try {
    const r = await emitirToken(form, new SupabaseMcpOAuth(), criptoNode);
    return jsonOAuth(r.corpo, r.status, { Pragma: 'no-cache' });
  } catch (e) {
    console.error('[oauth/token] falha', e instanceof Error ? e.message : 'erro');
    return jsonOAuth({ error: 'temporarily_unavailable', error_description: 'Tente de novo em instantes.' }, 503);
  }
}

export const OPTIONS = preflightOAuth;
