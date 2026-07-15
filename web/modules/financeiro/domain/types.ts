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

/** O que o financeiro grava no card (mesmas colunas que a ativação lê). */
export interface Acordo {
  vencimento: string | null;
  acordo: string | null;
  meio: string | null;
  forma: string | null;
  parcelas: number | null;
}
