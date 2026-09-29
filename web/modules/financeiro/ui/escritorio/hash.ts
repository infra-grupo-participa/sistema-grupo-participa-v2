// Sub-abas da aba Escritório (#escritorio?ver=), mesmo padrão de #faturamento?ver= (faturamento/hash.ts): o `?` mora
// DENTRO do hash — ver FinanceiroClient.tsx. Funções puras, sem DOM.
//
// 'contratos' (Contratos da Holding Familiar) é a 2ª sub-aba, feita por outra entrega. Enquanto não estiver em
// SUBABAS_ESCRITORIO_ATIVAS, o link `#escritorio?ver=contratos` cai no Funil (nunca numa sub-aba vazia).

export type SubAbaEscritorio = 'funil' | 'contratos';

/** Sub-abas com tela pronta, na ordem do tablist. Ligar Contratos = acrescentar aqui + o ramo no EscritorioAba. */
export const SUBABAS_ESCRITORIO_ATIVAS: readonly SubAbaEscritorio[] = ['funil'];

export const ROTULO_SUBABA_ESCRITORIO: Record<SubAbaEscritorio, string> = {
  funil: 'Funil',
  contratos: 'Contratos',
};

/** `ver=<sub>` ativa → essa sub-aba. Ausente, desconhecida ou ainda não ativa → Funil (o link `#escritorio`). */
export function subAbaEscritorioDoHash(query: string | undefined | null): SubAbaEscritorio {
  if (!query) return 'funil';
  const ver = new URLSearchParams(query).get('ver');
  return SUBABAS_ESCRITORIO_ATIVAS.find((s) => s === ver) ?? 'funil';
}

/** Funil usa o hash limpo `#escritorio` (o link do menu); as outras levam `?ver=<sub>`. */
export function hashDaSubAbaEscritorio(sub: SubAbaEscritorio): string {
  return sub === 'funil' ? '#escritorio' : `#escritorio?ver=${sub}`;
}
