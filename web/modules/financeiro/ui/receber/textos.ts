// Textos da aba "Contas a Receber" — moram aqui, fora dos componentes, para
// tela e (se um dia existir) PDF lerem a MESMA fonte, mesmo padrão de
// ui/hotmart/rotulos.ts.
//
// Regra de premissa (não inventar número): os percentuais e prazos de
// antecipação/garantia vêm de uma tabela de premissas no banco, não são fixos
// aqui. Por isso as frases de explicação são FUNÇÕES que recebem os valores
// já calculados — o único texto com "3,89" nesta tela é o gerado por
// explicacaoAntecipacao, nunca um literal solto em outro rótulo.

/** Título e subtítulo da aba, no topo do Financeiro. */
export const CABECALHO_RECEBER = {
  titulo: 'Contas a Receber',
  subtitulo: 'Quanto dinheiro entra no caixa, semana a semana.',
} as const;

/** Legenda de escopo — fixa acima dos blocos, para não confundir com projeção de vendas novas. */
export const ESCOPO_RECEBER = {
  legenda: 'Só dinheiro já vendido ou contratado. Projeção de vendas novas e eventos entra em outra etapa.',
} as const;

/** Nomes dos dois blocos da tela. */
export const BLOCOS_RECEBER = {
  vendasRealizadas: 'Vendas já realizadas',
  assinaturasEParcelasFuturas: 'Assinaturas e parcelas futuras',
} as const;

/** Nomes dos grupos dentro do bloco 2 (recorrências e parcelas a vencer). */
export const GRUPOS_RECEBER = {
  assinaturasServicoDiamante: 'Assinaturas Serviço Diamante',
  assinaturasHoldingMasters: 'Assinaturas Holding - Holding Masters',
  parcelasAVencerHM: 'Parcelas a vencer HM',
  parcelasAVencerAurum: 'Parcelas a vencer Aurum',
  parcelasAVencerOutros: 'Parcelas a vencer outros',
  outrasAssinaturas: 'Outras assinaturas',
} as const;

/** Nome da seção que lista as cobranças futuras dentro de cada grupo (nunca "Carteira"). */
export const SECAO_RECORRENCIAS = {
  titulo: 'Recorrências',
} as const;

/** Componentes do bloco 1 (vendas já realizadas): a divisão antecipação/garantia. */
export const COMPONENTES_VENDA = {
  antecipacao: 'Antecipação (D+2)',
  garantia: 'Garantia (D+30)',
} as const;

/**
 * Explicação da antecipação: percentual do líquido, taxa descontada e prazo em
 * dias úteis — todos vindos da tabela de premissas, nunca fixos no texto.
 * @param percentualLiquido ex.: 90 (representa 90%)
 * @param taxaPercentual ex.: 3.89 (representa 3,89%)
 * @param diasUteis ex.: 2
 */
export function explicacaoAntecipacao(percentualLiquido: number, taxaPercentual: number, diasUteis: number): string {
  const pct = formatarPercentual(percentualLiquido);
  const taxa = formatarPercentual(taxaPercentual);
  return `${pct} do valor líquido, menos ${taxa} de taxa, cai no caixa em ${diasUteis} dias úteis após a aprovação da venda.`;
}

/**
 * Explicação da garantia: percentual retido e prazo de liberação — também vindos
 * da tabela de premissas.
 * @param percentualRetido ex.: 10 (representa 10%)
 * @param diasCorridos ex.: 30
 */
export function explicacaoGarantia(percentualRetido: number, diasCorridos: number): string {
  const pct = formatarPercentual(percentualRetido);
  return `${pct} do valor fica retido e é liberado no 1º dia útil a partir de ${diasCorridos} dias, considerando feriados bancários.`;
}

function formatarPercentual(valor: number): string {
  return `${valor.toString().replace('.', ',')}%`;
}

/** Situações do bloco 2 — nunca "devendo". */
export const SITUACAO_RECEBER = {
  aReceber: 'A receber',
  realizada: 'Realizada',
  foraDaProjecao: 'Fora da projeção (atraso acima da tolerância)',
} as const;

/** Rótulos dos totais, usados nos dois blocos. */
export const ROTULOS_TOTAL = {
  totalDaSemana: 'Total da semana',
  totalDoMes: 'Total do mês',
  acumulado: 'Acumulado',
} as const;

/** Estado vazio e erro de carregamento. */
export const ESTADOS_RECEBER = {
  vazio: 'Nenhuma conta a receber neste recorte.',
  erroCarregamento: 'Não foi possível carregar as contas a receber agora. Tente novamente em instantes.',
} as const;
