// Os 4 totais do rodapé do board. Sem I/O.
//
// Regra dura: NUNCA usar status_financeiro como fonte de valor — só fatos
// monetários e o eixo vivo/morto (contaMorta). Motivo medido: 85 contas têm
// status='quitado' COM saldo_a_pagar > 0 (R$ 231.637,57), porque o CASE da
// view põe quitado_em IS NOT NULL antes de checar saldo. Se EM CASA usasse
// status e NA RUA usasse saldo, essas 85 entrariam nos dois e o rodapé
// mentiria em R$ 231 mil. A fonte de valor é sempre total_pago_bruto /
// saldoEfetivo() / reembolso_valor — nunca o rótulo do status.
import type { ContaReceber } from './types';
import { contaMorta, saldoEfetivo, ehReserva, segundaMetadeCondicional } from './financeiro';

export interface Totais {
  /** Σ total_pago_bruto sobre TODAS as contas (inclusive mortas) — o que já entrou. */
  emCasa: number;
  /** Mesmo universo de emCasa, em líquido (bruto − taxas da Hotmart). Campo secundário informativo. */
  emCasaLiquido: number;
  /** Σ saldoEfetivo sobre vivas (!contaMorta) — o que ainda falta receber de quem segue no jogo. */
  naRua: number;
  /** Σ saldoEfetivo sobre mortas + o que a pessoa pagou e voltou — dinheiro que não vai entrar. */
  perda: number;
  /** Quebra da perda: o que saiu do caixa (devolvido) vs. o que nunca vai entrar (saldo morto). */
  perdaDetalhe: { devolvido: number; naoRealizado: number };
  /** emCasa + naRua. Nunca inclui a 2ª metade condicional (sem lastro de marco). */
  esperado: number;
  /** Contas com saldo_a_pagar NULL (ex.: Aurum com exceção) — "não sabemos", não é zero. */
  semValorDefinido: number;
  /** Quantas das contas em NA RUA são reserva de vaga (pagou só o sinal). Contagem informativa, não some do total. */
  reservas: number;
  /** 2ª metade do honorário — condicional ao marco de faturamento do parceiro. Fora dos 4 totais. */
  segundaMetade: { valor: number; parceiros: number };
}

/**
 * Calcula os 4 totais do rodapé. Lista vazia devolve tudo zerado, mas isso é
 * distinguível de "tudo pago": nenhum outro campo (reservas, semValorDefinido)
 * finge ter varrido nada — são 0 porque não há contas, não porque a saúde
 * financeira está OK. (Lição registrada no commit 0814910: `[].every()` é
 * `true` — lista vazia não pode afirmar saúde nem sucesso. Aqui a distinção
 * cabe a quem consome Totais: leia junto o total de contas antes de exibir
 * "tudo em dia".)
 */
export function calcularTotais(contas: ContaReceber[]): Totais {
  let emCasa = 0;
  let emCasaLiquido = 0;
  let naRua = 0;
  let naoRealizado = 0;
  let devolvido = 0;
  let semValorDefinido = 0;
  let reservas = 0;

  for (const c of contas) {
    // EM CASA: bruto pago por TODOS, mortos inclusive — o que pagaram é real,
    // independe de a conta seguir viva.
    emCasa += c.total_pago_bruto ?? 0;
    emCasaLiquido += c.total_pago_liquido ?? 0;

    const morta = contaMorta(c);

    if (morta) {
      // PERDA tem duas parcelas de natureza distinta:
      //   naoRealizado = saldo que deixou de ser perseguível (nunca vai entrar)
      //   devolvido    = dinheiro que saiu do caixa de volta para o aluno
      //
      // O devolvido NÃO usa reembolso_valor: essa coluna vem de
      // sum(compras.preco) das compras REFUNDED/CHARGEBACK/PROTEST, e
      // `compras.preco` em oferta parcelada/recorrente guarda a PARCELA, não o
      // total (invariante I-1) — a perda sairia subestimada. O teto real do que
      // pode ter voltado é o que a pessoa efetivamente pagou, e esse número o
      // razão já tem correto em total_pago_bruto.
      naoRealizado += saldoEfetivo(c);
      if (c.reembolso_em != null) devolvido += c.total_pago_bruto ?? 0;
      continue; // conta morta nunca entra em NA RUA.
    }

    // saldo_a_pagar NULL é "não sabemos", nunca vira 0 silenciosamente na soma.
    if (c.saldo_a_pagar == null) {
      semValorDefinido += 1;
      continue;
    }

    // NA RUA: vivas, inclusive reserva de vaga — é dinheiro contratado.
    naRua += saldoEfetivo(c);
    if (ehReserva(c)) reservas += 1;
  }

  return {
    emCasa,
    emCasaLiquido,
    naRua,
    perda: naoRealizado + devolvido,
    perdaDetalhe: { devolvido, naoRealizado },
    esperado: emCasa + naRua,
    semValorDefinido,
    reservas,
    segundaMetade: segundaMetadeCondicional(contas),
  };
}
