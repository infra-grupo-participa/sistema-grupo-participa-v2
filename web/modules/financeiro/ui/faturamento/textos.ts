// Textos da aba Faturamento (sub-abas Por período e Caixa Hotmart). Moram aqui, fora dos componentes, no mesmo
// padrão de ui/receber/textos.ts. Nenhum percentual de antecipação ou retenção é escrito aqui: os valores vêm do
// banco (fin.premissas_recebimento). A única data fixa é o marco da antecipação, recebido por parâmetro.

/** Sub-abas de #faturamento, nesta ordem. */
export const SUBABAS_FATURAMENTO = {
  rotuloGrupo: 'Faturamento',
  periodo: 'Por período',
  caixa: 'Caixa Hotmart',
} as const;

/** As três linhas do líquido realista (decisão de tela de 28/09), na tabela de Por período. */
export const LINHAS_RECEBIMENTO = {
  entraRapido: 'Entra em 2 dias úteis',
  retido: 'Retido, volta em 30 dias',
  liquidoTotal: 'Líquido total',
  ajudaEntraRapido: 'Líquido menos o retido e o custo da antecipação. Cai no 2º dia útil depois da aprovação.',
  ajudaRetido: 'Parte retida pela Hotmart. Volta no 1º dia útil a partir de 30 dias da aprovação.',
  ajudaLiquidoTotal: 'Entra em 2 dias úteis + retido, se não houver reembolso.',
} as const;

/** Aviso do marco: antes dele não havia antecipação. `marco` já formatado (dd/mm/aaaa). */
export function avisoSemAntecipacao(marco: string): string {
  return `Antes de ${marco} não havia antecipação: o líquido dessas vendas fica inteiro retido e cai no 1º dia útil a partir de 30 dias da aprovação, sem custo de antecipação.`;
}

export const CAIXA_HOTMART = {
  escopo: 'Todas as famílias da conta Hotmart da Academy. Só vendas pagas, pelo dia da aprovação. Situação comparada com hoje.',
  periodo: 'Período',
  desdeAntecipacao: (marco: string) => `Desde ${marco}`,
  dias30: '30 dias',
  meses12: '12 meses',
  de: 'Data inicial',
  ate: 'Data final',
  ou: 'ou de',
  ateCurto: 'até',
  erroDatas: 'Informe as duas datas.',
  erroInvertido: 'A data final está antes da inicial.',
  erroJanela: (max: number) => `O período vai até ${max} dias. Encurte o intervalo.`,
  carregando: 'Carregando o caixa da Hotmart…',
  tentarDeNovo: 'Tentar de novo',
  vazio: 'Nenhuma venda paga no período.',
  // Totais (uma faixa só, sem card herói)
  totaisRotulo: 'Totais do período',
  liquido: 'Líquido',
  jaCaiuD2: 'Já caiu em D+2',
  custoAntecipacao: 'Custo da antecipação',
  retidoALiberar: 'Retido a liberar',
  liquidoTotal: 'Líquido total',
  vendas: (n: number) => `${n.toLocaleString('pt-BR')} ${n === 1 ? 'venda' : 'vendas'}`,
  aCair: (v: string) => `mais ${v} a cair`,
  jaLiberado: (v: string) => `${v} já liberado`,
  semRetidoAberto: 'nada retido em aberto',
  somaDasPartes: 'D+2 + retido',
  // Tabela por dia
  tabelaTitulo: 'Dia a dia',
  tabelaRotulo: 'Caixa Hotmart por dia de aprovação',
  dia: 'Dia',
  nVendas: 'Vendas',
  entraD2: 'Entra em D+2',
  dataD2: 'Cai em',
  situacaoD2: 'Situação D+2',
  retido: 'Retido',
  liberaEm: 'Volta em',
  situacaoRetido: 'Situação do retido',
  semAntecipacao: 'sem antecipação',
  semPremissa: 'sem regra de recebimento',
  situacao: {
    recebido: 'Recebido',
    a_receber: 'A receber',
    liberado: 'Liberado',
    em_garantia: 'A liberar',
  },
} as const;
