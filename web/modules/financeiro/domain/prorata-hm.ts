// Pro rata do HM → Programa (fn_fin_prorata_hm, 20260928d) — funções PURAS.
//
// Regra (decisão do João): crédito = pago no ciclo × meses cheios restantes ÷ 12;
// diferença = valor do Programa (R$ 15.000) − crédito, piso 0. O cálculo é do
// banco; aqui só normaliza números e acha a linha do card aberto na ficha.
import type { BoardHotmart, ProrataHM } from './hotmart';

/** Valor do Programa de Implementação Assistida usado no pro rata (fonte única — telas, repositório e ficha). */
export const VALOR_PROGRAMA_HM = 15000;

/** 'YYYY-MM-DD' de hoje em São Paulo (o banco calcula o ciclo nesse fuso). */
export function hojeSaoPaulo(agora: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(agora);
}

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

/** Início do ciclo do pro rata: vencimento − 12 meses − 60 dias (mesma conta de fn_fin_prorata_hm). */
export function inicioDoCiclo(vencimento: string): string {
  const [y, m, d] = vencimento.slice(0, 10).split('-').map(Number);
  const dt = new Date(Date.UTC(y - 1, m - 1, d));
  // 12 meses antes num dia que não existe (29/02) cai no último dia do mês, como o interval do Postgres
  if (dt.getUTCMonth() !== m - 1) dt.setUTCDate(0);
  dt.setUTCDate(dt.getUTCDate() - 60);
  return dt.toISOString().slice(0, 10);
}

/** Números da conta do pro rata, de qualquer das duas fontes (lista ou diagnóstico). */
export interface ContaProrata {
  pago: number;
  pagamentos: number;
  formas?: string | null;
  vencimento: string | null;
  inicioCiclo: string | null;
  meses: number;
  credito: number;
  valorPrograma: number;
  diferenca: number;
}

const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }).replace(/\s/g, ' ');

/**
 * A frase que diz POR QUE a pessoa paga aquele valor ("ele gastou tanto, por isso vai pagar isso" — João, 27/09).
 * Três casos: sem pagamento no ciclo, sem mês cheio restante, e o caso com crédito.
 */
export function explicarProrata(c: ContaProrata): string {
  const aPagar = brl(c.diferenca);
  if (c.pago <= 0) {
    return `Não há pagamento de HM na Hotmart neste ciclo, então não existe crédito: paga o valor cheio do Programa, ${aPagar}. Se pagou por fora ou com outro e-mail, confirme com a Isabela.`;
  }
  if (c.meses <= 0) {
    return `Pagou ${brl(c.pago)} no HM neste ciclo, mas o acesso não tem mais nenhum mês cheio pela frente, então esse pagamento já foi usado e não vira crédito: paga o valor cheio do Programa, ${aPagar}.`;
  }
  const meses = c.meses === 1 ? '1 mês cheio' : `${c.meses} meses cheios`;
  return `Pagou ${brl(c.pago)} no HM neste ciclo. Como ainda faltam ${meses} de acesso, ${c.meses}/12 desse valor volta como crédito: ${brl(c.credito)}. Por isso paga ${aPagar} para entrar no Programa (${brl(c.valorPrograma)} − ${brl(c.credito)}).`;
}
