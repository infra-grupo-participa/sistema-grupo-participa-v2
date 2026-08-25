// Faixa de prazo de pagamento — o 3º eixo do board financeiro (F6, 0307/0308
// no repo da esteira: "Reunião Finalizada exige prazo de pagamento").
//
// Já existem DOIS eixos válidos e paralelos, documentados em ./types.ts
// (FaixaFunil) e ./board.ts (FAIXAS/faixaDe — obstáculo de recebimento):
//   1. FaixaFunil    — estágio do funil comercial (vem do SQL, cs.vw_fin_board.faixa)
//   2. FaixaChave    — obstáculo de recebimento (domínio, testado, board.ts)
// Este é o 3º: prazo de pagamento (vencido / vence em 7 dias / a vencer /
// sem data) — três é o limite antes de virar ruído (não introduzir um 4º sem
// necessidade medida). Puro, sem I/O — mesmo padrão de agingDe() (./cobranca.ts),
// que resolve uma pergunta vizinha (envelhecimento em 6 baldes) com o mesmo
// formato de função. A diferença de agingDe(): esta faixa é para o SELETOR do
// board (F7), não para outro agrupamento simultâneo.
import type { ContaReceber } from './types';
import { contaMorta, saldoEfetivo } from './financeiro';

export type FaixaPrazo = 'vencidas' | 'vencem_7d' | 'a_vencer' | 'sem_data';

type Tone = 'neutral' | 'accent' | 'warning' | 'danger';

export const FAIXA_PRAZO_META: Record<FaixaPrazo, { label: string; descricao: string; tone: Tone }> = {
  vencidas: { label: 'Vencidas', descricao: 'Vencimento combinado já passou.', tone: 'danger' },
  vencem_7d: { label: 'Vencem em 7 dias', descricao: 'Vencimento combinado nos próximos 7 dias.', tone: 'warning' },
  a_vencer: { label: 'A vencer', descricao: 'Vencimento combinado além de 7 dias.', tone: 'accent' },
  sem_data: { label: 'Sem data', descricao: 'Sem vencimento combinado com o financeiro.', tone: 'neutral' },
};

export const FAIXAS_PRAZO_ORDEM: FaixaPrazo[] = ['vencidas', 'vencem_7d', 'a_vencer', 'sem_data'];

/**
 * Faixa de prazo de uma conta. `null` = conta morta (cancelada/reembolsada)
 * ou quitada sem saldo residual (tolerância de centavos) — mesmo contrato de
 * agingDe(): fora do funil de cobrança, não entra em NENHUMA faixa de prazo.
 *
 * `hojeISO` é injetado pelo chamador (mesma disciplina de proximaAcao()/
 * preverRecebimento() em ./cobranca.ts) — função pura não lê relógio.
 */
export function faixaPrazoDe(c: ContaReceber, hojeISO: string): FaixaPrazo | null {
  if (contaMorta(c) || c.status_financeiro === 'quitado') return null;
  if (saldoEfetivo(c) <= 0) return null;
  if (!c.vencimento) return 'sem_data';

  const venc = c.vencimento.slice(0, 10);
  if (venc < hojeISO) return 'vencidas';

  const [y, m, d] = hojeISO.split('-').map(Number);
  const d7 = new Date(Date.UTC(y, m - 1, d + 7)).toISOString().slice(0, 10);
  if (venc <= d7) return 'vencem_7d';

  return 'a_vencer';
}

export interface FatiaPrazo {
  faixa: FaixaPrazo;
  alunos: number;
  valor: number;
}

/** Agrupa as contas nas 4 faixas de prazo, na ordem canônica. Mesmo formato
 *  de distribuicaoAging() (./cobranca.ts) — soma alunos e saldoEfetivo. */
export function distribuicaoPrazo(contas: ContaReceber[], hojeISO: string): FatiaPrazo[] {
  const mapa = new Map<FaixaPrazo, FatiaPrazo>();
  for (const c of contas) {
    const f = faixaPrazoDe(c, hojeISO);
    if (!f) continue;
    const fatia = mapa.get(f) ?? { faixa: f, alunos: 0, valor: 0 };
    fatia.alunos += 1;
    fatia.valor += saldoEfetivo(c);
    mapa.set(f, fatia);
  }
  return FAIXAS_PRAZO_ORDEM.filter((f) => mapa.has(f)).map((f) => mapa.get(f)!);
}

/** Agrupa as contas por faixa de prazo — para o SELETOR do board (F7), nunca
 *  como agrupamento simultâneo ao FaixaFunil/FaixaChave existentes. */
export function agruparPorFaixaPrazo(contas: ContaReceber[], hojeISO: string): Record<FaixaPrazo, ContaReceber[]> {
  const grupos = Object.fromEntries(FAIXAS_PRAZO_ORDEM.map((f) => [f, [] as ContaReceber[]])) as Record<
    FaixaPrazo,
    ContaReceber[]
  >;
  for (const c of contas) {
    const f = faixaPrazoDe(c, hojeISO);
    if (f) grupos[f].push(c);
  }
  for (const f of Object.keys(grupos) as FaixaPrazo[]) {
    grupos[f].sort((a, b) => (b.saldo_a_pagar ?? 0) - (a.saldo_a_pagar ?? 0));
  }
  return grupos;
}
