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
    // Assinatura HM (20260928d): opcionais no tipo — ausente vira 0 (= sem assinatura).
    assinatura_mensalidades: num(r.assinatura_mensalidades),
    assinatura_valor: num(r.assinatura_valor),
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

/** 'YYYY-MM-DD' → 'MM/YYYY'. Coluna `date` do Postgres: sem fuso, recorte direto. */
export function fmtMesAno(ymd: string | null | undefined): string | null {
  const m = ymd?.match(/^(\d{4})-(\d{2})/);
  return m ? `${m[2]}/${m[1]}` : null;
}

/** Card tem assinatura HM (mensalidades pagas)? Contrato à parte — nunca entra no "pago" do card. */
export function temAssinaturaHM(h: BoardHotmart | null | undefined): h is BoardHotmart {
  return temDadoHotmart(h) && num(h.assinatura_mensalidades) > 0;
}

/** Linha curta do card: "Assinatura HM: 12 × · R$ 23.964 · até 09/2026". null sem assinatura. */
export function linhaAssinaturaHM(h: BoardHotmart | null | undefined, fmtValor: (n: number) => string): string | null {
  if (!temAssinaturaHM(h)) return null;
  const ate = fmtMesAno(h.assinatura_ate);
  return `Assinatura HM: ${num(h.assinatura_mensalidades)} × · ${fmtValor(num(h.assinatura_valor))}${ate ? ` · até ${ate}` : ''}`;
}

/** Dias corridos entre duas datas 'YYYY-MM-DD'. */
function diasEntre(de: string, ate: string): number {
  const d = (s: string) => { const [y, m, dd] = s.slice(0, 10).split('-').map(Number); return Date.UTC(y, m - 1, dd); };
  return Math.round((d(ate) - d(de)) / 86_400_000);
}

const ROTULO_CAT_BOLETO: Record<string, string> = {
  sinal: 'sinal', diferenca: 'saldo', compra_cheia: 'compra cheia', compra_cheia_inferida: 'compra cheia',
  renovacao: 'renovação', reserva: 'reserva', mensalidade: 'mensalidade', desconhecida: 'oferta desconhecida',
};

/**
 * Boleto/Pix gerado e não pago (20260928o): o que é, quanto e há quanto tempo. null sem boleto em aberto.
 * A Hotmart não informa o vencimento — a frase nunca promete data.
 */
export function descreverBoletoAberto(h: BoardHotmart | null | undefined, hojeISO: string, fmtValor: (n: number) => string):
  { curto: string; titulo: string; detalhe: string; dias: number | null } | null {
  if (!h || !h.boleto_aberto_n) return null;
  const pix = h.boleto_aberto_metodo === 'PIX';
  const meio = pix ? 'Pix' : 'Boleto';
  const oque = ROTULO_CAT_BOLETO[h.boleto_aberto_categoria ?? ''] ?? 'pagamento';
  const dias = h.boleto_aberto_em ? diasEntre(h.boleto_aberto_em, hojeISO) : null;
  const quando = dias == null ? '' : dias <= 0 ? 'gerado hoje' : dias === 1 ? 'gerado ontem' : `gerado há ${dias} dias`;
  const valor = fmtValor(num(h.boleto_aberto_valor));
  const n = num(h.boleto_aberto_n);
  return {
    curto: `${meio} em aberto · ${valor}`,
    titulo: `${meio} de ${oque} em aberto: ${valor}${n > 1 ? ` (${n} gerados)` : ''}`,
    detalhe: `${quando}${quando ? '. ' : ''}Ainda não pago na Hotmart. A Hotmart não informa o vencimento.`,
    dias,
  };
}
