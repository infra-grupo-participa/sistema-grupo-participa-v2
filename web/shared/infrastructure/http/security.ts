import { NextResponse } from 'next/server';
import { env } from '@/shared/infrastructure/config/env';

// Porta de app/api/_security.php — validação de origem, rate limit, validações e respostas.

// Origens oficiais aceitas em endpoints públicos (legado + env APP_ALLOWED_ORIGINS).
const LEGACY_ORIGINS = [
  'https://grupoparticipa.app.br',
  'https://sistema.grupoparticipa.com.br',
  'https://homologacao.grupoparticipa.app.br',
  'http://localhost:5500',
  'http://127.0.0.1:5500',
  'http://localhost:3000',
];

function originBase(value: string): string {
  const v = (value || '').trim();
  if (!v) return '';
  try {
    const u = new URL(v);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return '';
    return `${u.protocol}//${u.host}`.toLowerCase();
  } catch {
    return '';
  }
}

export function allowedOrigins(): string[] {
  return Array.from(new Set([...LEGACY_ORIGINS, ...env.app.allowedOrigins].map((o) => originBase(o)).filter(Boolean)));
}

/** Origem do próprio deploy (proto+host), considerando proxies (Hostinger/Vercel). */
function selfOrigin(request: Request): string {
  const h = request.headers;
  const proto = (h.get('x-forwarded-proto') || '').split(',')[0].trim() || 'https';
  const host = (h.get('x-forwarded-host') || h.get('host') || '').split(',')[0].trim();
  return host ? `${proto}://${host}`.toLowerCase() : '';
}

/**
 * Valida Origin/Referer contra a allowlist. Retorna a base válida ou null.
 * Requisições same-origin (a origem bate com o próprio host do deploy) são sempre
 * aceitas — é o caso normal do formulário e não configura CSRF de terceiros. Isso
 * dispensa cadastrar domínios de preview/definitivos (ex.: *.hostingersite.com) na allowlist.
 */
export function validateOrigin(request: Request): string | null {
  const origin = request.headers.get('origin') || '';
  const referer = request.headers.get('referer') || '';
  if (!origin && !referer) return null;
  const allow = allowedOrigins();
  const self = selfOrigin(request);
  for (const header of [origin, referer]) {
    const base = originBase(header);
    if (base && (allow.includes(base) || (self && base === self))) return base;
  }
  return null;
}

export function clientIp(request: Request): string {
  const h = request.headers;
  const candidates = [h.get('cf-connecting-ip'), h.get('x-forwarded-for'), h.get('x-real-ip')];
  for (const c of candidates) {
    if (!c) continue;
    const ip = c.split(',')[0].trim();
    if (ip) return ip;
  }
  return 'unknown';
}

const SECURITY_HEADERS: Record<string, string> = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Frame-Options': 'DENY',
  'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
};

/** Resposta JSON de erro com mensagem pública genérica (porta de api_json_error). */
export function jsonError(
  publicMessage = 'Não foi possível concluir a operação.',
  code = 400,
  meta: Record<string, string | null | undefined> = {},
): NextResponse {
  const payload: Record<string, string> = { error: publicMessage };
  for (const key of ['session_link', 'workflow_state', 'workflow_state_label']) {
    const v = meta[key];
    if (v) payload[key] = v;
  }
  return NextResponse.json(payload, { status: code, headers: SECURITY_HEADERS });
}

export function jsonOk(body: unknown, code = 200): NextResponse {
  return NextResponse.json(body, { status: code, headers: SECURITY_HEADERS });
}

/** Bootstrap de endpoint público: valida origem + método. Lança NextResponse via retorno. */
export function bootstrapPublic(
  request: Request,
  methods: string[],
): { ok: true; origin: string } | { ok: false; response: NextResponse } {
  if (request.method === 'OPTIONS') {
    return { ok: false, response: new NextResponse(null, { status: 200, headers: SECURITY_HEADERS }) };
  }
  if (!methods.includes(request.method)) {
    return { ok: false, response: jsonError('Não foi possível concluir a operação.', 405) };
  }
  const origin = validateOrigin(request);
  if (!origin) {
    return { ok: false, response: jsonError('Não foi possível concluir a operação.', 403) };
  }
  return { ok: true, origin };
}
