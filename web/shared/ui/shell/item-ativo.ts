// Qual item hash-nav da sidebar está ativo — função pura (testável sem navegador).
// Regras:
// - O item padrão (URL sem hash) é o do `defaultHref` do grupo, não "o primeiro filho com hash": o Financeiro abre no
//   #board e o 1º filho é "Previsão de caixa" (#receber) — destacar o 1º mostrava a página errada como ativa.
// - O hash é comparado SEM a parte depois do `?` (#board?produto=HM, #receber?ver=premissas): a sub-aba ou o filtro
//   não trocam o item do menu.
import type { NavChild } from '../nav/config';

/** '#receber?ver=premissas' → '#receber'. */
export const hashBase = (h: string): string => (h || '').split('?')[0];

/** Chave do filho que representa a URL sem hash: o do hash do defaultHref; sem ele, o 1º filho com hash. */
export function chaveHashPadrao(defaultHref: string, children: Pick<NavChild, 'key' | 'hash'>[]): string | undefined {
  const i = defaultHref.indexOf('#');
  const alvo = i >= 0 ? hashBase(defaultHref.slice(i)) : '';
  return (alvo && children.find((c) => c.hash && hashBase(c.hash) === alvo)?.key) || children.find((c) => c.hash)?.key;
}

/** O filho hash-nav está ativo? `noCaminho` = a rota atual é a do filho. */
export function itemHashAtivo(
  child: Pick<NavChild, 'key' | 'hash'>, hashAtual: string, noCaminho: boolean, chavePadrao: string | undefined,
): boolean {
  if (!noCaminho || !child.hash) return false;
  const atual = hashBase(hashAtual);
  return atual ? atual === hashBase(child.hash) : child.key === chavePadrao;
}
