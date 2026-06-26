import type { NextRequest, NextResponse } from 'next/server';
import { isUuid } from './validation';

export const PLACA_SESSION_COOKIE = 'gp_placa_session';
const TTL_SECONDS = 2592000; // 30 dias

/** Token público da solicitação a partir de body/query/cookie (porta de api_get_public_session_token). */
export function resolvePlacaToken(
  request: NextRequest,
  body?: Record<string, unknown> | null,
  field = 'token',
): string {
  const candidates = [
    body && typeof body[field] === 'string' ? (body[field] as string) : '',
    request.nextUrl.searchParams.get(field) ?? '',
    request.cookies.get(PLACA_SESSION_COOKIE)?.value ?? '',
  ];
  for (const c of candidates) {
    const v = String(c).trim();
    if (v && isUuid(v)) return v.toLowerCase();
  }
  return '';
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
