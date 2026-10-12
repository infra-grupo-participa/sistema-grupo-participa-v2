// Paginação de cartões (campanhas e conjuntos, 12/10): no máximo `porPagina` por página e a régua de números
// estilo Google ("‹ 1 2 3 4 5 ›"), com a página atual no meio da janela sempre que der.

export const POR_PAGINA = 10;

export interface Pagina<T> { itens: T[]; pagina: number; paginas: number; total: number }

/** Recorta a página pedida. Página fora do intervalo vira a mais próxima válida (nunca uma página vazia). */
export function paginar<T>(itens: readonly T[], pagina: number, porPagina = POR_PAGINA): Pagina<T> {
  const tamanho = Math.max(1, Math.floor(porPagina));
  const paginas = Math.max(1, Math.ceil(itens.length / tamanho));
  const atual = Math.min(paginas, Math.max(1, Math.floor(Number.isFinite(pagina) ? pagina : 1)));
  const inicio = (atual - 1) * tamanho;
  return { itens: itens.slice(inicio, inicio + tamanho), pagina: atual, paginas, total: itens.length };
}

/** Números visíveis na régua: janela de até `largura` páginas, a atual centralizada quando possível. */
export function paginasVisiveis(atual: number, paginas: number, largura = 5): number[] {
  const n = Math.max(1, paginas); const l = Math.max(1, Math.min(largura, n));
  const a = Math.min(n, Math.max(1, atual));
  const inicio = Math.min(Math.max(1, a - Math.floor(l / 2)), n - l + 1);
  return Array.from({ length: l }, (_, i) => inicio + i);
}
