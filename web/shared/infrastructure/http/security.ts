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

const APP_URL_FALLBACK = 'https://grupoparticipa.app.br';

/**
 * Base pública do app para links que saem do servidor (e-mail, lembrete).
 * Vem SÓ de NEXT_PUBLIC_APP_URL (fallback de produção) — nunca do Host/X-Forwarded-Host
 * da requisição, que o cliente controla (host spoofing → link ?token= apontando para
 * domínio do atacante). Sem barra final.
 */
export function publicAppBaseUrl(): string {
  return originBase(process.env.NEXT_PUBLIC_APP_URL || '') || APP_URL_FALLBACK;
}

/** Link pessoal do candidato (?token=) — sempre ancorado em publicAppBaseUrl(). */
export function placaTrackingLink(token: string): string {
  return `${publicAppBaseUrl()}/solicitar-placa?token=${encodeURIComponent(token)}`;
}

/**
 * Origem do próprio deploy (proto+host), considerando proxies (Hostinger/Vercel).
 * Usada SÓ para reconhecer requisição same-origin em validateOrigin — nunca para montar link.
 */
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
 *
 * GET sem Origin E sem Referer (alguns navegadores omitem ambos em fetch same-origin):
 * aceito quando Sec-Fetch-Site é same-origin, none ou ausente. cross-site/same-site → null.
 * POST sem Origin/Referer continua recusado.
 */
export function validateOrigin(request: Request): string | null {
  const origin = request.headers.get('origin') || '';
  const referer = request.headers.get('referer') || '';
  if (!origin && !referer) {
    if (request.method !== 'GET') return null;
    const site = (request.headers.get('sec-fetch-site') || '').trim().toLowerCase();
    if (site === '' || site === 'same-origin' || site === 'none') return publicAppBaseUrl();
    return null;
  }
  const allow = allowedOrigins();
  const self = selfOrigin(request);
  for (const header of [origin, referer]) {
    const base = originBase(header);
    if (base && (allow.includes(base) || (self && base === self))) return base;
  }
  return null;
}

/** Loopback, privado (RFC 1918), CGNAT, link-local e ULA: saltos internos de proxy, nunca o cliente. */
function ipInterno(ip: string): boolean {
  const v = ip.toLowerCase().replace(/^::ffff:/, '');
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(v)) return true;
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(v)) return true;
  if (/^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(v)) return true;
  return v === '::1' || v.startsWith('fc') || v.startsWith('fd') || v.startsWith('fe80:');
}

/**
 * IP do cliente para chave de rate limit.
 * PREMISSA (medida 01/10/2026): produção = Hostinger LiteSpeed SEM Cloudflare (Server: LiteSpeed,
 * platform: hostinger, sem cf-ray). Logo cf-connecting-ip é header do CLIENTE (forjável) e é ignorado.
 * X-Forwarded-For: o cliente pode mandar o header já preenchido; o proxy ACRESCENTA o IP de quem conectou
 * no fim. Por isso vale o salto mais à DIREITA que não seja interno (o primeiro é do cliente e mente).
 * Se um dia entrar CDN/Cloudflare na frente, esta função tem que mudar junto (o salto da direita vira a CDN).
 */
export function clientIp(request: Request): string {
  const h = request.headers;
  const saltos = (h.get('x-forwarded-for') || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  for (let i = saltos.length - 1; i >= 0; i--) {
    if (!ipInterno(saltos[i])) return saltos[i];
  }
  const real = (h.get('x-real-ip') || '').trim();
  if (real) return real;
  return saltos[saltos.length - 1] || 'unknown';
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
