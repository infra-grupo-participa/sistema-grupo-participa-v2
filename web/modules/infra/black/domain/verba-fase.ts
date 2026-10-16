import type { Valor } from './tipos';

// Verba (limite) de uma fase contra o que já foi gasto nela. Conta pura, usada pela aba "Por fase" do modal de investimento.
// O limite vem de ConfigBlack.previstoPorFase (concepção do Caio, 12/10/2026). Limite ausente = "sem limite cadastrado",
// gasto ausente = "sem dado": nenhum dos dois vira 0. Investimento contra a verba não é bom nem ruim (Victor, 15/10/2026):
// aqui não há farol, só distância.

export type SituacaoVerba = 'sem_limite' | 'sem_dado' | 'dentro' | 'no_limite' | 'estourou';

export interface VerbaDaFase {
  situacao: SituacaoVerba;
  limite: number | null;
  gasto: number | null;
  /** gasto ÷ limite (1 = no limite). Soma sobre soma: os dois são do mesmo recorte. null sem os dois. */
  pctDoLimite: number | null;
  /** limite − gasto: positivo = falta gastar, negativo = passou do limite. null sem os dois. */
  saldo: number | null;
  /** Fração (0 a 1) da trilha preenchida pelo gasto. 0 sem dado. */
  preenchimento: number;
  /** Fração (0 a 1) da trilha onde fica o marco do limite. null sem limite. */
  marcador: number | null;
}

/** A trilha vai até o maior entre limite e gasto, mais esta folga, para o marco nunca ficar colado na ponta. */
export const FOLGA_DA_TRILHA = 1.15;
const TOLERANCIA_CENTAVO = 0.005;

const valido = (v: Valor | undefined): v is number => v !== null && v !== undefined && Number.isFinite(v);

export function verbaDaFase(gasto: Valor, limite: Valor | undefined): VerbaDaFase {
  const temLimite = valido(limite) && limite > 0;
  const temGasto = valido(gasto) && gasto >= 0;
  const lim = temLimite ? (limite as number) : null;
  const gas = temGasto ? (gasto as number) : null;
  if (lim === null) {
    return { situacao: 'sem_limite', limite: null, gasto: gas, pctDoLimite: null, saldo: null, preenchimento: 0, marcador: null };
  }
  const trilha = Math.max(lim, gas ?? 0) * FOLGA_DA_TRILHA;
  const marcador = lim / trilha;
  if (gas === null) {
    return { situacao: 'sem_dado', limite: lim, gasto: null, pctDoLimite: null, saldo: null, preenchimento: 0, marcador };
  }
  const saldo = lim - gas;
  const situacao: SituacaoVerba = Math.abs(saldo) < TOLERANCIA_CENTAVO ? 'no_limite' : saldo > 0 ? 'dentro' : 'estourou';
  return { situacao, limite: lim, gasto: gas, pctDoLimite: gas / lim, saldo, preenchimento: gas / trilha, marcador };
}
