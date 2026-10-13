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

/**
 * Distância da meta em texto (Victor, 13/10/2026): "42% acima da meta", "20% abaixo da meta", "na meta".
 * Acima/abaixo é o lado numérico da meta, não bom ou ruim (CPL abaixo da meta é bom). Inteiro; abaixo de 1% usa uma casa
 * decimal para não escrever "0% abaixo" quando ainda não bateu a meta. Sem `pctDaMeta`: null.
 */
export function distanciaDaMeta(pctDaMeta: Valor): string | null {
  if (pctDaMeta === null || !Number.isFinite(pctDaMeta)) return null;
  const dif = (pctDaMeta - 1) * 100;
  const abs = Math.abs(dif);
  if (abs < 0.05) return 'na meta';
  const casas = abs < 1 ? 1 : 0;
  const n = abs.toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
  return `${n}% ${dif > 0 ? 'acima' : 'abaixo'} da meta`;
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
