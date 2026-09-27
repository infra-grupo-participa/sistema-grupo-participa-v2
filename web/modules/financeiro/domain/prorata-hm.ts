// Pro rata do HM → Programa (fn_fin_prorata_hm, 20260928d) — funções PURAS.
//
// Regra (decisão do João): crédito = pago no ciclo × meses cheios restantes ÷ 12;
// diferença = valor do Programa (R$ 15.000) − crédito, piso 0. O cálculo é do
// banco; aqui só normaliza números e acha a linha do card aberto na ficha.
import type { BoardHotmart, ProrataHM } from './hotmart';

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

/** Numeric do Postgres pode chegar como string pelo PostgREST. */
export function normalizarProrataHM(r: ProrataHM): ProrataHM {
  return {
    ...r,
    meses_restantes: num(r.meses_restantes),
    pago_no_ciclo: num(r.pago_no_ciclo),
    pagamentos_no_ciclo: num(r.pagamentos_no_ciclo),
    credito: num(r.credito),
    diferenca: num(r.diferenca),
  };
}

/**
 * Linha de pro rata do card. 1º pelo contato_hm_id (o card HM que a função
 * escolheu: maior saldo da pessoa); senão pela pessoa — as duas funções
 * devolvem fin.chave_opaca(fin.identidade.pessoa_chave), então a mesma pessoa
 * com 2 cards HM acha a linha nos dois. Só card HM: pro rata é do HM.
 */
export function prorataDoCard(
  linhas: readonly ProrataHM[], contatoHmId: string, hm: BoardHotmart | null | undefined,
): ProrataHM | null {
  const porCard = linhas.find((l) => l.contato_hm_id === contatoHmId);
  if (porCard) return porCard;
  if (hm?.origem !== 'HM' || !hm.pessoa_chave) return null;
  return linhas.find((l) => l.pessoa_chave === hm.pessoa_chave) ?? null;
}
