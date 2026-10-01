/**
 * URL http(s) segura para usar em `href`: recusa `javascript:`, `data:` e, quando `allowedHosts` é
 * passado, qualquer host fora da lista (aceita subdomínio: `www.instagram.com` casa `instagram.com`).
 */
export function safeHttpUrl(v: unknown, allowedHosts: readonly string[] = []): string | null {
  const raw = String(v ?? '').replace(/[\r\n]+/g, '').trim();
  if (!raw) return null;
  try {
    const u = new URL(raw);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    if (allowedHosts.length) {
      const host = u.host.toLowerCase();
      const ok = allowedHosts.some((h) => host === h || host.endsWith('.' + h));
      if (!ok) return null;
    }
    return raw;
  } catch {
    return null;
  }
}

export const HOSTS_REDE = {
  facebook: ['facebook.com', 'fb.com'],
  instagram: ['instagram.com'],
  youtube: ['youtube.com', 'youtu.be'],
} as const;
