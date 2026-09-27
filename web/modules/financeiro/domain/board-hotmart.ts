// Camada "Hotmart" pendurada no board — função PURA, sem I/O e sem React.
//
// Só aviso: nada aqui mexe nos 4 totais do board (domain/totais.ts). Os números
// vêm de fn_fin_board_hotmart (1 linha por card) e são POR PESSOA × família: se a
// pessoa tem 2 cards, os mesmos valores vêm repetidos nos dois. Por isso a soma
// do rodapé conta cada pessoa UMA vez — somar por card dobraria o dinheiro dela.
import type { BoardHotmart } from './hotmart';

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const numOuNull = (v: unknown): number | null => (v == null ? null : num(v));

/** Numeric do Postgres pode chegar como string pelo PostgREST — converte tudo para number. */
export function normalizarBoardHotmart(r: BoardHotmart): BoardHotmart {
  return {
    ...r,
    cards_da_pessoa: num(r.cards_da_pessoa),
    vendas_pagas: num(r.vendas_pagas),
    pago_bruto: num(r.pago_bruto),
    taxa_hotmart: num(r.taxa_hotmart),
    coproducao: num(r.coproducao),
    liquido: num(r.liquido),
    cobrado_cliente: num(r.cobrado_cliente),
    juros: num(r.juros),
    parcelas_max: numOuNull(r.parcelas_max),
    ultimo_pagamento_valor: numOuNull(r.ultimo_pagamento_valor),
    parcelas_devidas: num(r.parcelas_devidas),
    valor_devido: num(r.valor_devido),
    devido_antigo: num(r.devido_antigo),
    estornos: num(r.estornos),
    valor_estornado: num(r.valor_estornado),
    falta_no_board: num(r.falta_no_board),
    valor_falta_no_board: num(r.valor_falta_no_board),
    board_sem_hotmart: num(r.board_sem_hotmart),
  };
}

/** Mapa contato_hm_id → linha normalizada. */
export function indexarBoardHotmart(linhas: BoardHotmart[]): Map<string, BoardHotmart> {
  const mapa = new Map<string, BoardHotmart>();
  for (const l of linhas) mapa.set(l.contato_hm_id, normalizarBoardHotmart(l));
  return mapa;
}

/** Card tem dado da Hotmart para mostrar? Sem linha ou pessoa não achada = não (nunca "R$ 0"). */
export function temDadoHotmart(h: BoardHotmart | null | undefined): h is BoardHotmart {
  return !!h && h.encontrado;
}

export interface TotaisHotmart {
  /** Cards do recorte que têm dado da Hotmart. */
  cardsComDado: number;
  /** Cards do recorte sem dado da Hotmart (pessoa não encontrada ou sem linha). */
  cardsSemDado: number;
  /** Pessoas distintas somadas (cada uma uma vez só). */
  pessoas: number;
  bruto: number;
  taxa: number;
  coproducao: number;
  juros: number;
  cobradoCliente: number;
  liquido: number;
  devido: number;
  parcelasDevidas: number;
  /** Vendas pagas na Hotmart que não estão no board (R$). */
  valorFaltaNoBoard: number;
  /** Cards do recorte marcados como divergentes. */
  cardsDivergentes: number;
}

/**
 * Soma a camada Hotmart dos cards informados, contando cada pessoa UMA vez.
 * Chave de pessoa = origem + pessoa_chave (os valores são por pessoa × família;
 * a mesma pessoa no HM e no Aurum tem números diferentes). Linha encontrada sem
 * pessoa_chave cai na chave do próprio card, para não sumir nem se fundir com outra.
 */
export function somarHotmart(contatoIds: readonly string[], mapa: ReadonlyMap<string, BoardHotmart>): TotaisHotmart {
  const t: TotaisHotmart = {
    cardsComDado: 0, cardsSemDado: 0, pessoas: 0,
    bruto: 0, taxa: 0, coproducao: 0, juros: 0, cobradoCliente: 0, liquido: 0,
    devido: 0, parcelasDevidas: 0, valorFaltaNoBoard: 0, cardsDivergentes: 0,
  };
  const vistas = new Set<string>();
  for (const id of contatoIds) {
    const h = mapa.get(id);
    if (!temDadoHotmart(h)) { t.cardsSemDado += 1; continue; }
    t.cardsComDado += 1;
    if (h.diverge === true) t.cardsDivergentes += 1;
    const chave = `${h.origem}|${h.pessoa_chave ?? `card:${h.contato_hm_id}`}`;
    if (vistas.has(chave)) continue;
    vistas.add(chave);
    t.pessoas += 1;
    t.bruto += num(h.pago_bruto);
    t.taxa += num(h.taxa_hotmart);
    t.coproducao += num(h.coproducao);
    t.juros += num(h.juros);
    t.cobradoCliente += num(h.cobrado_cliente);
    t.liquido += num(h.liquido);
    t.devido += num(h.valor_devido);
    t.parcelasDevidas += num(h.parcelas_devidas);
    t.valorFaltaNoBoard += num(h.valor_falta_no_board);
  }
  return t;
}

/** "à vista" / "até 12x" / null (sem venda paga). */
export function rotuloParcelamento(parcelasMax: number | null): string | null {
  if (parcelasMax == null || parcelasMax <= 0) return null;
  return parcelasMax === 1 ? 'à vista' : `até ${parcelasMax}x`;
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

/**
 * Explicação da divergência em texto de quem não programa. null quando não
 * diverge (ou quando a divergência não se aplica — Aurum vem sempre null).
 */
export function explicarDivergencia(h: BoardHotmart, fmtValor: (n: number) => string): string | null {
  if (h.diverge !== true) return null;
  const partes: string[] = [];
  if (h.falta_no_board > 0) {
    partes.push(
      `${plural(h.falta_no_board, 'venda paga', 'vendas pagas')} na Hotmart (${fmtValor(h.valor_falta_no_board)}) não ${h.falta_no_board === 1 ? 'está lançada' : 'estão lançadas'} no board`,
    );
  }
  if (h.board_sem_hotmart > 0) {
    partes.push(
      `${plural(h.board_sem_hotmart, 'lançamento', 'lançamentos')} do board não ${h.board_sem_hotmart === 1 ? 'tem par' : 'têm par'} na Hotmart (ou foi estornado lá)`,
    );
  }
  if (!partes.length) return 'O board e a Hotmart não batem para esta pessoa.';
  return `${partes.join('; ')}.`;
}
