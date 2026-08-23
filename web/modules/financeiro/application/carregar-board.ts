// Caso de uso: carregar o board de cards + totais do rodapé + timeline de ações.
// Importa só domain + o port do repository — nunca Supabase direto.
import type { CardBoard, ContaReceber, FaixaFunil, ReguaPasso } from '../domain/types';
import { motivoUrgencia, urgencia } from '../domain/board';
import { corStatus, type CorStatus } from '../domain/cor-status';
import { ehReserva } from '../domain/financeiro';
import { calcularTotais, type Totais } from '../domain/totais';
import type { FinanceiroRepository } from './ports';

/**
 * Mapeia CardBoard (fn_fin_board) → ContaReceber (o shape que o domínio
 * board.ts/totais.ts já testa e opera). sinal_bruto e saldo_pago_bruto vêm
 * reais da RPC (corrigido pelo arquiteto em 2026-08-19 — cs.vw_fin_contas_receber
 * já calculava, só não repassava); os demais campos ausentes no board
 * (acordo, parcelas, tags…) entram como null/0 — "não sei", nunca um valor
 * inventado. Ficam completos só na ficha (fn_fin_ficha, 1 card por vez).
 */
export function cardBoardParaContaReceber(c: CardBoard): ContaReceber {
  return {
    contato_hm_id: c.contato_hm_id,
    comprador_id: c.comprador_id,
    aluno_id: c.aluno_id,
    nome: c.nome,
    email: c.email,
    // A RPC do board não devolve telefone/documento (LGPD: dado pessoal sem
    // consumidor na tela não trafega). Entram como null — "não veio", nunca um
    // valor inventado. A ficha carrega o card completo quando alguém clica.
    telefone: null,
    documento: null,
    turma: c.turma,
    turma_origem: c.turma_origem,
    canal: c.canal,
    publico: c.publico,
    tags: null,
    estagio_nome: c.estagio_nome,
    estagio_aba: c.estagio_aba,
    estagio_id: null,
    produto: c.produto,
    vendedor: c.vendedor,
    reuniao_em: null,
    reuniao_resultado: null,
    entrevista_em: null,
    entrevista_resultado: null,
    obs_comercial: null,
    solicitou_cancelamento: c.solicitou_cancelamento,
    sinal_bruto: c.sinal_bruto,
    sinal_liquido: null,
    sinal_taxas: null,
    sinal_pago_em: null,
    sinal_metodo: null,
    sinal_transacao: null,
    saldo_pago_bruto: c.saldo_pago_bruto,
    saldo_pago_liquido: 0,
    saldo_taxas: 0,
    saldo_pago_em: null,
    saldo_metodo: null,
    saldo_lancamentos: 0,
    total_pago_bruto: c.total_pago_bruto,
    total_pago_liquido: c.total_pago_liquido,
    pacote: c.pacote,
    pacote_regra: null,
    divergencia_regra: null,
    credito: c.credito,
    saldo_a_pagar: c.saldo_a_pagar,
    pago_pct: c.pago_pct,
    vencimento: c.vencimento,
    acordo: null,
    pagamento_meio: null,
    pagamento_forma: null,
    pagamento_parcelas: null,
    parcelas_pagas: null,
    parcelas_contratadas: null,
    valor_parcela: null,
    dias_atraso: c.dias_atraso,
    oferta_codigo: c.oferta_codigo,
    oferta_valor: null,
    oferta_link: null,
    oferta_recorrente: null,
    oferta_enviada_em: c.oferta_enviada_em,
    cancelamento_em: c.cancelamento_em,
    cancelamento_motivo: null,
    cancelamento_efetivado_em: c.cancelamento_efetivado_em,
    quitado_em: c.quitado_em,
    reembolso_em: c.reembolso_em,
    reembolso_status: null,
    reembolso_valor: c.reembolso_valor,
    ultimo_pagamento_em: c.ultimo_pagamento_em,
    situacao_ativacao: null,
    status_financeiro: c.status_financeiro,
    ultima_cobranca_em: null,
    cobrancas_total: 0,
    remarcacoes: 0,
  };
}

export interface CardComEfeito {
  conta: ContaReceber;
  origem: CardBoard['origem'];
  /** Coluna do board — estágio do funil comercial (vem do SQL, cs.vw_fin_board.faixa). */
  faixaFunil: FaixaFunil;
  cor: CorStatus;
  urgencia: 0 | 1 | 2 | 3;
  /** Prosa da urgência acima — canal para aria-label/title (F6). Mesma bijeção
   *  de urgencia(): null sse urgencia === 0. Nunca diverge dela (ver board.ts). */
  motivoUrgencia: string | null;
  /** Pagou só o sinal (R$ 300), nada do saldo — esperado mais frágil, marca própria no card. */
  reserva: boolean;
  acaoNome: string | null;
  acaoData: string | null;
  /** Dias parados no estágio atual (cs.vw_fin_board.dias_no_estagio) — sinal de
   *  cobrança de posição pro comercial. Null = sem `entrou_estagio_em` gravado
   *  (16 de 305 cards) — "não sabemos", nunca vira 0 no card. */
  diasNoEstagio: number | null;
}

export const FAIXAS_FUNIL: { chave: FaixaFunil; rotulo: string }[] = [
  { chave: 'sem_tratativa', rotulo: 'Sem tratativa' },
  { chave: 'em_negociacao', rotulo: 'Em negociação' },
  { chave: 'acordo_em_curso', rotulo: 'Acordo em curso' },
  { chave: 'quitado', rotulo: 'Quitado' },
  { chave: 'em_risco', rotulo: 'Em risco' },
];

export interface BoardCarregado {
  /** Todos os cards, já com faixa/cor/urgência/reserva calculadas — para filtro no cliente. */
  cards: CardComEfeito[];
  /** Cards agrupados nas 5 faixas do funil (colunas do board), na ordem de FAIXAS_FUNIL. */
  colunas: Record<FaixaFunil, CardComEfeito[]>;
  /** Totais do rodapé sobre TODOS os cards (recalcular sobre `visiveis` ao filtrar).
   *  Reserva ENTRA em esperado/naRua (é dinheiro contratado) — só ganha marca visual no card. */
  totais: Totais;
}

/**
 * Carrega o board completo: busca fn_fin_board, mapeia para o domínio e
 * decora cada card com faixa/cor/urgência/reserva — puro a partir daqui, sem
 * nova query ao filtrar no cliente.
 */
export async function carregarBoard(
  repo: FinanceiroRepository,
  regua: ReguaPasso[],
  hojeISO: string,
  turma: string | null = null,
  produto: string | null = null,
): Promise<BoardCarregado> {
  const brutos = await repo.loadBoard(turma, produto);

  const cards: CardComEfeito[] = brutos.map((bruto) => {
    const conta = cardBoardParaContaReceber(bruto);
    return {
      conta,
      origem: bruto.origem,
      faixaFunil: bruto.faixa,
      cor: corStatus(conta.status_financeiro),
      urgencia: urgencia(conta, regua, hojeISO),
      motivoUrgencia: motivoUrgencia(conta, regua, hojeISO),
      reserva: ehReserva(conta),
      acaoNome: bruto.acao_nome,
      acaoData: bruto.acao_data,
      diasNoEstagio: bruto.dias_no_estagio,
    };
  });

  const colunas = Object.fromEntries(
    FAIXAS_FUNIL.map(({ chave }) => [
      chave,
      cards.filter((c) => c.faixaFunil === chave).sort((a, b) => (b.conta.saldo_a_pagar ?? 0) - (a.conta.saldo_a_pagar ?? 0)),
    ]),
  ) as Record<FaixaFunil, CardComEfeito[]>;

  return { cards, colunas, totais: calcularTotais(cards.map((c) => c.conta)) };
}
