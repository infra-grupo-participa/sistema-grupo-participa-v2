// Tipos do módulo Financeiro. Espelham 1:1 o retorno das RPCs do Postgres.
//
// Vocabulário do negócio (Holding Master):
//   pacote  = R$ 15.000 (ou o valor cravado no card, quando o comercial negociou outro)
//   sinal   = R$ 300 pagos na Hotmart. É a sinalização de compra, não é entrada do pacote.
//   saldo   = o que sobra do pacote depois do sinal (R$ 14.700), pago à vista ou parcelado.
//   bruto   = o que o aluno pagou.  líquido = o que caiu na conta (Hotmart já tirou a taxa).

/** Status financeiro derivado no banco. Ordem = prioridade de cálculo. */
export type StatusFinanceiro =
  | 'reembolsado'
  | 'cancelado'
  | 'cancelamento_solicitado'
  | 'quitado'
  | 'em_pagamento'
  | 'vencido'
  | 'a_vencer'
  | 'futuro'
  | 'incalculavel'
  | 'oferta_enviada'
  | 'sem_acordo';

/** Uma linha de contas a receber = um card HM = um aluno na turma. */
export interface ContaReceber {
  contato_hm_id: string;
  comprador_id: string;
  aluno_id: string | null;

  nome: string;
  email: string;
  telefone: string | null;
  documento: string | null;

  turma: string | null;
  turma_origem: string | null;
  /** Tag de origem gravada por cs.fn_tag_hm_origem — mesma taxonomia da ativação. */
  canal: string;
  publico: string | null;
  tags: string[] | null;
  estagio_nome: string | null;
  estagio_aba: string | null;
  estagio_id: number | null;

  /** Identificador de produto. Hoje sempre 'Holding Masters'; base para outras fontes de receita. */
  produto: string;

  // ── Comercial (espelhado do card da ativação, read-only) ────────────────────
  /** Vendedor responsável (cs.contatos_hm.responsavel). */
  vendedor: string | null;
  reuniao_em: string | null;
  reuniao_resultado: string | null;
  entrevista_em: string | null;
  entrevista_resultado: string | null;
  obs_comercial: string | null;
  // Desfecho da reunião (F6/F7/F8, 0307/0308 — mesma extensão de 2026-08-20
  // documentada em CardBoard, abaixo). `intencao_pagamento_obs` é OUTRO campo
  // que `obs_comercial` acima — não confundir: obs_comercial segue sem fonte
  // na RPC do board (fica null via cardBoardParaContaReceber).
  /** Declaração comercial do desfecho — trilha [A] quando 'vai_pagar'. */
  intencao_pagamento: 'vai_pagar' | 'indeciso' | 'nao_vai_pagar' | null;
  /** A observação do que foi combinado na reunião. */
  intencao_pagamento_obs: string | null;
  /** Motivo categorizado da trilha [B] (não prometeu pagar) — lista fechada. */
  reuniao_motivo_tipo: string | null;
  /** Data em que o comercial disse que retoma o contato (trilha B). Não é
   *  vencimento — não entra em cobrança. */
  reuniao_retomar_em: string | null;

  /** Caiu no kanban de cancelamento (estágio 28) OU tem timestamp de cancelamento. */
  solicitou_cancelamento: boolean;

  sinal_bruto: number | null;
  sinal_liquido: number | null;
  sinal_taxas: number | null;
  sinal_pago_em: string | null;
  sinal_metodo: string | null;
  sinal_transacao: string | null;

  saldo_pago_bruto: number;
  saldo_pago_liquido: number;
  saldo_taxas: number;
  saldo_pago_em: string | null;
  saldo_metodo: string | null;
  saldo_lancamentos: number;

  total_pago_bruto: number | null;
  total_pago_liquido: number | null;
  pacote: number | null;
  /** O que a régua manda (15.000 lead novo, ou 15.000 − crédito para aluno da base). */
  pacote_regra: number | null;
  /** Cravado − régua: positivo = cobrando a mais; negativo = dinheiro na mesa. */
  divergencia_regra: number | null;
  credito: number | null;
  /** O que ainda falta receber. É a métrica que o financeiro persegue. */
  saldo_a_pagar: number | null;
  pago_pct: number | null;

  /** Data combinada com o aluno pelo financeiro (cs.contatos_hm.pagamento_previsto_em). */
  vencimento: string | null;
  acordo: string | null;
  pagamento_meio: string | null;
  pagamento_forma: string | null;
  pagamento_parcelas: number | null;
  parcelas_pagas: number | null;
  parcelas_contratadas: number | null;
  valor_parcela: number | null;
  /** Positivo = atrasado. Null = sem vencimento combinado. */
  dias_atraso: number | null;

  oferta_codigo: string | null;
  oferta_valor: number | null;
  oferta_link: string | null;
  oferta_recorrente: boolean | null;
  oferta_enviada_em: string | null;

  cancelamento_em: string | null;
  cancelamento_motivo: string | null;
  cancelamento_efetivado_em: string | null;
  quitado_em: string | null;
  reembolso_em: string | null;
  reembolso_status: string | null;
  reembolso_valor: number | null;

  ultimo_pagamento_em: string | null;
  situacao_ativacao: string | null;
  status_financeiro: StatusFinanceiro;

  /** Última cobrança registrada (régua). */
  ultima_cobranca_em: string | null;
  cobrancas_total: number;
  /** Quantas vezes o vencimento foi remarcado — promessa quebrada/remanejada. */
  remarcacoes: number;
}

/** Meta financeira de uma turma (personalização). */
export interface Meta {
  turma: string;
  meta_arrecadacao: number | null;
  meta_cobertura_pct: number | null;
  prazo_quitacao_dias: number | null;
  data_fechamento: string | null;
  obs: string | null;
  atualizado_em: string | null;
  atualizado_por: string | null;
}

/** Um passo da régua de cobrança. offset relativo ao vencimento. */
export interface ReguaPasso {
  id?: number;
  ordem: number;
  offset_dias: number;
  titulo: string;
  canal: string | null;
  ativo: boolean;
}

/** Uma cobrança registrada no histórico de uma conta. */
export interface Cobranca {
  id: string;
  quando: string;
  canal: string | null;
  resultado: string | null;
  obs: string | null;
  autor: string | null;
}

/** Um lançamento na razão do aluno, casado com a compra que caiu do webhook. */
export interface Lancamento {
  id: string;
  categoria: string;
  valor_bruto: number;
  valor_liquido: number;
  /** Taxa que a Hotmart reteve da empresa (= bruto − líquido). */
  taxas: number;
  /** Juros que o ALUNO pagou para parcelar. Não é custo da empresa. */
  juros_parcelamento: number;
  pago_em: string;
  origem: string;
  transacao: string | null;
  oferta_codigo: string | null;
  metodo_pagamento: string | null;
  parcela: number | null;
  obs: string | null;
  autor: string;
  produto_nome: string | null;
  compra_status: string | null;
  compra_parcelas: number | null;
  compra_data_vencimento: string | null;
}

export interface Oferta {
  codigo: string;
  valor: number | null;
  recorrente: boolean;
  link: string;
  ativo: boolean;
  usos: number;
  /**
   * `categoria` (read-only, legado que mente para 3 ofertas) e `papel`
   * (editável) NÃO vêm de fn_fin_ofertas hoje — a RPC retorna só os 6 campos
   * acima. Campos opcionais aqui para a UI não quebrar quando a RPC evoluir;
   * até lá ficam sempre undefined e a UI não finge exibir o que não tem.
   */
  categoria?: string | null;
  papel?: string | null;
}

export interface TurmaFin {
  turma: string;
  alunos: number;
  atual: boolean;
}

/** Uma linha do faturamento diário do HM (regime de caixa, por data de pagamento). */
export interface DiaFaturamento {
  dia: string;
  lancamentos: number;
  /** O que os clientes pagaram (com juros de parcelamento) = "Valor da Compra" do painel Hotmart. */
  cliente_pagou: number | null;
  /** Juros de parcelamento retidos pela Hotmart (cliente_pagou − bruto). Não é receita nossa. */
  juros: number | null;
  bruto: number;
  liquido: number;
  taxas: number;
  sinal: number | null;
  saldo: number | null;
  mensalidade: number | null;
  compra_cheia: number | null;
  ajuste: number | null;
  alunos: number;
}

/**
 * Uma compra Hotmart do aluno, em qualquer status — ciclo de vida completo
 * (boletos gerados, pendentes, vencidos, estornados). Espelha fn_fin_compras_aluno.
 */
export interface CompraHistorico {
  id: string;
  transacao: string;
  produto_id: string;
  produto_nome: string;
  oferta_codigo: string;
  status: string;
  hotmart_event: string;
  metodo_pagamento: string;
  parcelas: number | null;
  data_compra: string | null;
  data_aprovacao: string | null;
  data_vencimento: string | null;
  bruto: number | null;
  cliente_pagou: number | null;
  juros_parcelamento: number | null;
  valor_liquido: number | null;
  taxa_hotmart: number | null;
  /** Status aprovado — dinheiro que entrou. */
  pago: boolean;
  /** Boleto gerado / aguardando pagamento. */
  pendente: boolean;
  /** Vencido, cancelado ou estornado — não vira receita. */
  morto: boolean;
}

/** Uma checagem de integridade do financeiro (fn_fin_saude). valor=0/ok=true = sem problema. */
export interface SaudeCheck {
  check_id: string;
  label: string;
  valor: number;
  ok: boolean;
}

/** Oferta HM usada em compras mas ausente do catálogo (fn_fin_ofertas_orfas) — furo I-5. */
export interface OfertaOrfa {
  oferta_codigo: string;
  produto_id: string;
  produto_nome: string;
  compras: number;
  menor: number;
  maior: number;
  parceladas: number;
  primeiro: string;
  ultimo: string;
  exemplo_aluno: string;
}

/**
 * Uma interação do histórico de ativação (comercial), espelhada na ficha do
 * financeiro — fn_fin_historico_ativacao(uuid). Fonte: cs.interacoes.
 * `autor` é texto livre na origem (nome da pessoa, 'sistema' ou 'hotmart'),
 * não é FK — pode vir null. `estagio_de`/`estagio_para` só vêm preenchidos
 * quando tipo === 'mudanca_estagio' (já resolvidos para nome legível).
 */
export interface InteracaoAtivacao {
  id: string;
  quando: string;
  tipo: 'disparo' | 'resposta' | 'nota' | 'mudanca_estagio' | 'sistema';
  canal: string | null;
  descricao: string | null;
  autor: string | null;
  estagio_de: string | null;
  estagio_para: string | null;
}

/** O que o financeiro grava no card (mesmas colunas que a ativação lê). */
export interface Acordo {
  vencimento: string | null;
  acordo: string | null;
  meio: string | null;
  forma: string | null;
  parcelas: number | null;
}

/** As 5 faixas resolvidas pelo SQL (cs.vw_fin_board.faixa) — estágio do funil
 *  comercial. É a coluna do board financeiro. */
export type FaixaFunil = 'sem_tratativa' | 'em_negociacao' | 'acordo_em_curso' | 'quitado' | 'em_risco';

/**
 * Uma linha do board novo (HM + Aurum unificados). Espelha fn_fin_board(text,text)
 * 1:1 — CONFERIDO contra o `returns table` de 20260819d_fn_fin_board.sql
 * (versão aplicada em produção 2026-08-19, com sinal_bruto/saldo_pago_bruto
 * repassados de cs.vw_fin_contas_receber por correção do arquiteto — ver nota
 * de divergência da entrega; a migration local nesta pasta ainda precisa ser
 * sincronizada pelo backend-engineer com o SQL efetivamente aplicado).
 *
 * ATUALIZADO 2026-08-20 (coordenador): cs.vw_fin_board/fn_fin_board ganharam
 * 5 colunas NOVAS ao final do returns table (reuniao_resultado/
 * intencao_pagamento/intencao_pagamento_obs/reuniao_motivo_tipo/
 * reuniao_retomar_em) — desfecho da reunião comercial (0307/0308 no repo da
 * esteira). Migration local ainda não sincronizada (mesma dívida do
 * parágrafo acima); confiar no relato do coordenador até a migration
 * aparecer nesta pasta.
 *
 * Ainda mais enxuto que ContaReceber (fn_fin_contas_receber, o "razão") em:
 * ultima_cobranca_em/cobrancas_total/remarcacoes — custo medido dessas
 * subqueries na RPC legada (ver comentário de 20260819d_fn_fin_board.sql).
 * Ficam só na ficha (fn_fin_ficha, 1 card por vez).
 */
export interface CardBoard {
  origem: 'HM' | 'AURUM';
  contato_hm_id: string;
  comprador_id: string;
  aluno_id: string | null;
  nome: string;
  email: string;
  // documento e telefone NÃO vêm no board: dado pessoal sem consumidor na tela
  // não deve trafegar (LGPD, princípio da necessidade). O card não os exibe —
  // quem precisa deles é a ficha (1 card, sob clique) e o relatório, ambos sob
  // gp_pode_ver_cpf()/mascararDoc. Achado da auditoria de segurança de 19/08.
  turma: string | null;
  turma_origem: string | null;
  canal: string;
  publico: string | null;
  produto: string;
  /** Chave do estágio comercial (cs.estagios.chave) — não o id. */
  estagio_chave: string | null;
  estagio_nome: string | null;
  estagio_aba: string | null;
  vendedor: string | null;
  status_financeiro: StatusFinanceiro;
  /** Faixa por ESTÁGIO DO FUNIL (ver FaixaFunil) — a coluna do board. */
  faixa: FaixaFunil;
  pacote: number | null;
  total_pago_bruto: number | null;
  total_pago_liquido: number | null;
  /** Sinal pago na Hotmart (R$ 300) — junto com saldo_pago_bruto define ehReserva(). */
  sinal_bruto: number | null;
  /** Pago do saldo do pacote (fora o sinal). 0 = nada pago do saldo ainda. */
  saldo_pago_bruto: number;
  saldo_a_pagar: number | null;
  credito: number | null;
  pago_pct: number | null;
  vencimento: string | null;
  dias_atraso: number | null;
  entrou_estagio_em: string | null;
  dias_no_estagio: number | null;
  solicitou_cancelamento: boolean;
  cancelamento_em: string | null;
  cancelamento_efetivado_em: string | null;
  quitado_em: string | null;
  reembolso_em: string | null;
  reembolso_valor: number | null;
  oferta_codigo: string | null;
  oferta_enviada_em: string | null;
  ultimo_pagamento_em: string | null;
  /** AURUM: distingue "não cobrar por decisão" de "sem dado". HM = sempre null. */
  aurum_excecao: boolean | null;
  aurum_excecao_motivo: string | null;
  aurum_rotulo_operador: string | null;
  /** Nome do canal/ação da timeline (cs.hm_evento_janela.nota) — null quando o
   *  pagamento do sinal não caiu em nenhuma janela conhecida (133 de 305 cards). */
  acao_nome: string | null;
  acao_data: string | null;
  // ── Desfecho da reunião (F6/F7/F8, 0307/0308 no repo da esteira) ────────────
  // Estendido em produção (coordenador, 2026-08-20): cs.vw_fin_board e
  // fn_fin_board agora projetam estas 5 colunas AO FINAL do returns table —
  // ordem posicional importa, não reordenar. Custo medido: zero (81,8 ms /
  // 14.335 buffers, 1 buffer A MENOS que antes — o join com contatos_hm já
  // existia, são colunas de projeção pura, sem novo JOIN).
  /** Resultado categórico da reunião comercial (ex.: "Realizada"). 165 de N
   *  cards já trazem valor (medido 2026-08-20). */
  reuniao_resultado: string | null;
  /** Declaração comercial do desfecho — trilha [A] quando 'vai_pagar'. NÃO é
   *  dado de pagamento (irmã de `acordo`). */
  intencao_pagamento: 'vai_pagar' | 'indeciso' | 'nao_vai_pagar' | null;
  /** A observação do que foi combinado na reunião — DIFERENTE de
   *  `obs_comercial` (ContaReceber): aquele é outro campo, sem fonte na RPC
   *  do board (mapeado como null em cardBoardParaContaReceber). Não confundir
   *  os dois. 20 cards já trazem valor (medido 2026-08-20). */
  intencao_pagamento_obs: string | null;
  /** Motivo categorizado da trilha [B] (não prometeu pagar) — lista fechada,
   *  mesmos 5 valores de lib/reuniao-motivos.ts no repo da esteira (NÃO
   *  importar de lá — repos separados, duplicar 5 strings é aceitável).
   *  0 cards hoje (coluna nova da 0307, preenche daqui pra frente). */
  reuniao_motivo_tipo: string | null;
  /** Data em que o comercial disse que retoma o contato — só preenchida na
   *  trilha [B]. Informativo para o financeiro; NÃO é vencimento e não entra
   *  em cobrança (decisão do Marcio: só quem prometeu pagar entra na fila). */
  reuniao_retomar_em: string | null;
}
