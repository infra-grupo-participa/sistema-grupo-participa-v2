import type { Valor } from './tipos';

// Bom, atenção ou ruim contra a meta de um card (Victor, 13/10/2026).
//   quanto MAIOR melhor (taxas, CTR): bom quando valor >= meta;
//   quanto MENOR melhor (CPL, CPC, CPM): bom quando valor <= meta.
// Atenção (amarelo): do lado errado da meta, mas por pouco, dentro da tolerância (10% da meta, escolha provisória).
// Além disso, ruim. `pctDaMeta` é valor ÷ meta (1 = na meta). Sem valor, sem meta ou meta <= 0: 'sem' (nunca chuta).

export type EstadoMeta = 'bom' | 'atencao' | 'ruim' | 'sem';
export interface AvaliacaoMeta { estado: EstadoMeta; pctDaMeta: Valor; distancia: string | null }

/** Folga, em fração da meta, em que o resultado ainda é só atenção. */
export const TOLERANCIA_META = 0.1;

/**
 * Compara valor e meta uma única vez para definir o farol e o rótulo de distância.
 * Com `ideal`, preserva a faixa do CPL: até o ideal é bom, entre ideal e meta é atenção e acima da meta é ruim.
 * `distancia` sempre compara valor/meta e nunca é truncada.
 */
export function compararMeta(valor: Valor, meta: Valor, menorMelhor = false, ideal: Valor = null, tolerancia = TOLERANCIA_META): AvaliacaoMeta {
  if (valor === null || meta === null || !Number.isFinite(valor) || !Number.isFinite(meta) || meta <= 0
    || (ideal !== null && (!Number.isFinite(ideal) || ideal <= 0 || meta < ideal))) {
    return { estado: 'sem', pctDaMeta: null, distancia: null };
  }
  const pctDaMeta = valor / meta;
  const estado: EstadoMeta = ideal !== null
    ? valor <= ideal + 1e-9 ? 'bom' : valor <= meta + 1e-9 ? 'atencao' : 'ruim'
    : (menorMelhor ? pctDaMeta - 1 : 1 - pctDaMeta) <= 1e-9 ? 'bom'
      : (menorMelhor ? pctDaMeta - 1 : 1 - pctDaMeta) <= tolerancia + 1e-9 ? 'atencao' : 'ruim';
  const dif = (pctDaMeta - 1) * 100;
  const abs = Math.abs(dif);
  const casas = abs < 1 ? 1 : 0;
  const n = abs.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
  const distancia = abs < 0.05 ? 'na meta' : `${n}% ${dif > 0 ? 'acima' : 'abaixo'} da meta`;
  return { estado, pctDaMeta, distancia };
}
