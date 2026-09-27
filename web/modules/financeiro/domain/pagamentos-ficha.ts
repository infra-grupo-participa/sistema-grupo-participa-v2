// Pagamentos da ficha em UMA lista (pedido do João, 27/09: "o histórico financeiro está muito desorganizado").
// Antes eram três blocos que repetiam a mesma venda: lançamentos do board, compras do webhook e o extrato da API.
// Agora: cada transação da Hotmart (a fonte oficial) aparece uma vez, marcada se está ou não no board; lançamento do
// board sem transação (Pix manual, acordo) entra também, marcado "só no board". Função PURA.
import type { Lancamento } from './types';
import type { TransacaoHotmart } from './hotmart';

export type FontePagamento = 'hotmart_e_board' | 'so_hotmart' | 'so_board';

export interface PagamentoFicha {
  chave: string;
  /** Data do pagamento (aprovação) ou, sem ela, do pedido. 'YYYY-MM-DD…' */
  data: string | null;
  grupo: TransacaoHotmart['grupo'];
  valor: number;
  liquido: number | null;
  produto: string | null;
  oferta: string | null;
  /** Categoria do board (sinal, diferenca, compra_cheia…) quando o lançamento existe. */
  categoriaBoard: string | null;
  metodo: string | null;
  parcelas: number | null;
  recorrencia: number | null;
  fonte: FontePagamento;
  obs: string | null;
}

const n = (v: unknown): number => {
  const x = Number(v);
  return Number.isFinite(x) ? x : 0;
};

export function juntarPagamentos(board: Lancamento[], hotmart: TransacaoHotmart[]): PagamentoFicha[] {
  const porTransacao = new Map(board.filter((l) => l.transacao).map((l) => [l.transacao as string, l]));
  const usados = new Set<string>();
  const saida: PagamentoFicha[] = hotmart.map((t) => {
    const l = porTransacao.get(t.transacao);
    if (l) usados.add(l.id);
    return {
      chave: t.transacao,
      data: t.aprovado_em ?? t.pedido_em,
      grupo: t.grupo,
      valor: n(t.valor_oferta),
      liquido: t.liquido != null ? n(t.liquido) : null,
      produto: t.produto,
      oferta: t.oferta_codigo,
      categoriaBoard: l?.categoria ?? null,
      metodo: t.metodo,
      parcelas: t.parcelas,
      recorrencia: t.recorrencia,
      fonte: l ? 'hotmart_e_board' : 'so_hotmart',
      obs: l?.obs ?? null,
    };
  });
  for (const l of board) {
    if (usados.has(l.id)) continue;
    saida.push({
      chave: `board:${l.id}`,
      data: l.pago_em,
      grupo: 'pago',
      valor: n(l.valor_bruto),
      liquido: l.valor_liquido != null ? n(l.valor_liquido) : null,
      produto: null,
      oferta: l.oferta_codigo,
      categoriaBoard: l.categoria,
      metodo: l.metodo_pagamento,
      parcelas: null,
      recorrencia: l.parcela,
      fonte: 'so_board',
      obs: l.obs,
    });
  }
  return saida.sort((a, b) => (b.data ?? '').localeCompare(a.data ?? ''));
}

/** Totais da lista: o que foi pago (Hotmart ou board) e quanto disso o board não registra. */
export function resumirPagamentos(ps: PagamentoFicha[]) {
  const pagos = ps.filter((p) => p.grupo === 'pago');
  return {
    pagos: pagos.length,
    valorPago: pagos.reduce((s, p) => s + p.valor, 0),
    foraDoBoard: pagos.filter((p) => p.fonte === 'so_hotmart').length,
    valorForaDoBoard: pagos.filter((p) => p.fonte === 'so_hotmart').reduce((s, p) => s + p.valor, 0),
    tentativas: ps.filter((p) => p.grupo !== 'pago' && p.grupo !== 'estornado').length,
    estornos: ps.filter((p) => p.grupo === 'estornado').length,
  };
}
