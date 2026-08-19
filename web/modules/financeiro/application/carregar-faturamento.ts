// Caso de uso: faturamento diário (regime de caixa). fn_fin_faturamento_diario
// inalterada — só reescrito sobre o caso de uso, mesmo contrato de antes.
import { comAcumulado, resumirFaturamento, type DiaComAcumulado, type ResumoFaturamento } from '../domain/financeiro';
import type { FinanceiroRepository } from './ports';

export interface FaturamentoCarregado {
  dias: DiaComAcumulado[];
  resumo: ResumoFaturamento;
}

export async function carregarFaturamento(
  repo: FinanceiroRepository,
  turma: string | null,
  hojeISO: string,
): Promise<FaturamentoCarregado> {
  const brutos = await repo.loadFaturamento(turma);
  return { dias: comAcumulado(brutos), resumo: resumirFaturamento(brutos, hojeISO) };
}
