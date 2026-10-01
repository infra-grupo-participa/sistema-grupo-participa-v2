// Valor de uma resposta do Respondi (`respondi.respostas.respostas[].v` e `dados.*`) como texto de
// tela. No banco é sempre string, mas às vezes carrega JSON: lista (`'["T16"]'`), telefone
// `{"country":"55","phone":"…"}`, moeda `{"currency":"BRL","value":N}` ou endereço. Lista vira
// "a, b"; telefone e moeda saem formatados; outro objeto vira os valores em ordem.

type Obj = Record<string, unknown>;

/** `{country, phone}` → "+55 (62) 99999-0000"; fora do Brasil, "+<país> <número>". */
export function formatarTelefone(country: unknown, phone: unknown): string {
  const c = String(country ?? '').replace(/\D/g, '');
  const p = String(phone ?? '').replace(/\D/g, '');
  if (!p) return '';
  if (c === '55' && (p.length === 10 || p.length === 11)) {
    const n = p.slice(2);
    return `+55 (${p.slice(0, 2)}) ${n.slice(0, n.length - 4)}-${n.slice(-4)}`;
  }
  return c ? `+${c} ${p}` : p;
}

/** `{currency, value}` → "R$ 150.000,00" (outra moeda: código + valor). */
export function formatarMoeda(currency: unknown, value: unknown): string {
  const v = typeof value === 'number' ? value : Number(String(value ?? '').replace(',', '.'));
  if (!Number.isFinite(v)) return '';
  const cur = String(currency ?? '').trim().toUpperCase() || 'BRL';
  try {
    return v.toLocaleString('pt-BR', { style: 'currency', currency: cur });
  } catch {
    return `${cur} ${v.toLocaleString('pt-BR')}`;
  }
}

export function textoResposta(v: unknown): string {
  if (v == null) return '';
  if (Array.isArray(v)) return v.map(textoResposta).filter(Boolean).join(', ');
  if (typeof v === 'object') {
    const o = v as Obj;
    if ('phone' in o) return formatarTelefone(o.country, o.phone);
    if ('currency' in o && 'value' in o) return formatarMoeda(o.currency, o.value);
    return Object.values(o).map(textoResposta).filter(Boolean).join(' ');
  }
  const s = String(v).trim();
  if ((s.startsWith('[') && s.endsWith(']')) || (s.startsWith('{') && s.endsWith('}'))) {
    try { return textoResposta(JSON.parse(s)); } catch { /* texto cru */ }
  }
  return s;
}

/** Pares pergunta → valor prontos para a tela (sem pergunta ou valor vazio somem). */
export function itensResposta(respostas: { p?: string | null; v?: unknown }[] | null | undefined): { q: string; v: string }[] {
  return (respostas ?? [])
    .map((r) => ({ q: String(r.p ?? '').trim(), v: textoResposta(r.v) }))
    .filter((r) => r.q && r.v);
}
