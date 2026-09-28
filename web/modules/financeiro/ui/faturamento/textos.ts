// Textos da aba Faturamento (sub-abas Por período, Caixa Hotmart e Taxa Hotmart). Moram aqui, fora dos componentes, no mesmo
// padrão de ui/receber/textos.ts. Nenhum percentual de antecipação ou retenção é escrito aqui: os valores vêm do
// banco (fin.premissas_recebimento). A única data fixa é o marco da antecipação, recebido por parâmetro.

/** Sub-abas de #faturamento, nesta ordem. */
export const SUBABAS_FATURAMENTO = {
  rotuloGrupo: 'Faturamento',
  periodo: 'Por período',
  caixa: 'Caixa Hotmart',
  taxa: 'Taxa Hotmart',
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

const n = (v: number) => v.toLocaleString('pt-BR');
const vendas = (v: number) => `${n(v)} ${v === 1 ? 'venda' : 'vendas'}`;

/** Taxa Hotmart (F7, z70). Nenhum percentual de acordo mora aqui: o texto do acordo vem do banco (grupo_acordo). */
export const TAXA_HOTMART = {
  pergunta: 'A Hotmart está cobrando o que combinou?',
  escopo: 'Todas as vendas pagas da conta Hotmart da Academy, pelo dia da aprovação. Venda com oferta abaixo de R$ 100 fica fora (ruído). Divergente = taxa cobrada difere do acordo do produto em mais de R$ 10.',
  periodo: 'Período',
  anoCorrente: (ano: string) => `Ano de ${ano}`,
  meses12: '12 meses',
  de: 'Data inicial',
  ate: 'Data final',
  ou: 'ou de',
  ateCurto: 'até',
  erroDatas: 'Informe as duas datas.',
  erroInvertido: 'A data final está antes da inicial.',
  erroJanela: (max: number) => `O período vai até ${max} dias. Encurte o intervalo.`,
  carregando: 'Carregando a auditoria da taxa Hotmart…',
  tentarDeNovo: 'Tentar de novo',
  // Resumo do topo (uma frase, sem card)
  resumoRotulo: 'Resumo do período',
  semVendas: 'Nenhuma venda à vista com oferta a partir de R$ 100 no período.',
  vendasAVista: (v: number) => `${vendas(v)} à vista`,
  tudoCerto: 'A Hotmart cobrou o combinado em todas as vendas do período.',
  divergentes: (d: number, impacto: string, aMais: boolean) =>
    `${n(d)} ${d === 1 ? 'divergente' : 'divergentes'}, impacto ${impacto} ${aMais ? 'cobrado a mais' : 'cobrado a menos'}.`,
  semTaxa: (v: number) => `${vendas(v)} ${v === 1 ? 'veio' : 'vieram'} sem a taxa informada pela Hotmart e ficaram fora da conta.`,
  semAcordo: (p: number) => `${n(p)} ${p === 1 ? 'produto não tem' : 'produtos não têm'} acordo específico e ${p === 1 ? 'cai' : 'caem'} no acordo padrão.`,
  // Tabela por produto
  produtosTitulo: 'À vista, por produto',
  produtosRotulo: 'Taxa Hotmart à vista por produto: real × acordo',
  produto: 'Produto',
  acordo: 'Acordo',
  semAcordoEspecifico: 'sem acordo específico',
  nVendas: 'Vendas',
  oferta: 'Oferta',
  taxaReal: 'Taxa cobrada',
  taxaEsperada: 'Taxa do acordo',
  nDivergentes: 'Divergentes',
  impacto: 'Impacto',
  ajudaImpacto: 'Soma de (cobrado − acordo) só das vendas divergentes. Positivo = a Hotmart cobrou a mais.',
  semTaxaNota: (v: number) => `+ ${n(v)} sem taxa`,
  // Parcelado (informativo)
  parceladoTitulo: 'Parcelado: quanto o cliente paga a mais por nº de parcelas',
  parceladoExplica: 'O juro do parcelamento é pago pelo cliente. A empresa recebe o mesmo líquido da venda à vista, então o parcelado não entra na auditoria acima. A tabela é só informativa: (valor cobrado do cliente − líquido da empresa) ÷ oferta.',
  parceladoRotulo: 'Quanto o cliente paga a mais por número de parcelas',
  parcelas: 'Parcelas',
  parcela: (p: number) => (p === 1 ? '1× (referência)' : `${p}×`),
  clientePaga: 'Cobrado − líquido, sobre a oferta',
  aMaisQue1x: 'A mais que 1×',
  pontos: (v: string) => `+${v} p.p.`,
  // Divergências
  divergenciasTitulo: 'Vendas divergentes',
  divergenciasRotulo: 'Vendas à vista com taxa diferente do acordo, maior diferença primeiro',
  limite: (mostradas: number, total: number) => `Mostrando as ${n(mostradas)} maiores diferenças de ${n(total)} divergentes.`,
  transacao: 'Transação',
  dia: 'Dia',
  diferenca: 'Diferença',
  exportar: 'Exportar CSV',
  exportarAjuda: 'Transação, dia, produto e valores. Sem nome, e-mail ou documento.',
} as const;
