// Contas a Receber (fase 1): UMA chamada a fn_fin_receber_semanal quando a aba abre. A grade, o clique numa célula
// (quem compõe) e a lista de Recorrências saem todos desta mesma resposta — nenhum clique consulta de novo.
import type { FinanceiroRepository } from './ports';
import {
  agregarReceber, cobrancasRecorrentes, periodoReceber, recebimentoDesligado,
  type CobrancaRecorrente, type GradeReceber, type LinhaReceber,
} from '../domain/contas-receber';

export interface ContasReceberCarregado {
  linhas: LinhaReceber[];
  grade: GradeReceber;
  recorrencias: CobrancaRecorrente[];
  /** Premissa de recebimento desligada no banco: sem data de caixa, a grade zerada não é dado. */
  desligado: boolean;
  /** Dia (São Paulo) em que a grade foi montada — início do período. */
  hojeISO: string;
}

/** Hoje no fuso de São Paulo (YYYY-MM-DD). `new Date().toISOString()` viraria o dia às 21h. */
export function hojeSaoPaulo(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(agora);
}

export function montarContasReceber(linhas: LinhaReceber[], hojeISO: string): ContasReceberCarregado {
  const { inicio, fim } = periodoReceber(linhas, hojeISO);
  return {
    linhas, grade: agregarReceber(linhas, inicio, fim), recorrencias: cobrancasRecorrentes(linhas),
    desligado: recebimentoDesligado(linhas), hojeISO,
  };
}

export async function carregarContasReceber(
  repo: Pick<FinanceiroRepository, 'loadContasReceber'>, hojeISO: string = hojeSaoPaulo(),
): Promise<ContasReceberCarregado> {
  return montarContasReceber(await repo.loadContasReceber(), hojeISO);
}
