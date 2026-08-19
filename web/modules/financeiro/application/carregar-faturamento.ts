// Caso de uso: faturamento diário (regime de caixa). fn_fin_faturamento_diario
// inalterada — só reescrito sobre o caso de uso, mesmo contrato de antes.
// `dias` agora vem com lacunas preenchidas (dia sem lançamento = zero
// explícito, não some da série) + variação dia-a-dia + média móvel 7d —
// ver comMetricas() para a decisão de como tratar dias ausentes.
import { comMetricas, resumirFaturamento, type DiaComMetricas, type ResumoFaturamento } from '../domain/financeiro';
import type { FinanceiroRepository } from './ports';

export interface FaturamentoCarregado {
  dias: DiaComMetricas[];
  resumo: ResumoFaturamento;
}

export async function carregarFaturamento(
  repo: FinanceiroRepository,
  turma: string | null,
  hojeISO: string,
): Promise<FaturamentoCarregado> {
  const brutos = await repo.loadFaturamento(turma);
  // resumirFaturamento usa os dias BRUTOS (só os que têm lançamento) — "dias
  // com lançamento" e "média por dia com lançamento" são leituras distintas
  // da média móvel de 7 dias corridos usada na tabela.
  return { dias: comMetricas(brutos), resumo: resumirFaturamento(brutos, hojeISO) };
}
