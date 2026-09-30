// Sub-abas da aba Escritório (#escritorio?ver=), mesmo padrão de #faturamento?ver= (faturamento/hash.ts): o `?` mora
// DENTRO do hash — ver FinanceiroClient.tsx. Funções puras, sem DOM.
//
// 'contratos' (Contratos da Holding Familiar, z93) é a 2ª sub-aba. Ela depende da z93 no banco: o EscritorioAba só a mostra
// depois que a sonda confirma as RPCs (application/carregar-contratos-hf.ts). Sem a z93, o link `#escritorio?ver=contratos`
// cai no Funil (nunca numa sub-aba vazia). Desligar de vez = tirar 'contratos' de SUBABAS_ESCRITORIO_ATIVAS.

export type SubAbaEscritorio = 'funil' | 'contratos';

/** Sub-abas com tela pronta, na ordem do tablist. Ligar Contratos = acrescentar aqui + o ramo no EscritorioAba. */
export const SUBABAS_ESCRITORIO_ATIVAS: readonly SubAbaEscritorio[] = ['funil', 'contratos'];

export const ROTULO_SUBABA_ESCRITORIO: Record<SubAbaEscritorio, string> = {
  funil: 'Funil',
  contratos: 'Contratos',
};

/** `ver=<sub>` ativa → essa sub-aba. Ausente, desconhecida ou fora das ativas → Funil (o link `#escritorio`). */
export function subAbaEscritorioDoHash(query: string | undefined | null): SubAbaEscritorio {
  if (!query) return 'funil';
  const ver = new URLSearchParams(query).get('ver');
  return SUBABAS_ESCRITORIO_ATIVAS.find((s) => s === ver) ?? 'funil';
}

/** Funil usa o hash limpo `#escritorio` (o link do menu); as outras levam `?ver=<sub>`. */
export function hashDaSubAbaEscritorio(sub: SubAbaEscritorio): string {
  return sub === 'funil' ? '#escritorio' : `#escritorio?ver=${sub}`;
}
