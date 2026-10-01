import type { NextRequest, NextResponse } from 'next/server';
import { isUuid } from './validation';

export const PLACA_SESSION_COOKIE = 'gp_placa_session';
const TTL_SECONDS = 7776000; // 90 dias — o processo de placa costuma atravessar semanas

export type PlacaTokenSource = 'body' | 'query' | 'cookie';

export interface ResolvedPlacaToken {
  /** Token escolhido (prioridade body > query > cookie), minúsculo; '' se nenhum UUID válido. */
  token: string;
  /** De onde veio o token escolhido; null quando token = ''. */
  source: PlacaTokenSource | null;
  /** UUID válido do cookie gp_placa_session ('' se ausente/ inválido) — permite cair para ele. */
  cookieToken: string;
}

function asUuid(v: unknown): string {
  const s = typeof v === 'string' ? v.trim() : '';
  return s && isUuid(s) ? s.toLowerCase() : '';
}

/** Igual a resolvePlacaToken, mas devolve a ORIGEM do token e o token do cookie. */
export function resolvePlacaTokenSource(
  request: NextRequest,
  body?: Record<string, unknown> | null,
  field = 'token',
): ResolvedPlacaToken {
  const cookieToken = asUuid(request.cookies.get(PLACA_SESSION_COOKIE)?.value);
  const candidates: Array<[PlacaTokenSource, string]> = [
    ['body', asUuid(body ? body[field] : '')],
    ['query', asUuid(request.nextUrl.searchParams.get(field))],
    ['cookie', cookieToken],
  ];
  for (const [source, token] of candidates) {
    if (token) return { token, source, cookieToken };
  }
  return { token: '', source: null, cookieToken };
}

/**
 * O token que falhou (404) era o do cookie? Só então o cookie deve ser apagado — um UUID
 * inexistente na URL/body não pode derrubar a sessão válida guardada no cookie.
 */
export function failedTokenIsCookie(r: ResolvedPlacaToken): boolean {
  return r.token !== '' && (r.source === 'cookie' || r.token === r.cookieToken);
}

/** Token público da solicitação a partir de body/query/cookie (porta de api_get_public_session_token). */
export function resolvePlacaToken(
  request: NextRequest,
  body?: Record<string, unknown> | null,
  field = 'token',
): string {
  return resolvePlacaTokenSource(request, body, field).token;
}

export function setPlacaCookie(res: NextResponse, token: string): NextResponse {
  if (!isUuid(token)) return res;
  res.cookies.set(PLACA_SESSION_COOKIE, token.toLowerCase(), {
    maxAge: TTL_SECONDS,
    path: '/',
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
  });
  return res;
}

export function clearPlacaCookie(res: NextResponse): NextResponse {
  res.cookies.set(PLACA_SESSION_COOKIE, '', { maxAge: 0, path: '/' });
  return res;
}
