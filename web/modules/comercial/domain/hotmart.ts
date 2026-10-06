// Regras puras ligadas à Hotmart (links de checkout, códigos de oferta).

/** Código de oferta a partir do que a pessoa colou: link com ?off=, link /checkout/X?off=, ou o próprio código. */
export function extrairCodigoOferta(texto: string): string | null {
  const t = texto.trim();
  if (!t) return null;
  const m = t.match(/[?&]off=([A-Za-z0-9_-]+)/);
  if (m) return m[1];
  if (/^[A-Za-z0-9_-]{4,40}$/.test(t)) return t;
  return null;
}

/** Link de checkout a partir do produto e da oferta. */
export function linkCheckout(produtoId: string, codigo: string): string {
  return `https://pay.hotmart.com/${produtoId}?off=${codigo}`;
}
