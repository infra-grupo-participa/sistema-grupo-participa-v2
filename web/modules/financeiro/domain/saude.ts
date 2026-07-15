// Traduz números em CONDIÇÃO (bom / atenção / crítico) — a camada de leitura
// visual do financeiro. Regras puras e testáveis; a UI só pinta o resultado.
// Thresholds ancorados em benchmarks de contas a receber (aging 60+ saudável < 10%).
import type { ContaReceber, Meta } from './types';
import { resumir } from './financeiro';
import { distribuicaoAging } from './cobranca';

export type Condicao = 'boa' | 'atencao' | 'critica' | 'neutra';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export const CONDICAO_META: Record<Condicao, { label: string; tone: Tone; icon: string }> = {
  boa: { label: 'Saudável', tone: 'success', icon: 'check-circle' },
  atencao: { label: 'Atenção', tone: 'warning', icon: 'alert' },
  critica: { label: 'Em risco', tone: 'danger', icon: 'alert' },
  neutra: { label: 'Sem dados', tone: 'neutral', icon: 'circle' },
};

const RANK: Record<Condicao, number> = { boa: 0, neutra: 1, atencao: 2, critica: 3 };
/** A pior condição vence — usado para consolidar sinais num estado só. */
export function pior(a: Condicao, b: Condicao): Condicao {
  return RANK[a] >= RANK[b] ? a : b;
}

// ── Indicadores individuais ──────────────────────────────────────────────────

export interface Indicador {
  condicao: Condicao;
  /** 0–100 para a barra/anel, quando faz sentido. */
  pct: number | null;
  /** Frase curta do porquê da condição. */
  nota: string;
}

/**
 * Progresso da arrecadação/cobertura contra a meta. No começo da turma a
 * cobertura é naturalmente baixa, então isto é PROGRESSO (barra), não alarme —
 * a condição só fica crítica se a meta existe e o realizado está muito abaixo.
 */
export function progressoMeta(realizadoPct: number, metaPct: number | null): Indicador {
  if (metaPct == null || metaPct <= 0) {
    return { condicao: 'neutra', pct: null, nota: 'sem meta definida' };
  }
  const razao = realizadoPct / metaPct; // 1 = na meta
  const pct = Math.min(100, Math.round(razao * 100));
  const condicao: Condicao = razao >= 0.9 ? 'boa' : razao >= 0.5 ? 'atencao' : 'critica';
  return { condicao, pct, nota: `${realizadoPct.toFixed(1)}% de ${metaPct}% da meta` };
}

/** Parcela do saldo a receber parada há 60+ dias. Benchmark: saudável < 10%. */
export function condicaoAging(contas: ContaReceber[]): Indicador {
  const dist = distribuicaoAging(contas);
  const total = dist.reduce((a, f) => a + f.valor, 0);
  if (total <= 0) return { condicao: 'boa', pct: 0, nota: 'nada em aberto' };
  const velho = dist.filter((f) => f.bucket === 'd31_60' || f.bucket === 'd60_plus').reduce((a, f) => a + f.valor, 0);
  const pct = (velho / total) * 100;
  const condicao: Condicao = pct < 10 ? 'boa' : pct <= 20 ? 'atencao' : 'critica';
  return { condicao, pct: Math.round(pct), nota: `${pct.toFixed(0)}% do saldo com 30+ dias de atraso` };
}

/** Previsibilidade: quanto do a-receber ainda não tem vencimento combinado. */
export function condicaoPrevisibilidade(contas: ContaReceber[]): Indicador {
  const r = resumir(contas);
  const semPrazo = contas
    .filter((c) => c.status_financeiro === 'sem_acordo' || c.status_financeiro === 'incalculavel')
    .reduce((a, c) => a + (c.saldo_a_pagar ?? 0), 0);
  if (r.aReceber <= 0) return { condicao: 'boa', pct: 0, nota: 'nada a receber' };
  const pct = (semPrazo / r.aReceber) * 100;
  const condicao: Condicao = pct < 25 ? 'boa' : pct <= 60 ? 'atencao' : 'critica';
  return { condicao, pct: Math.round(pct), nota: `${pct.toFixed(0)}% do a-receber sem data combinada` };
}

/** Inadimplência ativa: há saldo vencido em aberto? */
export function condicaoVencido(contas: ContaReceber[]): Indicador {
  const r = resumir(contas);
  if (r.vencido <= 0) return { condicao: 'boa', pct: 0, nota: 'nada vencido' };
  const pct = r.aReceber > 0 ? (r.vencido / r.aReceber) * 100 : 0;
  const condicao: Condicao = pct < 5 ? 'atencao' : 'critica';
  return { condicao, pct: Math.round(pct), nota: `${r.vencidoQtd} conta(s) vencida(s) a cobrar` };
}

// ── Estado consolidado da turma ──────────────────────────────────────────────

export interface EstadoTurma {
  condicao: Condicao;
  titulo: string;
  /** O motivo dominante — o que mais pesa contra a saúde agora. */
  motivo: string;
}

/**
 * A pergunta "qual a condição desta turma?" respondida numa linha. Escolhe o
 * sinal mais grave e o transforma em ação. Ordem = prioridade de atenção.
 */
export function estadoTurma(contas: ContaReceber[]): EstadoTurma {
  if (!contas.length) return { condicao: 'neutra', titulo: 'Sem dados', motivo: 'nenhuma conta nesta turma' };

  const aging = condicaoAging(contas);
  const venc = condicaoVencido(contas);
  const prev = condicaoPrevisibilidade(contas);

  // Prioriza dinheiro velho (mais difícil de recuperar), depois vencido, depois previsibilidade.
  if (aging.condicao === 'critica') return { condicao: 'critica', titulo: 'Em risco', motivo: aging.nota };
  if (venc.condicao === 'critica') return { condicao: 'critica', titulo: 'Em risco', motivo: venc.nota };
  if (prev.condicao === 'critica') return { condicao: 'atencao', titulo: 'Atenção', motivo: prev.nota };
  if (venc.condicao === 'atencao') return { condicao: 'atencao', titulo: 'Atenção', motivo: venc.nota };
  if (prev.condicao === 'atencao') return { condicao: 'atencao', titulo: 'Atenção', motivo: prev.nota };
  return { condicao: 'boa', titulo: 'Saudável', motivo: 'em dia, sem saldo velho nem vencidos' };
}

// ── Meta vs realizado (bullet) ───────────────────────────────────────────────

export interface MetaVsReal {
  arrecadacao: { realizado: number; meta: number | null; ind: Indicador };
  cobertura: { realizado: number; meta: number | null; ind: Indicador };
  /** Dias até o fechamento da turma (negativo = já passou). Null se sem data. */
  diasParaFechar: number | null;
}

function diasEntre(hojeISO: string, alvoISO: string): number {
  const p = (s: string) => { const [y, m, d] = s.slice(0, 10).split('-').map(Number); return Date.UTC(y, m - 1, d); };
  return Math.round((p(alvoISO) - p(hojeISO)) / 86400000);
}

export function metaVsReal(contas: ContaReceber[], meta: Meta | null, hojeISO: string): MetaVsReal {
  const r = resumir(contas);
  const metaArr = meta?.meta_arrecadacao ?? null;
  const metaCob = meta?.meta_cobertura_pct ?? null;
  return {
    arrecadacao: {
      realizado: r.recebidoBruto,
      meta: metaArr,
      ind: progressoMeta(metaArr ? (r.recebidoBruto / metaArr) * 100 : 0, metaArr ? 100 : null),
    },
    cobertura: {
      realizado: r.cobertura,
      meta: metaCob,
      ind: progressoMeta(r.cobertura, metaCob),
    },
    diasParaFechar: meta?.data_fechamento ? diasEntre(hojeISO, meta.data_fechamento) : null,
  };
}
