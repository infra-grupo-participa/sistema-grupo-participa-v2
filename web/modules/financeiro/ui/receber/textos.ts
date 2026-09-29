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
  // A aba é "Previsão de caixa" (o item do menu); "Contas a Receber" é o título da SEÇÃO do menu, não da aba.
  titulo: 'Previsão de caixa',
  subtitulo: 'Quanto dinheiro entra no caixa, semana a semana.',
} as const;

/** Legenda de escopo — fixa acima dos blocos: o que é certo, o que é estimado e o que fica fora da soma. */
export const ESCOPO_RECEBER = {
  legenda: 'Certo: dinheiro já vendido, contratado ou informado pelo financeiro, e contratos Holding Familiar assinados. Estimado: vendas novas, eventos planejados e reserva de reembolso, calculados por premissa (a projeção liga e desliga em Premissas), e contratos Holding Familiar sem contrato assinado. Acordos combinados no board aparecem como informativo, fora da soma.',
} as const;

/** Nomes dos blocos da tela. */
export const BLOCOS_RECEBER = {
  vendasRealizadas: 'Vendas já realizadas',
  assinaturasEParcelasFuturas: 'Assinaturas e parcelas futuras',
  recebimentosInformados: 'Recebimentos informados',
  vendasNovas: 'Vendas novas',
  eventosPlanejados: 'Eventos planejados',
  reserva: 'Reserva de reembolso e chargeback',
  contratosHoldingFamiliar: 'Contratos Holding Familiar',
  informativoBoard: 'Acordos combinados no board',
} as const;

/** Seções da grade: certo × estimado, e a faixa informativa abaixo dos totais. */
export const SECOES_RECEBER = {
  certo: 'Certo',
  certoAjuda: 'vendido, contratado, informado ou assinado',
  estimado: 'Estimado',
  estimadoAjuda: 'calculado por premissa ou sem contrato assinado',
  subtotalCerto: 'Subtotal certo',
  subtotalEstimado: 'Subtotal estimado',
  totalGeral: 'Total da semana (certo + estimado)',
  nenhumEstimado: 'Nenhum valor estimado nesta previsão. A projeção liga e desliga em Premissas.',
  informativo: 'Informativo — fora da soma',
  informativoAjuda: 'somar contaria duas vezes com a venda nova',
  semBase: 'sem base medida',
  informativoForaDoPeriodo: (n: number, v: string) => `${n} acordo(s) do board fora do período da grade (${v}), também fora da soma.`,
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

/** Rótulos das sub-abas de Previsão de caixa (#receber?ver=), nesta ordem. */
export const SUBABAS_RECEBER = {
  rotuloGrupo: 'Previsão de caixa',
  semana: 'Semana a semana',
  recorrencias: 'Recorrências',
  informados: 'Recebimentos informados',
  eventos: 'Eventos',
  premissas: 'Premissas',
  base: 'Base auditável',
} as const;

/** Sub-aba Base auditável (#receber?ver=base): a lista inteira do cenário ativo, linha a linha, com o porquê de cada
 * tratamento, o resumo por centro de custo × mês e a exportação em CSV. Sem consulta nova. */
export const BASE_AUDITAVEL = {
  titulo: 'Base auditável',
  caption: (cenario: string) => `Linhas da previsão de caixa, cenário ${cenario}`,
  filtros: 'Filtros da base auditável',
  situacao: 'Situação',
  bloco: 'Bloco',
  centroCusto: 'Centro de custo',
  certeza: 'Certeza',
  busca: 'Buscar',
  buscaAjuda: 'grupo, descrição, produto, tratamento',
  de: 'Caixa de',
  ate: 'Caixa até',
  todas: 'Todas',
  todos: 'Todos',
  semCentro: 'Sem centro de custo',
  semCerteza: 'Sem certeza',
  limpar: 'Limpar filtros',
  situacaoSemBase: 'Sem base medida',
  situacaoInformativo: 'Informativo (fora da soma)',
  certezas: { certo: 'Certo', estimado: 'Estimado', informativo: 'Informativo' } as Record<string, string>,
  // Colunas (a ordem é a da tabela e a do CSV).
  dataCaixa: 'Data de caixa',
  semana: 'Semana',
  grupo: 'Grupo',
  componente: 'Componente',
  descricao: 'Descrição',
  produto: 'Produto',
  valorEsperado: 'Valor esperado',
  valorBruto: 'Valor bruto',
  fator: 'Fator',
  tratamento: 'Tratamento',
  cenario: 'Cenário',
  semBaseValor: 'sem base medida',
  vazio: 'Nenhuma linha neste filtro.',
  linhas: (n: number, total: number) => `${n.toLocaleString('pt-BR')} de ${total.toLocaleString('pt-BR')} linhas`,
  somaAReceber: (n: number) => `Soma a receber (${n.toLocaleString('pt-BR')} ${n === 1 ? 'linha' : 'linhas'})`,
  foraDaSoma: 'Fora da soma, só contagem:',
  semAReceber: 'Nenhuma linha a receber neste filtro: nada soma.',
  pagina: (p: number, n: number) => `Página ${p} de ${n}`,
  anterior: 'Anterior',
  proxima: 'Próxima',
  paginacao: 'Paginação da base auditável',
  // Resumo centro de custo × mês.
  resumoTitulo: 'Entradas por centro de custo × mês',
  resumoCaption: 'Soma do valor esperado a receber das linhas filtradas, por centro de custo e mês da data de caixa',
  resumoTotal: 'Total de entradas',
  resumoVazio: 'Nenhuma linha a receber com data de caixa neste filtro.',
  resumoSemData: (n: number, v: string) => `${n} linha(s) a receber sem data de caixa (${v}) fora do resumo.`,
  // Exportação.
  exportar: 'Exportar CSV',
  nivel: 'Dado pessoal',
  niveis: { completo: 'Completo (com nome)', sem_dado_pessoal: 'Sem dado pessoal (Pessoa N)' } as Record<string, string>,
  exportou: (n: number) => `${n.toLocaleString('pt-BR')} ${n === 1 ? 'linha exportada' : 'linhas exportadas'}.`,
  pessoa: (n: number) => `Pessoa ${n}`,
} as const;

/** Grade semana a semana e composição da célula (antes PROVISORIO em ContasAReceber.tsx). */
export const GRADE_RECEBER = {
  total: 'Total',
  hoje: 'hoje',
  kpis: {
    total: (n: number) => `Entra em ${n} ${n === 1 ? 'semana' : 'semanas'}`,
    certo: 'Já é certo',
    estimado: 'Estimado',
    estimadoAjuda: 'por premissa, fora do certo',
    semEstimado: 'sem estimado',
    semEstimadoAjuda: 'projeção desligada ou sem base',
    pico: 'Semana de pico',
    hojeEm: (n: number) => `hoje em S${n}`,
  },
  componenteCheio: 'Valor cheio',
  recebimentoDesligado: 'Cálculo de recebimento desligado',
  semDataCaixa: (n: number, v: string) => `${n} cobrança(s) a receber sem data de caixa (${v}) não estão somadas acima.`,
  foraDoPeriodo: (n: number, v: string) => `${n} lançamento(s) a receber fora do período da grade (${v}) não estão somados acima.`,
  fechar: 'Fechar',
  todasAsSemanas: 'todas as semanas',
  caiNoCaixa: 'Cai no caixa',
  parte: 'Parte',
  vendasDe: 'Vendas de',
  transacao: 'Transação',
  produto: 'Produto',
  nome: 'Nome',
  liquidoDaVenda: 'Líquido da venda',
  valor: 'Valor',
  cobrancaPrevista: 'Vencimento',
  semVendasNoDetalhe: 'vendas do dia não vieram no detalhe',
  vendas: (n: number) => `${n} venda(s)`,
  bruto: 'Bruto',
  esperado: 'Esperado',
  fator: 'Fator',
  tratamento: 'Tratamento',
  /** Linha pequena sob o esperado, na célula com perda. */
  brutoCurto: (v: string) => `bruto ${v}`,
  resumoComPerda: (bruto: string, esperado: string) => `Bruto ${bruto} · esperado ${esperado}`,
  pagasDoContrato: (n: number) => `${n} ${n === 1 ? 'transação paga' : 'transações pagas'} do contrato`,
  semPagasNoContrato: 'nenhuma transação paga do contrato até o corte',
  parcela: 'Nº',
  pagaEm: 'Paga em',
  liquidoPago: 'Líquido pago',
  carregandoCenario: 'Carregando o cenário…',
  /** Composição dos blocos 3 e 4: de onde veio cada venda projetada. */
  deOndeVeio: 'De onde veio',
  vendaDoDia: 'Venda do dia',
  vendasProjetadas: (n: number) => `${n} dia(s) de venda projetada`,
  percentual: 'Percentual',
  foraDaSoma: 'fora da soma',
} as const;

/** Seletor de cenário da grade. Conferido contra o banco (z66/z67): o cenário escolhe o tamanho do evento planejado e,
 * quando há valor próprio do cenário em Premissas, a venda nova, a reserva e a perda mensal. A perda mensal mexe no
 * esperado do CERTO (assinaturas, parcelas, informados) — por isso a legenda não diz "só o estimado". */
export const CENARIO_RECEBER = {
  rotulo: 'Cenário',
  base: 'Base',
  conservador: 'Conservador',
  otimista: 'Otimista',
  legenda: 'O cenário muda o estimado: o tamanho do evento planejado, o percentual de recebimento dos contratos sem assinatura e, se gravadas em Premissas para o cenário, a venda nova e a reserva. No certo, muda só a perda mensal e o recebimento de contrato assinado que tiverem valor próprio do cenário. Sem valor próprio gravado, conservador e otimista usam o da base.',
} as const;

/** Recorrências (antes PROVISORIO em Recorrencias.tsx). */
export const TABELA_RECORRENCIAS = {
  todas: 'Todas',
  grupo: 'Grupo',
  nome: 'Nome',
  produto: 'Produto',
  cobrancaPrevista: 'Vencimento',
  caiNoCaixa: 'Cai no caixa',
  valor: 'Valor',
  esperado: 'Esperado',
  situacao: 'Situação',
  nenhuma: 'Nenhuma cobrança nesta situação.',
} as const;

/** Sub-aba Premissas: com que números a previsão é feita, desde quando e quem mudou. */
export const PREMISSAS_RECEBER = {
  titulo: 'Premissas da previsão',
  explicacao: 'Cada mudança grava uma vigência nova a partir da data escolhida; nada é apagado. A previsão já vista não muda.',
  carregando: 'Carregando premissas…',
  erroCarregamento: 'Não foi possível carregar as premissas.',
  tentarDeNovo: 'Tentar de novo',
  vazio: 'Nenhuma premissa cadastrada.',
  somenteLeitura: 'Somente leitura: alterar premissa exige permissão de operar o financeiro.',
  premissa: 'Premissa',
  cenario: 'Cenário',
  valor: 'Valor',
  desde: 'Desde',
  quem: 'Quem mudou',
  faixa: 'Faixa',
  acoes: 'Ações',
  usaBase: (v: string) => `usa a base (${v})`,
  semVigente: 'sem vigência hoje',
  proxima: (v: string, d: string) => `próxima: ${v} a partir de ${d}`,
  historico: (n: number) => `Histórico (${n})`,
  ocultarHistorico: 'Ocultar histórico',
  semHistorico: 'sem vigência anterior',
  situacaoVigencia: { vigente: 'vigente', futura: 'futura', anterior: 'anterior' } as Record<string, string>,
  fonte: 'Fonte',
  alterar: 'Alterar',
  novoValor: (unidade: string) => `Novo valor${unidade ? ` (${unidade})` : ''}`,
  vigenteDe: 'Vale a partir de',
  salvar: 'Gravar vigência',
  salvando: 'Gravando…',
  cancelar: 'Cancelar',
  gravou: 'Vigência gravada. A previsão foi recarregada.',
  ligado: 'Ligado',
  desligado: 'Desligado',
  sistema: 'carga inicial',
  /** Sugestão medida (z67, fn_fin_receber_sugestoes). */
  sugestaoMedida: (v: string, base: string) => `Sugestão medida: ${v} (base: ${base})`,
  sugestaoSemBase: (base: string) => `Sugestão medida: sem base medida (${base})`,
  valeSugestao: (v: string) => `vale a sugestão medida (${v})`,
  semBaseMedida: 'sem vigência gravada e sem base medida',
  usarSugestao: 'Usar sugestão',
  usarSugestaoRotulo: (rotulo: string, cenario: string, v: string) => `Usar sugestão: ${rotulo} (${cenario}) = ${v}, a partir de hoje`,
  gravouSugestao: 'Sugestão gravada como vigência de hoje. A previsão foi recarregada.',
  erroSugestoes: 'Sugestões medidas indisponíveis agora.',
  carregandoSugestoes: 'Carregando sugestões medidas…',
  /** Liga/desliga da projeção (projecao_no_receber). */
  projecaoTitulo: 'Projeção na previsão',
  projecaoLigada: 'Ligada: vendas novas, eventos planejados, reserva de reembolso e o informativo dos acordos do board entram na Semana a semana (seção Estimado e faixa Informativo).',
  projecaoDesligada: 'Desligada: a Semana a semana mostra o certo (vendas já realizadas, assinaturas e parcelas, recebimentos informados, contratos assinados) e, no estimado, só os contratos Holding Familiar sem assinatura.',
  ligarProjecao: 'Ligar a projeção a partir de hoje',
  desligarProjecao: 'Desligar a projeção a partir de hoje',
  projecaoGravada: (ligada: boolean) => `Projeção ${ligada ? 'ligada' : 'desligada'} a partir de hoje. A previsão foi recarregada.`,
} as const;

/** Seção "Feriados bancários" dentro de Premissas. */
export const FERIADOS_RECEBER = {
  titulo: 'Feriados bancários',
  explicacao: 'Dia útil de caixa desconsidera sábado, domingo e os feriados ativos. Desligar mantém o registro.',
  carregando: 'Carregando feriados…',
  erroCarregamento: 'Não foi possível carregar os feriados.',
  ano: 'Ano',
  todos: 'Todos',
  dia: 'Dia',
  nome: 'Nome',
  situacao: 'Situação',
  ativo: 'Ativo',
  inativo: 'Desligado',
  fonte: 'Fonte',
  quem: 'Quem mudou',
  acoes: 'Ações',
  adicionar: 'Adicionar feriado',
  gravar: 'Gravar feriado',
  desligar: 'Desligar',
  religar: 'Religar',
  vazio: 'Nenhum feriado neste ano.',
  gravou: 'Feriado gravado. A previsão foi recarregada.',
  desligou: 'Feriado desligado. A previsão foi recarregada.',
} as const;

/** Sub-aba Eventos (#receber?ver=eventos, z67): evento planejado do bloco 4. */
export const EVENTOS_RECEBER = {
  titulo: 'Eventos planejados',
  explicacao: 'Venda do evento = tamanho × a venda de cada dia do evento de referência, a partir da abertura. Só os dias depois de hoje entram na previsão; o efeito rebote depois do evento não é somado. Nada é apagado: arquive.',
  carregando: 'Carregando eventos planejados…',
  erroCarregamento: 'Não foi possível carregar os eventos planejados.',
  tentarDeNovo: 'Tentar de novo',
  vazio: 'Nenhum evento planejado nesta situação.',
  somenteLeitura: 'Somente leitura: cadastrar e arquivar exige permissão de operar o financeiro.',
  novo: 'Novo evento planejado',
  filtro: 'Situação',
  todosSemArquivados: 'Todos (sem arquivados)',
  situacao: { ativo: 'Ativo', encerrado: 'Encerrado', arquivado: 'Arquivado' } as Record<string, string>,
  evento: 'Evento',
  vendas: 'Vendas',
  referencia: 'Referência',
  tamanho: 'Tamanho',
  tamanhoAjuda: 'Tamanho em vezes a referência: 1 = igual; 1,3 = 30% maior.',
  totalEsperado: 'Venda esperada',
  totalEsperadoAjuda: 'Tamanho × líquido total da referência. É venda, não caixa.',
  pausa: 'Pausa HM avulso',
  sim: 'Sim',
  nao: 'Não',
  quem: 'Quem mudou',
  acoes: 'Ações',
  editar: 'Editar',
  arquivar: 'Arquivar',
  verCurva: 'Ver curva',
  ocultarCurva: 'Ocultar curva',
  semVendaRef: 'referência sem venda medida',
  cenarios: (c: string, b: string, o: string) => `cons. ${c} · base ${b} · ot. ${o}`,
  tituloNovo: 'Novo evento planejado',
  tituloEditar: 'Editar evento planejado',
  nome: 'Nome',
  abertura: 'Abertura (dia 0 da curva)',
  eventoRef: 'Evento de referência',
  eventoRefAjuda: 'Só eventos da educação, com as vendas encerradas e até 31 dias de venda.',
  carregandoRef: 'Carregando eventos de referência…',
  erroRef: 'Não foi possível carregar os eventos de referência.',
  selecione: 'Selecione',
  conservador: 'Conservador',
  base: 'Base',
  otimista: 'Otimista',
  pausaAvulso: 'Pausar o HM avulso nas semanas do evento',
  pausaAvulsoAjuda: 'Zera a venda nova do HM avulso nas semanas (segunda a domingo) tocadas pelo evento, para não contar duas vezes.',
  observacao: 'Observação',
  salvar: 'Gravar evento',
  salvando: 'Gravando…',
  cancelar: 'Cancelar',
  gravou: 'Evento gravado. A previsão foi recarregada.',
  motivo: 'Motivo (3 a 500 caracteres)',
  confirmarArquivar: 'Confirmar arquivamento',
  arquivou: 'Evento arquivado. A previsão foi recarregada.',
  arquivadoPor: (quem: string, motivo: string) => `Arquivado por ${quem}: ${motivo}`,
  curvaTitulo: (ref: string) => `Curva de ${ref}`,
  dia: 'Dia',
  diaPlanejado: 'No evento planejado',
  participacao: 'Participação',
  liquidoRef: 'Líquido da referência',
  vendaBase: 'Venda esperada (base)',
  curvaVazia: 'A referência não tem venda por dia no espelho.',
} as const;

/** Componentes do bloco 1 (vendas já realizadas): a divisão antecipação/retido. "Garantia" tinha três sentidos
 * diferentes no sistema (Conflito 2 do catálogo) — o rótulo agora diz o que a linha é: 10% retido, volta em D+30. */
export const COMPONENTES_VENDA = {
  antecipacao: 'Antecipação (D+2)',
  garantia: 'Retido 10% (volta em D+30)',
  reserva: 'Reserva (negativa)',
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
  explicacao: 'Renovações, serviços e contratos Holding Familiar negociados fora. Via Hotmart: a baixa é automática quando o pagamento chega. Pago fora: baixa manual. Contrato Holding Familiar entra na previsão como bloco 7 (assinado no certo, sem assinatura no estimado).',
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
  contrato_holding_familiar: 'Contrato Holding Familiar',
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
  identificadorSemPermissao: 'Só quem pode ver CPF informa CPF/e-mail',
  acordoDesde: 'Acordo a partir de',
  recebidoAcumulado: 'Recebido / acumulado',
  baixaManual: 'Baixa manual',
  situacao: 'Situação',
  acoes: 'Ações',
  sim: 'S',
  nao: 'N',
  selecione: 'Selecione',
  // Contrato Holding Familiar (z73)
  parcela: 'Parcela',
  parcelaDe: 'de',
  parcelaAjuda: 'nº e total (ex.: 2 de 5); vazio se não for parcelado',
  parcelaN: 'Número da parcela',
  parcelaTotal: 'Total de parcelas',
  contratoAssinado: 'Contrato assinado',
  assinado: 'assinado',
  semAssinatura: 'sem contrato assinado',
  simExtenso: 'Sim',
  naoExtenso: 'Não',
  resumoContrato: (n: number | null, de: number | null, assinado: boolean | null) =>
    [n != null && de != null ? `${n} de ${de}` : null, assinado == null ? null : assinado ? 'assinado' : 'sem contrato assinado']
      .filter(Boolean).join(' · '),
  filtroTipo: 'Tipo',
  todosTipos: 'Todos os tipos',
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
  identificadoresSemPermissao: 'Sem permissão para ver CPF: deixe Identificador 1 e 2 vazios (linha com CPF/e-mail volta com erro e nada vai ao banco).',
  // Planilha "Contratos Soluções" (z73): reconhecida pelo cabeçalho.
  ouContratos: 'Ou a planilha Contratos Soluções, COM o cabeçalho (é por ele que ela é reconhecida):',
  formatoContratos: 'Planilha Contratos Soluções reconhecida pelo cabeçalho: tudo entra como Contrato Holding Familiar.',
  statusBaixa: 'Pago e Entrada gravam a baixa na data do vencimento (ou na data escrita no Status, ex.: Pago 12/10/2026); Pendente fica a receber.',
  avisos: 'Avisos',
  confirmeAvisos: (n: number) => `${n} ${n === 1 ? 'linha com aviso' : 'linhas com aviso'}: confira antes de gravar.`,
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

/** Visão geral do Contas a Receber (#visao, F4): 4 semanas, alertas, o que mudou desde a última foto e previsto ×
 * realizado. Sem texto de metodologia na tela (a regra mora no comentário de domain/visao-receber.ts). */
export const VISAO_GERAL = {
  titulo: 'Visão geral',
  // Próximas 4 semanas
  semanasTitulo: 'Próximas 4 semanas',
  semanasCaption: 'A receber nas próximas 4 semanas (segunda a domingo; a 1ª começa hoje), cenário base',
  linha: 'Linha',
  certo: 'Certo',
  estimado: 'Estimado',
  total: 'Total',
  quatroSemanas: '4 semanas',
  estimadoDesligado: 'desligado',
  estaSemana: 'Esta semana',
  semanaN: (n: number) => `Semana ${n}`,
  nadaPrevisto: 'nada previsto',
  abrirGrade: (rotulo: string, periodo: string, valor: string) => `${rotulo}, ${periodo}: ${valor}. Abrir Semana a semana`,
  carregandoPrevisao: 'Carregando a previsão…',
  recebimentoDesligado: 'Cálculo de recebimento desligado: sem data de caixa, as 4 semanas não têm valor. Veja Semana a semana.',
  // Alertas
  alertasTitulo: 'Alertas',
  alertasSemPrevisao: 'Os alertas dependem da previsão, que não carregou.',
  foraDaProjecao: 'Cobranças fora da projeção (atraso)',
  informadosACobrar: 'Recebimentos informados a cobrar (em atraso)',
  semBase: 'Grupos estimados sem base medida',
  eventosEncerrados: 'Eventos planejados encerrados, sem arquivar',
  eventosCarregando: 'carregando…',
  eventosErro: 'não foi possível conferir',
  projecao: 'Projeção do estimado',
  projecaoLigada: 'ligada',
  projecaoDesligada: 'desligada: o estimado não entra na previsão',
  nenhum: 'nenhum',
  nenhuma: 'nenhuma',
  cobrancas: (n: number) => `${n} ${n === 1 ? 'cobrança' : 'cobranças'}`,
  informados: (n: number) => `${n} ${n === 1 ? 'informado' : 'informados'}`,
  grupos: (n: number) => `${n} ${n === 1 ? 'grupo' : 'grupos'}`,
  eventos: (n: number) => `${n} ${n === 1 ? 'evento' : 'eventos'}`,
  verEm: (onde: string) => `ver em ${onde}`,
  // O que mudou
  mudouTitulo: 'O que mudou desde a última foto',
  umaFoto: (foto: string, proxima: string) =>
    `Há 1 foto da previsão (${foto}). A primeira comparação aparece depois da próxima foto, segunda ${proxima} às 06h11.`,
  semFoto: (proxima: string) => `Nenhuma foto da previsão ainda. A primeira sai na segunda ${proxima} às 06h11.`,
  fotoReconstruida: 'reconstruída com os dados do dia em que foi tirada',
  comparando: (a: string, b: string) => `Foto de ${a} × foto de ${b}`,
  somaFotos: (a: string, b: string, d: string) => `a receber (todo o horizonte): ${a} → ${b} (${d})`,
  mudouCaption: 'O que mudou por bloco e grupo entre as duas fotos mais recentes',
  grupo: 'Bloco · grupo',
  antes: 'Foto anterior',
  agora: 'Última foto',
  diferenca: 'Diferença',
  porque: 'O que mudou',
  semMudanca: (n: number) => `${n} ${n === 1 ? 'grupo sem mudança' : 'grupos sem mudança'}.`,
  nadaMudou: 'Nada mudou entre as duas fotos.',
  porMotivoTitulo: 'Por que o a receber mudou (soma por motivo)',
  entrouSaiu: (entrou: string, saiu: string) => `Entrou ${entrou} · saiu ${saiu}`,
  saldo: (v: string) => `saldo ${v}`,
  carregandoMudancas: 'Carregando o que mudou…',
  /** Motivo em texto claro; `n` = cobranças, dias ou informados distintos. */
  motivos: {
    entrou: 'entrou',
    saiu_pagamento: 'saiu porque foi pago',
    saiu_atraso: 'saiu por atraso',
    saiu_periodo: 'saiu porque a data passou',
    saiu_outro: 'saiu (cancelado, estornado, arquivado ou coberto por informado)',
    mudou_valor: 'mudou o valor',
    mudou_premissa: 'mudou a premissa',
  } as Record<string, string>,
  itens: (n: number) => `${n} ${n === 1 ? 'item' : 'itens'}`,
  // Previsto × realizado
  prTitulo: 'Previsão × realizado',
  prCaption: 'O que a foto de segunda previa para a semana e o que caiu, por semana completa',
  semana: 'Semana',
  certoPrevisto: 'Certo previsto',
  certoRealizado: 'Certo realizado',
  acerto: 'Acerto',
  estimadoPrevisto: 'Estimado previsto',
  foraDaFoto: 'Vendas novas e outros (caíram fora da foto)',
  detalhar: 'Detalhar',
  fechar: 'Fechar',
  detalheCaption: (semana: string) => `Previsto × realizado por bloco e grupo, semana ${semana}`,
  previsto: 'Previsto',
  realizado: 'Realizado',
  desvio: 'Desvio',
  naoMedido: 'não medido',
  acertoUltima: 'Acerto do certo na última semana medida:',
  acertoMedia: (media: string, n: number) => `média ${media} em ${n} ${n === 1 ? 'semana' : 'semanas'}`,
  acimaDaPremissa: 'acima da premissa',
  dentroDaPremissa: 'dentro da premissa',
  foraDaFotoGrupo: 'Fora da foto (vendas novas e outros)',
  semanasSemFoto: (n: number) => `${n} ${n === 1 ? 'semana' : 'semanas'} sem foto no início (antes da 1ª foto).`,
  nenhumaSemana: (de: string, ate: string, sai: string) =>
    `Ainda não há semana completa com foto. O primeiro previsto × realizado (semana ${de} a ${ate}) aparece na segunda ${sai}.`,
  carregandoPr: 'Carregando o previsto × realizado…',
  // Perda medida
  perdaTitulo: 'Perda medida nas recorrências (sugestão)',
  perdaCaption: 'Perda medida por grupo das assinaturas e parcelas, ao lado da premissa em uso',
  perdaMedida: 'Perda medida',
  premissaEmUso: 'Premissa em uso',
  resolvidas: 'Resolvidas',
  perdidas: 'Perdidas',
  valorPerdido: 'Valor perdido / resolvido',
  semResolvidas: 'sem cobrança resolvida',
  ajustar: 'Ajustar em Premissas',
  ajustarGrupo: (g: string) => `Ajustar a perda de ${g} em Premissas`,
  perdaVazia: 'Sem cobrança resolvida nas semanas medidas.',
  // Geral
  tentarDeNovo: 'Tentar de novo',
} as const;

/** Faixa executiva (KPIs, gráfico e chips) de cada sub-aba do Contas a Receber. Números vêm de
 * domain/receber-executivo.ts; aqui só o texto. */
export const EXECUTIVO_RECEBER = {
  recorrencias: {
    aReceber: 'A receber',
    emDia: 'Em dia',
    emDiaAjuda: 'do valor a cobrar, sem atraso',
    atraso: 'Em atraso (fora da projeção)',
    realizadas: 'Já realizadas',
    nenhuma: 'nenhuma',
    nadaAtrasado: 'nada vencido fora da previsão',
    semAtraso: 'Nenhuma cobrança em atraso.',
    cobrancas: (n: number) => `${n.toLocaleString('pt-BR')} ${n === 1 ? 'cobrança' : 'cobranças'}`,
    maior: (produto: string, pct: string) => `maior: ${produto} (${pct})`,
    maisAntiga: (dias: number) => `a mais antiga venceu há ${dias} ${dias === 1 ? 'dia' : 'dias'}`,
    cobertas: (v: string) => `${v} coberto por informado`,
    agingTitulo: 'Atraso por idade (dias desde o vencimento)',
    faixas: { ate30: 'Até 30 dias', de31a60: '31 a 60 dias', mais60: 'Mais de 60 dias' },
    ha: (dias: number) => `há ${dias} ${dias === 1 ? 'dia' : 'dias'}`,
    trocarFiltro: 'Troque o filtro acima para ver as outras situações.',
  },
  informados: {
    aCobrar: 'Em atraso — cobrar',
    aReceber: 'A receber',
    recebido: 'Recebido na Hotmart',
    baixado: 'Baixado fora',
    nenhum: 'nenhum',
    nadaACobrar: 'nenhum informado vencido',
    semProximo: 'nenhuma data futura',
    itens: (n: number) => `${n.toLocaleString('pt-BR')} ${n === 1 ? 'informado' : 'informados'}`,
    maisAntigo: (dias: number) => `o mais antigo venceu há ${dias} ${dias === 1 ? 'dia' : 'dias'}`,
    proximo: (data: string, v: string) => `próximo: ${data} · ${v}`,
    ha: (dias: number) => `há ${dias} ${dias === 1 ? 'dia' : 'dias'}`,
    trocarFiltro: 'Troque o filtro acima ou cadastre um novo.',
  },
  eventos: {
    previsto: 'Previsto dos ativos (base)',
    proximo: 'Próxima abertura',
    semReferencia: 'Sem venda de referência',
    encerrados: 'Encerrados sem arquivar',
    nenhum: 'nenhum',
    nenhuma: 'nenhuma',
    ativos: (n: number) => `${n} ${n === 1 ? 'evento ativo' : 'eventos ativos'}`,
    foraDaSoma: (n: number) => `${n} sem referência fora da soma`,
    todosComReferencia: 'todos os ativos têm referência',
    semReferenciaAjuda: 'total esperado desconhecido — escolha outra referência',
    encerradosAjuda: 'arquive para sair da lista',
    encerradosOk: 'lista em dia',
    graficoTitulo: 'Total esperado por evento (cenário base)',
    semVendaRef: 'sem venda de referência',
  },
  premissas: {
    projecao: 'Projeção do estimado',
    ligada: 'Ligada',
    desligada: 'Desligada',
    projecaoLigadaAjuda: 'vendas novas e eventos entram na previsão',
    projecaoDesligadaAjuda: 'a previsão mostra o certo e, no estimado, só os contratos sem assinatura',
    total: 'Premissas',
    semVigente: (n: number) => (n === 0 ? 'todas com valor gravado' : `${n} sem valor gravado (vale a sugestão)`),
    diferem: 'Diferem da sugestão',
    semMedida: 'nenhuma premissa com medida ainda',
    diferemAjuda: (n: number) => `de ${n} com medida · confira a seta em cada linha`,
    feriados: (ano: number) => `Feriados ativos em ${ano}`,
    feriadosAjuda: 'contam como dia sem caixa',
    carregando: 'carregando…',
    igual: 'igual à sugestão',
  },
  base: {
    soma: 'Soma a receber (recorte)',
    linhas: 'Linhas no recorte',
    linhasAjuda: (total: string) => `de ${total} no cenário`,
    maior: 'Maior linha a receber',
    perda: 'Perda aplicada',
    perdaAjuda: 'bruto − esperado no recorte',
    semPerda: 'sem perda no recorte',
    somam: (n: number) => `${n.toLocaleString('pt-BR')} ${n === 1 ? 'linha soma' : 'linhas somam'}`,
    nenhuma: 'nenhuma',
    trocarFiltro: 'Limpe ou troque os filtros acima.',
  },
} as const;
