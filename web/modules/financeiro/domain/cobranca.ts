// Regras puras de cobrança avançada: envelhecimento (aging), próxima ação da
// régua, e previsão de recebimento. Sem I/O. Datas em ISO 'YYYY-MM-DD'.
import type { ContaReceber, ReguaPasso } from './types';
import { contaMorta } from './financeiro';

// ── Aging (envelhecimento do saldo) ──────────────────────────────────────────

export type AgingBucket = 'sem_prazo' | 'a_vencer' | 'd1_15' | 'd16_30' | 'd31_60' | 'd60_plus';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export const AGING_META: Record<AgingBucket, { label: string; tone: Tone }> = {
  sem_prazo: { label: 'Sem prazo', tone: 'neutral' },
  a_vencer: { label: 'A vencer', tone: 'accent' },
  d1_15: { label: '1–15 dias', tone: 'warning' },
  d16_30: { label: '16–30 dias', tone: 'warning' },
  d31_60: { label: '31–60 dias', tone: 'danger' },
  d60_plus: { label: '60+ dias', tone: 'danger' },
};

export const AGING_ORDEM: AgingBucket[] = ['a_vencer', 'd1_15', 'd16_30', 'd31_60', 'd60_plus', 'sem_prazo'];

/** Faixa de envelhecimento do saldo. Contas quitadas/mortas ficam fora (null). */
export function agingDe(c: ContaReceber): AgingBucket | null {
  if (contaMorta(c) || c.status_financeiro === 'quitado') return null;
  if ((c.saldo_a_pagar ?? 0) <= 0) return null;
  if (!c.vencimento) return 'sem_prazo';
  const d = c.dias_atraso ?? 0;
  if (d <= 0) return 'a_vencer';
  if (d <= 15) return 'd1_15';
  if (d <= 30) return 'd16_30';
  if (d <= 60) return 'd31_60';
  return 'd60_plus';
}

export interface FatiaAging {
  bucket: AgingBucket;
  alunos: number;
  valor: number;
}

/** Distribuição do saldo a receber por faixa de atraso — a foto do risco. */
export function distribuicaoAging(contas: ContaReceber[]): FatiaAging[] {
  const mapa = new Map<AgingBucket, FatiaAging>();
  for (const c of contas) {
    const b = agingDe(c);
    if (!b) continue;
    const f = mapa.get(b) ?? { bucket: b, alunos: 0, valor: 0 };
    f.alunos += 1;
    f.valor += c.saldo_a_pagar ?? 0;
    mapa.set(b, f);
  }
  return AGING_ORDEM.filter((b) => mapa.has(b)).map((b) => mapa.get(b)!);
}

// ── Próxima ação (régua de cobrança) ─────────────────────────────────────────

export type TipoAcao = 'nenhuma' | 'definir_acordo' | 'calcular_valor' | 'cobrar' | 'aguardar';

export interface ProximaAcao {
  tipo: TipoAcao;
  titulo: string;
  /** Data em que a ação passou/passa a ser devida (ISO), quando aplicável. */
  quando: string | null;
  /** True se a ação já deveria ter sido feita (está atrasada). */
  atrasada: boolean;
}

/** Soma dias a uma data ISO sem depender de fuso (opera no calendário puro). */
function addDias(iso: string, dias: number): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  const base = Date.UTC(y, m - 1, d) + dias * 86400000;
  return new Date(base).toISOString().slice(0, 10);
}

/**
 * O que fazer com esta conta agora, segundo a régua. Considera o vencimento
 * combinado, os passos da régua e a última cobrança já registrada.
 */
export function proximaAcao(c: ContaReceber, regua: ReguaPasso[], hojeISO: string): ProximaAcao {
  if (contaMorta(c) || c.status_financeiro === 'quitado') {
    return { tipo: 'nenhuma', titulo: '—', quando: null, atrasada: false };
  }
  if (c.status_financeiro === 'incalculavel') {
    return { tipo: 'calcular_valor', titulo: 'Calcular o valor', quando: null, atrasada: true };
  }
  if (!c.vencimento) {
    return { tipo: 'definir_acordo', titulo: 'Combinar vencimento', quando: null, atrasada: true };
  }

  const venc = c.vencimento.slice(0, 10);
  const ultima = c.ultima_cobranca_em ? c.ultima_cobranca_em.slice(0, 10) : null;
  const passos = regua.filter((p) => p.ativo).sort((a, b) => a.offset_dias - b.offset_dias);

  // Data de cada passo = vencimento + offset. Devidos = já chegaram (<= hoje).
  const comData = passos.map((p) => ({ p, data: addDias(venc, p.offset_dias) }));
  const devidos = comData.filter((x) => x.data <= hojeISO);

  if (devidos.length) {
    const ultimoDevido = devidos[devidos.length - 1];
    // Já cobramos depois que este passo venceu? Então a ação dele está cumprida.
    const cumprido = ultima != null && ultima >= ultimoDevido.data;
    if (!cumprido) {
      return { tipo: 'cobrar', titulo: ultimoDevido.p.titulo, quando: ultimoDevido.data, atrasada: true };
    }
  }
  // Nada devido pendente: aponta o próximo passo futuro, se houver.
  const futuro = comData.find((x) => x.data > hojeISO);
  if (futuro) {
    return { tipo: 'aguardar', titulo: futuro.p.titulo, quando: futuro.data, atrasada: false };
  }
  return { tipo: 'nenhuma', titulo: 'Régua concluída', quando: null, atrasada: false };
}

/** Conta que exige ação de cobrança agora (entra na fila do dia). */
export function precisaAcao(c: ContaReceber, regua: ReguaPasso[], hojeISO: string): boolean {
  const a = proximaAcao(c, regua, hojeISO);
  return a.atrasada && a.tipo !== 'nenhuma';
}

// ── Previsão de recebimento (forecast de caixa) ──────────────────────────────

export interface Forecast {
  /** Vence nos próximos 7 dias (a receber, ainda no prazo). */
  proximos7: number;
  proximos30: number;
  /** Vencido em aberto — em risco, cobrança ativa. */
  emRisco: number;
  /** Sem vencimento combinado — não previsível até virar acordo. */
  semPrazo: number;
}

export function preverRecebimento(contas: ContaReceber[], hojeISO: string): Forecast {
  const d7 = addDias(hojeISO, 7);
  const d30 = addDias(hojeISO, 30);
  const f: Forecast = { proximos7: 0, proximos30: 0, emRisco: 0, semPrazo: 0 };
  for (const c of contas) {
    if (contaMorta(c) || c.status_financeiro === 'quitado') continue;
    const saldo = c.saldo_a_pagar ?? 0;
    if (saldo <= 0) continue;
    if (!c.vencimento) { f.semPrazo += saldo; continue; }
    const venc = c.vencimento.slice(0, 10);
    if (venc < hojeISO) { f.emRisco += saldo; continue; }
    if (venc <= d7) f.proximos7 += saldo;
    if (venc <= d30) f.proximos30 += saldo;
  }
  return f;
}
