// Métricas do Dashboard da Base de Alunos — puras, client-side sobre os alunos carregados.
// Porta da spec docs/specs/dashboard-indicadores.md (Opção A: dado limpo do acervo).
import { NRANK } from './aluno-360';
import type { Aluno360 } from './aluno-360';
import { nivelLabel } from '@/shared/domain/nivel-resultado';

export type DashView = 'alunos' | 'socios';
export interface DashFiltros {
  nivel?: string;
  estado?: string;
  turma?: string;
}
const ATIVO = new Set(['renovado', 'vigente']);

/** Aplica view (alunos/sócios) + filtros do dashboard. */
export function applyDashFilters(alunos: Aluno360[], view: DashView, f: DashFiltros = {}): Aluno360[] {
  return alunos.filter((a) => {
    if (view === 'socios' && !a.eh_socio) return false;
    if (f.nivel && a.nivel_resultado !== f.nivel) return false;
    if (f.estado && String(a.estado ?? '').toUpperCase() !== f.estado) return false;
    if (f.turma && a.turma_codigo !== f.turma) return false;
    return true;
  });
}

export interface Distribuicao {
  key: string;
  label: string;
  count: number;
  color?: string;
}

export interface AlunosMetrics {
  total: number;
  ativos: number;
  pctAtivos: number;
  ht: number;
  hm: number;
  placa: number;
  depoimento: number;
  aurum: number;
  socios: number;
  porNivel: Distribuicao[];
  porEspaco: Distribuicao[];
  porEstado: Distribuicao[];
  porAno: Distribuicao[];
  porTurma: Distribuicao[];
}

/** Matriz turma × nível (heat). Linhas = turmas (top), colunas = níveis presentes. */
export interface TurmaNivelMatrix {
  turmas: string[];
  niveis: { key: string; label: string; color: string }[];
  cells: Record<string, Record<string, number>>;
  max: number;
}

export function computeTurmaNivelMatrix(alunos: Aluno360[], topTurmas = 12): TurmaNivelMatrix {
  const niveisPresentes = (Object.keys(NRANK) as string[])
    .sort((a, b) => NRANK[b] - NRANK[a])
    .filter((k) => alunos.some((a) => a.nivel_resultado === k))
    .map((key) => ({ key, label: nivelLabel(key), color: NIVEL_COLOR[key] || 'var(--nivel-base)' }));

  const turmaCounts = new Map<string, number>();
  for (const a of alunos) if (a.turma_codigo) turmaCounts.set(a.turma_codigo, (turmaCounts.get(a.turma_codigo) ?? 0) + 1);
  const turmas = Array.from(turmaCounts.entries())
    .sort((x, y) => y[1] - x[1])
    .slice(0, topTurmas)
    .map(([t]) => t);

  const cells: Record<string, Record<string, number>> = {};
  let max = 0;
  for (const t of turmas) {
    cells[t] = {};
    for (const n of niveisPresentes) {
      const c = alunos.filter((a) => a.turma_codigo === t && a.nivel_resultado === n.key).length;
      cells[t][n.key] = c;
      if (c > max) max = c;
    }
  }
  return { turmas, niveis: niveisPresentes, cells, max };
}

const NIVEL_COLOR: Record<string, string> = {
  ouro: 'var(--nivel-ouro)',
  platina: 'var(--nivel-platina)',
  diamante: 'var(--nivel-diamante)',
  diamante_vermelho: 'var(--nivel-diamante-vermelho)',
};

function tally(rows: Aluno360[], keyFn: (a: Aluno360) => string | null, labelFn?: (k: string) => string): Distribuicao[] {
  const map = new Map<string, number>();
  for (const a of rows) {
    const k = keyFn(a) ?? '__none__';
    map.set(k, (map.get(k) ?? 0) + 1);
  }
  return Array.from(map.entries())
    .map(([key, count]) => ({ key, count, label: key === '__none__' ? '—' : labelFn ? labelFn(key) : key }))
    .sort((x, y) => y.count - x.count);
}

export function computeAlunosMetrics(alunos: Aluno360[], view: DashView = 'alunos', filtros: DashFiltros = {}): AlunosMetrics {
  const base = applyDashFilters(alunos, view, filtros);
  const total = base.length;
  const ativos = base.filter((a) => ATIVO.has(String(a.status_acesso ?? '').toLowerCase())).length;

  // Nível ordenado do mais alto para o mais baixo (funil); "sem nível" ao fim.
  const porNivel = (Object.keys(NRANK) as string[])
    .sort((a, b) => NRANK[b] - NRANK[a])
    .map((key) => ({
      key,
      label: nivelLabel(key),
      count: base.filter((a) => a.nivel_resultado === key).length,
      color: NIVEL_COLOR[key] || 'var(--nivel-base)',
    }))
    .filter((d) => d.count > 0);
  const semNivel = base.filter((a) => !a.nivel_resultado).length;
  if (semNivel) porNivel.push({ key: '__none__', label: 'Sem nível', count: semNivel, color: 'var(--fg-4)' });

  return {
    total,
    ativos,
    pctAtivos: total ? Math.round((ativos / total) * 100) : 0,
    ht: base.filter((a) => a.tem_ht).length,
    hm: base.filter((a) => a.tem_hm).length,
    placa: base.filter((a) => a.tem_placa).length,
    depoimento: base.filter((a) => a.tem_depoimento).length,
    aurum: base.filter((a) => a.turma_aurum_id != null).length,
    socios: alunos.filter((a) => a.eh_socio).length,
    porNivel,
    porEspaco: tally(base.filter((a) => a.espaco_instrucao), (a) => a.espaco_instrucao, (k) => k.replace(/_/g, ' ')).slice(0, 6),
    porEstado: tally(base.filter((a) => a.estado), (a) => String(a.estado).toUpperCase()).slice(0, 8),
    porAno: tally(
      base.filter((a) => a.data_compra_importada),
      (a) => String(a.data_compra_importada).slice(0, 4),
    ).sort((x, y) => x.key.localeCompare(y.key)),
    porTurma: tally(base.filter((a) => a.turma_codigo), (a) => a.turma_codigo).slice(0, 8),
  };
}
