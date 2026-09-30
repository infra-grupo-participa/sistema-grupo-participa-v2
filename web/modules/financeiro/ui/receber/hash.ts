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

/** Filtro de situação que cada sub-aba aceita pelo hash (`&situacao=`). O resto é ignorado (cai sem filtro). */
const FILTROS_POR_SUBABA: Partial<Record<SubAbaReceber, readonly string[]>> = {
  recorrencias: ['a_receber', 'realizada', 'em_atraso_fora', 'coberta_informado'],
  informados: ['em_atraso_cobrar', 'a_receber', 'realizado_hotmart', 'baixado_hotmart', 'baixado_fora', 'arquivado'],
  eventos: ['ativo', 'encerrado', 'arquivado'],
};

/** Lê `situacao` da query do hash, válida só para a sub-aba de `ver` (a Visão geral leva a lista já filtrada). */
export function filtroReceberDoHash(query: string | undefined | null): string | null {
  if (!query) return null;
  const sub = subAbaReceberDoHash(query);
  const s = new URLSearchParams(query).get('situacao');
  return s && FILTROS_POR_SUBABA[sub]?.includes(s) ? s : null;
}

/** Link para a sub-aba já filtrada (`#receber?ver=recorrencias&situacao=em_atraso_fora`). Sem filtro, ou filtro que a
 * sub-aba não aceita, = o hash da sub-aba. */
export function hashReceberFiltrado(sub: SubAbaReceber, situacao: string | null): string {
  const base = hashDaSubAbaReceber(sub);
  if (!situacao || !FILTROS_POR_SUBABA[sub]?.includes(situacao)) return base;
  return `${base}&situacao=${encodeURIComponent(situacao)}`;
}
