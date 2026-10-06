import { createHash } from 'node:crypto';
import { NextResponse, type NextRequest } from 'next/server';
import { allowedOrigins, clientIp } from '@/shared/infrastructure/http/security';
import { rateLimitOk, sweepRateLimit } from '@/shared/infrastructure/http/rate-limit';
import { atenderMcp } from '@/modules/comercial/application/mcp-servidor';
import { SupabaseMcpAdapter } from '@/modules/comercial/infrastructure/supabase-mcp';

export const dynamic = 'force-dynamic';

// MCP do Comercial (F7): servidor MCP remoto (Streamable HTTP, stateless, só POST + JSON). Como conectar e regras:
// docs/projetos/comercial/mcp.md. Público no proxy (sem cookie): autenticação própria por token pessoal
// (Authorization: Bearer gpc_…). O token vira hash sha-256 aqui; o texto nunca vai ao banco nem a log.

const TOKEN = /^Bearer\s+(gpc_[0-9a-f]{64})$/i;
const LIMITE_CORPO = 64 * 1024;
/** Teto por IP antes de tocar o banco (o limite real é por token, 60/min, no banco). */
const LIMITE_IP_MIN = 300;
const CABECALHOS = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } as const;

function json(corpo: unknown, status: number, extra: Record<string, string> = {}) {
  return NextResponse.json(corpo, { status, headers: { ...CABECALHOS, ...extra } });
}

/** Origin presente e de fora = navegador de terceiro (DNS rebinding/CSRF): recusa. Cliente MCP de servidor não manda Origin. */
function origemPermitida(req: NextRequest): boolean {
  const o = req.headers.get('origin');
  if (!o) return true;
  return [...allowedOrigins(), 'https://claude.ai'].includes(o.trim().toLowerCase().replace(/\/+$/, ''));
}

export async function POST(req: NextRequest) {
  if (!origemPermitida(req)) return json({ error: 'Origem não permitida.' }, 403);
  sweepRateLimit();
  if (!rateLimitOk(clientIp(req), 'gp_mcp_ip_', LIMITE_IP_MIN, 60)) return json({ error: 'Muitas requisições.' }, 429, { 'Retry-After': '60' });

  const m = TOKEN.exec((req.headers.get('authorization') || '').trim());
  if (!m) {
    return json({ error: 'Token ausente ou inválido. Use Authorization: Bearer gpc_…' }, 401, {
      'WWW-Authenticate': 'Bearer realm="grupo-participa-comercial"',
    });
  }
  const tipo = (req.headers.get('content-type') || '').toLowerCase();
  if (!tipo.includes('application/json')) return json({ error: 'Content-Type precisa ser application/json.' }, 415);

  const bruto = await req.text();
  if (bruto.length > LIMITE_CORPO) return json({ error: 'Mensagem grande demais.' }, 413);
  let corpo: unknown;
  try {
    corpo = JSON.parse(bruto);
  } catch {
    return json({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'JSON inválido.' } }, 400);
  }

  const hash = createHash('sha256').update(m[1].toLowerCase()).digest('hex');
  let r;
  try {
    r = await atenderMcp(corpo, hash, new SupabaseMcpAdapter());
  } catch (e) {
    // Sem segredo/ambiente (ex.: SUPABASE_JWT_SECRET ausente) ou falha inesperada: nada de detalhe para fora.
    console.error('[mcp] falha', e instanceof Error ? e.message : 'erro');
    return json({ error: 'MCP indisponível.' }, 503);
  }
  if (r.status === 202) return new NextResponse(null, { status: 202, headers: CABECALHOS });
  return json(r.corpo, r.status, r.autenticar ? { 'WWW-Authenticate': 'Bearer realm="grupo-participa-comercial", error="invalid_token"' } : {});
}

/** Sem stream SSE nem sessão: GET/DELETE não se aplicam (spec Streamable HTTP permite 405). */
export function GET() {
  return json({ error: 'Use POST (MCP Streamable HTTP, sem SSE).' }, 405, { Allow: 'POST' });
}

export function DELETE() {
  return json({ error: 'Servidor sem sessão.' }, 405, { Allow: 'POST' });
}
