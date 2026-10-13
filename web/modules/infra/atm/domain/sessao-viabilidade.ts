export type MetricaSessaoViabilidade = { valor: number; semDado: boolean };

/** Vendas ÷ pré-checkouts únicos por e-mail. Sem qualquer fonte ausente, preserva Sem dado. */
export function conversaoSessaoViabilidade(vendas: MetricaSessaoViabilidade, preCheckoutsUnicos: number | null): MetricaSessaoViabilidade {
  if (vendas.semDado || preCheckoutsUnicos === null || preCheckoutsUnicos <= 0) return { valor: 0, semDado: true };
  return { valor: vendas.valor / preCheckoutsUnicos * 100, semDado: false };
}
