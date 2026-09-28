// Sub-abas do Faturamento (#faturamento?ver=), no mesmo padrão de hash de #receber?ver= e #board?produto=: o `?` mora
// DENTRO do hash — ver FinanceiroClient.tsx. Funções puras, sem DOM.

export type SubAbaFaturamento = 'periodo' | 'caixa';

/** `ver=caixa` → Caixa Hotmart. Ausente ou desconhecido → Por período (o mesmo destino do link `#faturamento`). */
export function subAbaFaturamentoDoHash(query: string | undefined | null): SubAbaFaturamento {
  if (!query) return 'periodo';
  return new URLSearchParams(query).get('ver') === 'caixa' ? 'caixa' : 'periodo';
}

/** "Por período" usa o hash limpo `#faturamento` (o link do menu); Caixa Hotmart leva `?ver=caixa`. */
export function hashDaSubAbaFaturamento(sub: SubAbaFaturamento): string {
  return sub === 'periodo' ? '#faturamento' : `#faturamento?ver=${sub}`;
}
