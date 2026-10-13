import type { Valor } from './tipos';

// Bom, atenção ou ruim contra a meta de um card (Victor, 13/10/2026).
//   quanto MAIOR melhor (taxas, CTR): bom quando valor >= meta;
//   quanto MENOR melhor (CPL, CPC, CPM): bom quando valor <= meta.
// Atenção (amarelo): do lado errado da meta, mas por pouco, dentro da tolerância (10% da meta, escolha provisória).
// Além disso, ruim. `pctDaMeta` é valor ÷ meta (1 = na meta). Sem valor, sem meta ou meta <= 0: 'sem' (nunca chuta).

export type EstadoMeta = 'bom' | 'atencao' | 'ruim' | 'sem';
export interface AvaliacaoMeta { estado: EstadoMeta; pctDaMeta: Valor }

/** Folga, em fração da meta, em que o resultado ainda é só atenção. */
export const TOLERANCIA_META = 0.1;

/**
 * Faixa de duas linhas para métrica de quanto menor, melhor (CPL, Victor 13/10/2026): até o ideal é bom; entre o ideal e
 * o limite é atenção; acima do limite é ruim. `pctDaMeta` é valor ÷ limite.
 */
export function avaliarFaixa(valor: Valor, ideal: Valor, limite: Valor): AvaliacaoMeta {
  if (valor === null || ideal === null || limite === null || ![valor, ideal, limite].every(Number.isFinite) || ideal <= 0 || limite < ideal) {
    return { estado: 'sem', pctDaMeta: null };
  }
  const estado: EstadoMeta = valor <= ideal + 1e-9 ? 'bom' : valor <= limite + 1e-9 ? 'atencao' : 'ruim';
  return { estado, pctDaMeta: valor / limite };
}

export function avaliarMeta(valor: Valor, meta: Valor, menorMelhor: boolean, tolerancia = TOLERANCIA_META): AvaliacaoMeta {
  if (valor === null || meta === null || !Number.isFinite(valor) || !Number.isFinite(meta) || meta <= 0) {
    return { estado: 'sem', pctDaMeta: null };
  }
  const pctDaMeta = valor / meta;
  const razao = menorMelhor ? pctDaMeta - 1 : 1 - pctDaMeta; // quanto está do lado errado da meta (<= 0: cumpriu)
  const estado: EstadoMeta = razao <= 1e-9 ? 'bom' : razao <= tolerancia + 1e-9 ? 'atencao' : 'ruim';
  return { estado, pctDaMeta };
}
