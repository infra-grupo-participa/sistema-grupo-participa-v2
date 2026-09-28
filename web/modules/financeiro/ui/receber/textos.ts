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
  legenda: 'Certo: dinheiro já vendido, contratado ou informado pelo financeiro. Estimado: vendas novas, eventos planejados e reserva de reembolso, calculados por premissa (a projeção liga e desliga em Premissas). Acordos combinados no board aparecem como informativo, fora da soma.',
} as const;

/** Nomes dos blocos da tela. */
export const BLOCOS_RECEBER = {
  vendasRealizadas: 'Vendas já realizadas',
  assinaturasEParcelasFuturas: 'Assinaturas e parcelas futuras',
  recebimentosInformados: 'Recebimentos informados',
  vendasNovas: 'Vendas novas',
  eventosPlanejados: 'Eventos planejados',
  reserva: 'Reserva de reembolso e chargeback',
  informativoBoard: 'Acordos combinados no board',
} as const;

/** Seções da grade: certo × estimado, e a faixa informativa abaixo dos totais. */
export const SECOES_RECEBER = {
  certo: 'Certo',
  certoAjuda: 'vendido, contratado ou informado',
  estimado: 'Estimado',
  estimadoAjuda: 'calculado por premissa',
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
} as const;

/** Grade semana a semana e composição da célula (antes PROVISORIO em ContasAReceber.tsx). */
export const GRADE_RECEBER = {
  total: 'Total',
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
  legenda: 'O cenário muda o estimado: o tamanho do evento planejado e, se gravadas em Premissas para o cenário, a venda nova e a reserva. No certo, muda só a perda mensal que tiver valor próprio do cenário. Sem valor próprio gravado, conservador e otimista usam o da base.',
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
  projecaoDesligada: 'Desligada: a Semana a semana mostra só o certo (vendas já realizadas, assinaturas e parcelas, recebimentos informados).',
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
  identificadorSemPermissao: 'Só quem pode ver CPF informa CPF/e-mail',
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
  identificadoresSemPermissao: 'Sem permissão para ver CPF: deixe Identificador 1 e 2 vazios (linha com CPF/e-mail volta com erro e nada vai ao banco).',
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
