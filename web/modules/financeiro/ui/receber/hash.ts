// Sub-abas da tela "Previsão de caixa" (#receber), lidas do mesmo padrão de hash que #board?produto= usa: o `?`
// mora DENTRO do hash, não é querystring de verdade — ver FinanceiroClient.tsx. Funções puras, sem DOM, para
// poderem ser testadas sem navegador.

export type SubAbaReceber = 'semana' | 'recorrencias' | 'informados' | 'eventos' | 'premissas' | 'base';

/** Lê `ver` da parte depois do `?` do hash (`#receber?ver=recorrencias` → passar só `ver=recorrencias`). Valor
 * ausente ou desconhecido cai na grade (Semana a semana) — o mesmo destino do link `#receber` sem query. */
export function subAbaReceberDoHash(query: string | undefined | null): SubAbaReceber {
  if (!query) return 'semana';
  const ver = new URLSearchParams(query).get('ver');
  if (ver === 'recorrencias' || ver === 'informados' || ver === 'eventos' || ver === 'premissas' || ver === 'base') return ver;
  return 'semana';
}

/** Hash a escrever quando a sub-aba muda. "Semana a semana" usa o hash limpo `#receber` — é o mesmo link do item do
 * menu, sem `?ver=` — as outras levam o parâmetro. */
export function hashDaSubAbaReceber(sub: SubAbaReceber): string {
  return sub === 'semana' ? '#receber' : `#receber?ver=${sub}`;
}
