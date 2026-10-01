// Valor de uma resposta do Respondi (`respondi.respostas.respostas[].v`) como texto de tela.
// No banco é sempre string, mas às vezes carrega JSON: lista (`'["T16"]'`) ou objeto (telefone
// `{"country":"55","phone":"…"}`, endereço). Lista vira "a, b"; objeto vira os valores em ordem.

export function textoResposta(v: unknown): string {
  if (v == null) return '';
  if (Array.isArray(v)) return v.map(textoResposta).filter(Boolean).join(', ');
  if (typeof v === 'object') return Object.values(v as Record<string, unknown>).map(textoResposta).filter(Boolean).join(' ');
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
