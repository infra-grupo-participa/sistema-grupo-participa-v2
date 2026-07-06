// Monta o link de acesso (definir senha) a partir do hashed_token do generateLink.
// Fluxo: generateLink → /auth/confirm (verifyOtp) → /definir-senha → /.

const APP_URL_FALLBACK = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';

/** Origin do deploy considerando proxy (Hostinger). Fallback p/ APP_URL. */
export function appOrigin(request: Request): string {
  const h = request.headers;
  const proto = (h.get('x-forwarded-proto') || '').split(',')[0].trim() || 'https';
  const host = (h.get('x-forwarded-host') || h.get('host') || '').split(',')[0].trim();
  return host ? `${proto}://${host}` : APP_URL_FALLBACK;
}

export type AccessLinkType = 'invite' | 'recovery';

/** URL /auth/confirm pronta para enviar à pessoa (cria senha e já entra). */
export function buildAccessLink(origin: string, hashedToken: string, type: AccessLinkType): string {
  const p = new URLSearchParams({ token_hash: hashedToken, type, next: '/definir-senha' });
  return `${origin}/auth/confirm?${p.toString()}`;
}
