// Alerta "boleto do HM cheio com contrato já em curso" — função PURA, sem I/O e sem React.
//
// Caso que originou (29/09, Marcio): HT30 — sinal R$ 697 pago, pacote R$ 15.000, saldo R$ 14.303 — e um boleto
// da oferta HM CHEIO de R$ 15.000 em aberto. A oferta cheia não desconta o que já foi pago: se a pessoa pagar,
// paga R$ 697 a mais. O certo é o link do saldo (R$ 14.303).
//
// Regra aprovada: dispara quando há boleto/Pix em aberto com categoria de catálogo 'compra_cheia' E o card já tem
// contrato (sinal_bruto > 0 OU (pacote > 0 E total_pago_bruto > 0)). Só leitura: não muda nenhum valor do board.
//
// Ajuste 29/09 (João, medido em produção: 3 cards acendiam, 2 falsos): com pacote > 0, só dispara se pagar aquele
// boleto PASSA do pacote (aMais = total_pago_bruto + boleto − pacote > 0). Os falsos eram a PARCELA da própria compra
// cheia parcelada (pacote 15.000, pago 2.552,28, boleto compra_cheia 1.276,14 → −11.171,58: não passa). Sem pacote
// (só sinal) não há conta a fazer: mantém a regra original.
// O catálogo de ofertas (hm_product_catalog) não está carregado no board — por isso o texto não cita código de
// oferta de saldo; pede ao comercial o link (nenhuma query nova para isso).
import type { BoletoAberto } from './hotmart';

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

export interface ContratoParaAlerta {
  sinal_bruto: number | null;
  pacote: number | null;
  total_pago_bruto: number | null;
  saldo_a_pagar: number | null;
}

export interface AlertaCompraCheia {
  /** Valor do boleto cheio considerado (o mais recente dos de categoria compra_cheia). */
  boleto: number;
  /** total_pago_bruto + boleto − pacote (sempre > 0 quando há pacote). null quando o card não tem pacote. */
  aMais: number | null;
  /** saldo_a_pagar do card. null quando o card não tem saldo calculado. */
  saldo: number | null;
  /** Selo do card (curto). */
  curto: string;
  /** Texto completo (ficha e title do selo). */
  texto: string;
}

/** Card já tem contrato em curso? (sinal pago, ou pacote definido com algo pago.) */
export function temContrato(c: ContratoParaAlerta): boolean {
  return num(c.sinal_bruto) > 0 || (num(c.pacote) > 0 && num(c.total_pago_bruto) > 0);
}

export function alertaCompraCheia(
  c: ContratoParaAlerta,
  boletos: readonly BoletoAberto[] | null | undefined,
  fmtValor: (n: number) => string,
): AlertaCompraCheia | null {
  if (!temContrato(c)) return null;
  // Lista vem mais recente primeiro (z76): o 1º compra_cheia é o que a pessoa acabou de gerar.
  const cheio = (boletos ?? []).find((b) => b.categoria === 'compra_cheia');
  if (!cheio) return null;

  const boleto = num(cheio.valor);
  const pago = num(c.total_pago_bruto);
  const pacote = num(c.pacote);
  const conta = pago + boleto - pacote;
  // Com pacote: boleto que não passa do pacote é parcela/pagamento normal, não compra em dobro.
  if (pacote > 0 && conta <= 0) return null;
  const aMais = pacote > 0 ? conta : null;
  const saldo = c.saldo_a_pagar != null && num(c.saldo_a_pagar) > 0 ? num(c.saldo_a_pagar) : null;

  const meio = cheio.metodo === 'PIX' ? 'Pix' : 'Boleto';
  const efeito = aMais != null ? `: se pagar, paga ${fmtValor(aMais)} a mais` : ` (${fmtValor(pago)})`;
  const acao = saldo != null
    ? `Mande o link do saldo de ${fmtValor(saldo)}: peça ao comercial um link do saldo nesse valor.`
    : 'Peça ao comercial um link do saldo.';
  return {
    boleto,
    aMais,
    saldo,
    curto: aMais != null ? `${meio} cheio · ${fmtValor(aMais)} a mais` : `${meio} do HM cheio`,
    texto: `${meio} do HM cheio não desconta o que já foi pago${efeito}. ${acao}`,
  };
}
