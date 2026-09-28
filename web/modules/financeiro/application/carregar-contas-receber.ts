// Contas a Receber: UMA chamada a fn_fin_receber_semanal por cenário, quando a aba abre ou o cenário muda. A grade, o
// clique numa célula (quem compõe) e a lista de Recorrências saem todos desta mesma resposta — nenhum clique consulta
// de novo. O cache por cenário mora no pai (FinanceiroClient): voltar a um cenário já visto não consulta.
import type { FinanceiroRepository } from './ports';
import {
  agregarReceber, cobrancasRecorrentes, pagasPorContrato, periodoReceber, recebimentoDesligado,
  type CenarioReceber, type CobrancaRecorrente, type GradeReceber, type LinhaReceber, type PagamentoContrato,
} from '../domain/contas-receber';

export interface ContasReceberCarregado {
  linhas: LinhaReceber[];
  grade: GradeReceber;
  recorrencias: CobrancaRecorrente[];
  /** Bloco 2: transações pagas por contrato (ref), de qualquer linha que as traga — a composição lê daqui. */
  pagasPorRef: Map<string, PagamentoContrato[]>;
  /** Premissa de recebimento desligada no banco: sem data de caixa, a grade zerada não é dado. */
  desligado: boolean;
  /** Dia (São Paulo) em que a grade foi montada — início do período. */
  hojeISO: string;
  /** Cenário pedido. */
  cenario: CenarioReceber;
}

/** Hoje no fuso de São Paulo (YYYY-MM-DD). `new Date().toISOString()` viraria o dia às 21h. */
export function hojeSaoPaulo(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(agora);
}

export function montarContasReceber(linhas: LinhaReceber[], hojeISO: string, cenario: CenarioReceber = 'base'): ContasReceberCarregado {
  const { inicio, fim } = periodoReceber(linhas, hojeISO);
  return {
    linhas, grade: agregarReceber(linhas, inicio, fim), recorrencias: cobrancasRecorrentes(linhas),
    pagasPorRef: pagasPorContrato(linhas),
    desligado: recebimentoDesligado(linhas), hojeISO, cenario,
  };
}

export async function carregarContasReceber(
  repo: Pick<FinanceiroRepository, 'loadContasReceber'>, cenario: CenarioReceber = 'base', hojeISO: string = hojeSaoPaulo(),
): Promise<ContasReceberCarregado> {
  return montarContasReceber(await repo.loadContasReceber(cenario), hojeISO, cenario);
}
