// Sub-abas do Faturamento (#faturamento?ver=), no mesmo padrão de hash de #receber?ver= e #board?produto=: o `?` mora
// DENTRO do hash — ver FinanceiroClient.tsx. Funções puras, sem DOM.

export type SubAbaFaturamento = 'periodo' | 'caixa' | 'taxa';

/** `ver=caixa` → Caixa Hotmart; `ver=taxa` → Taxa Hotmart. Ausente ou desconhecido → Por período (o link `#faturamento`). */
export function subAbaFaturamentoDoHash(query: string | undefined | null): SubAbaFaturamento {
  if (!query) return 'periodo';
  const ver = new URLSearchParams(query).get('ver');
  return ver === 'caixa' || ver === 'taxa' ? ver : 'periodo';
}

/** "Por período" usa o hash limpo `#faturamento` (o link do menu); as outras levam `?ver=<sub>`. */
export function hashDaSubAbaFaturamento(sub: SubAbaFaturamento): string {
  return sub === 'periodo' ? '#faturamento' : `#faturamento?ver=${sub}`;
}
