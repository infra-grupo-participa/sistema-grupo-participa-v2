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
  legenda: 'Só dinheiro já vendido, contratado ou informado pelo financeiro (renovações negociadas fora, cadastradas em Recebimentos informados). Projeção de vendas novas e eventos entra em outra etapa.',
} as const;

/** Nomes dos blocos da tela. */
export const BLOCOS_RECEBER = {
  vendasRealizadas: 'Vendas já realizadas',
  assinaturasEParcelasFuturas: 'Assinaturas e parcelas futuras',
  recebimentosInformados: 'Recebimentos informados',
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
  /** Cobrança do bloco 2 que um recebimento informado já cobre: o informado prevalece, ela sai da soma. */
  cobertaInformado: 'Coberta por recebimento informado',
} as const;

// ─── Recebimentos informados (bloco 5) ──────────────────────────────────────

/** Sub-seção da aba: lista, formulário, baixa manual, arquivar e colar da planilha. */
export const SECAO_INFORMADOS = {
  titulo: 'Recebimentos informados',
  explicacao: 'Renovações e serviços negociados fora. Via Hotmart: a baixa é automática quando o pagamento chega. Pago fora: baixa manual.',
  carregando: 'Carregando recebimentos informados…',
  erroCarregamento: 'Não foi possível carregar os recebimentos informados.',
  tentarDeNovo: 'Tentar de novo',
  vazio: 'Nenhum recebimento informado nesta situação.',
  todosAtivos: 'Todos (sem arquivados)',
  novo: 'Novo',
  colar: 'Colar da planilha',
  somenteLeitura: 'Somente leitura: cadastrar e baixar exige permissão de operar o financeiro.',
} as const;

/** Situação de cada recebimento informado (lista). Nunca "devendo". */
export const SITUACAO_INFORMADO: Record<string, string> = {
  a_receber: 'A receber',
  realizado_hotmart: 'Realizado na Hotmart',
  baixado_fora: 'Baixado fora',
  em_atraso_cobrar: 'Em atraso — cobrar',
  arquivado: 'Arquivado',
};

/** Tipo do recebimento informado (texto da planilha). */
export const TIPO_INFORMADO: Record<string, string> = {
  renovacao_diamante: 'Renovação Diamante',
  renovacao_aurum: 'Renovação Aurum',
  diamante_extra: 'Diamante extra',
  outro: 'Outro',
};

/** Colunas da lista e campos do formulário. */
export const CAMPOS_INFORMADO = {
  dataPrevista: 'Data prevista',
  cliente: 'Cliente',
  tipo: 'Tipo',
  valor: 'Valor informado',
  viaHotmart: 'Via Hotmart',
  produtos: 'Produto na Hotmart',
  produtosAjuda: 'Mais de um: separe por ;',
  identificador1: 'Identificador 1',
  identificador2: 'Identificador 2',
  identificadorAjuda: 'CPF, CNPJ ou e-mail do pagador',
  identificadorMantido: (m: string) => `mantido (${m}) — digite para trocar`,
  acordoDesde: 'Acordo a partir de',
  recebidoAcumulado: 'Recebido / acumulado',
  baixaManual: 'Baixa manual',
  situacao: 'Situação',
  acoes: 'Ações',
  sim: 'S',
  nao: 'N',
  selecione: 'Selecione',
} as const;

/** Botões e confirmações das ações de cada linha. */
export const ACOES_INFORMADO = {
  editar: 'Editar',
  salvar: 'Salvar',
  cancelar: 'Cancelar',
  baixar: 'Baixar',
  dataDaBaixa: 'Data em que o dinheiro entrou',
  confirmarBaixa: 'Confirmar baixa',
  desfazerBaixa: 'Desfazer baixa',
  arquivar: 'Arquivar',
  motivo: 'Motivo (mínimo 3 caracteres)',
  confirmarArquivar: 'Confirmar arquivamento',
  arquivadoPor: (motivo: string) => `Motivo: ${motivo}`,
  tituloNovo: 'Novo recebimento informado',
  tituloEditar: 'Editar recebimento informado',
  salvando: 'Salvando…',
} as const;

/** Colar da planilha: prévia antes de gravar. */
export const COLAR_PLANILHA = {
  titulo: 'Colar da planilha',
  instrucao: 'Selecione as linhas no Google Sheets (com ou sem o cabeçalho), copie e cole aqui. Colunas, nesta ordem:',
  rotuloTexto: 'Linhas copiadas da planilha',
  conferir: 'Conferir (prévia, não grava)',
  conferindo: 'Conferindo…',
  gravar: (n: number) => `Gravar ${n} ${n === 1 ? 'linha' : 'linhas'}`,
  gravando: 'Gravando…',
  limpar: 'Limpar',
  cabecalhoIgnorado: 'Cabeçalho reconhecido e ignorado.',
  resumo: (n: number, erros: number) => `${n} ${n === 1 ? 'linha lida' : 'linhas lidas'} · ${erros} com erro`,
  corrijaNaPlanilha: 'Corrija na planilha e cole de novo. Nada foi enviado ao banco.',
  tudoOuNada: 'A gravação é tudo ou nada: com qualquer linha com erro, nada é gravado.',
  naoGravou: 'Nada foi gravado: o banco recusou as linhas abaixo.',
  gravou: (n: number) => `${n} ${n === 1 ? 'linha gravada' : 'linhas gravadas'}.`,
  linha: 'Linha',
  resultado: 'Conferência',
  ok: 'OK',
  semConferencia: 'sem resposta do banco para esta linha',
  identificadores: 'Identificadores',
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
