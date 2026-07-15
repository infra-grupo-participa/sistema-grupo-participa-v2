// Métricas do Dashboard da Base de Alunos — puras, client-side sobre os alunos carregados.
// Porta da spec docs/specs/dashboard-indicadores.md (Opção A: dado limpo do acervo).
import { ESPACO_LABEL, ESPACO_COLOR } from './aluno-360';
import type { Aluno360 } from './aluno-360';

export type DashView = 'alunos' | 'socios';
export interface DashFiltros {
  espaco?: string[];
  estado?: string[];
  turma?: string[];
}
const ATIVO = new Set(['renovado', 'vigente']);

// Coage valor de filtro para array (tolera visões salvas no formato antigo string única).
const asArr = (v: string[] | string | undefined): string[] => (Array.isArray(v) ? v : v ? [v] : []);

/** Aplica view (alunos/sócios) + filtros do dashboard (multi-seleção: OR dentro, AND entre). */
export function applyDashFilters(alunos: Aluno360[], view: DashView, f: DashFiltros = {}): Aluno360[] {
  const esp = asArr(f.espaco);
  const est = asArr(f.estado);
  const tur = asArr(f.turma);
  return alunos.filter((a) => {
    if (view === 'socios' && !a.eh_socio) return false;
    if (esp.length && !esp.includes(a.espaco_instrucao || '')) return false;
    if (est.length && !est.includes(String(a.estado ?? '').toUpperCase())) return false;
    if (tur.length && !tur.includes(a.turma_codigo || '')) return false;
    return true;
  });
}

export interface Distribuicao {
  key: string;
  label: string;
  count: number;
  color?: string;
  /** Detalhe titular/sócio (ex.: Top estados) — opcional. */
  titulares?: number;
  socios?: number;
}

export interface EspacoKpi { key: string; label: string; total: number; titulares: number; socios: number; color: string }
export interface AnoEspaco { year: string; total: number; segs: { key: string; count: number; color: string }[] }

/** Espaços destacados nos KPIs (ordem fixa). */
const ESPACO_KPI: { key: string; label: string }[] = [
  { key: 'holding_masters', label: 'Holding Masters' },
  { key: 'aurum', label: 'Aurum' },
  { key: 'platina', label: 'Platina' },
  { key: 'mastermind_diamante', label: 'Diamante' },
  { key: 'diamante_vermelho', label: 'Diamante Vermelho' },
];

export interface AlunosMetrics {
  total: number;
  ativos: number;
  pctAtivos: number;
  ht: number;
  hm: number;
  placa: number;
  depoimento: number;
  sip: number;
  aurum: number;
  socios: number;
  totalTitulares: number;
  totalSocios: number;
  espacoKpi: EspacoKpi[];
  porEspaco: Distribuicao[];
  porEstado: Distribuicao[];
  porAnoEspaco: AnoEspaco[];
  porTurma: Distribuicao[];
}

/** Matriz turma × espaço de instrução (heat). Linhas = todas as turmas, colunas = espaços presentes. */
export interface TurmaEspacoMatrix {
  turmas: string[];
  colunas: { key: string; label: string; color: string }[];
  cells: Record<string, Record<string, number>>;
  max: number;
}

export function computeTurmaEspacoMatrix(alunos: Aluno360[]): TurmaEspacoMatrix {
  const colunas = (Object.keys(ESPACO_LABEL) as string[])
    .filter((k) => alunos.some((a) => a.espaco_instrucao === k))
    .map((key) => ({ key, label: ESPACO_LABEL[key], color: ESPACO_COLOR[key] || 'var(--nivel-base)' }));

  const turmaCounts = new Map<string, number>();
  for (const a of alunos) if (a.turma_codigo) turmaCounts.set(a.turma_codigo, (turmaCounts.get(a.turma_codigo) ?? 0) + 1);
  // Ordem decrescente por edição de turma (T38 → T1).
  const turmas = Array.from(turmaCounts.keys()).sort((a, b) =>
    b.localeCompare(a, 'pt-BR', { numeric: true, sensitivity: 'base' }),
  );

  const cells: Record<string, Record<string, number>> = {};
  let max = 0;
  for (const t of turmas) {
    cells[t] = {};
    for (const col of colunas) {
      const c = alunos.filter((a) => a.turma_codigo === t && a.espaco_instrucao === col.key).length;
      cells[t][col.key] = c;
      if (c > max) max = c;
    }
  }
  return { turmas, colunas, cells, max };
}

export function computeAlunosMetrics(alunos: Aluno360[], view: DashView = 'alunos', filtros: DashFiltros = {}): AlunosMetrics {
  const base = applyDashFilters(alunos, view, filtros);
  const total = base.length;
  const ativos = base.filter((a) => ATIVO.has(String(a.status_acesso ?? '').toLowerCase())).length;

  // Espaço de instrução (o que mais importa) — com recorte titular/sócio; "sem espaço" ao fim.
  const porEspaco = (Object.keys(ESPACO_LABEL) as string[])
    .map((key) => {
      const rows = base.filter((a) => a.espaco_instrucao === key);
      return {
        key,
        label: ESPACO_LABEL[key],
        count: rows.length,
        color: ESPACO_COLOR[key] || 'var(--nivel-base)',
        titulares: rows.filter((a) => !a.eh_socio).length,
        socios: rows.filter((a) => a.eh_socio).length,
      };
    })
    .filter((d) => d.count > 0)
    .sort((x, y) => y.count - x.count);
  const semEspacoRows = base.filter((a) => !a.espaco_instrucao);
  if (semEspacoRows.length) {
    porEspaco.push({ key: '__none__', label: 'Sem espaço', count: semEspacoRows.length, color: 'var(--fg-4)', titulares: semEspacoRows.filter((a) => !a.eh_socio).length, socios: semEspacoRows.filter((a) => a.eh_socio).length });
  }

  return {
    total,
    ativos,
    pctAtivos: total ? Math.round((ativos / total) * 100) : 0,
    ht: base.filter((a) => a.tem_ht).length,
    hm: base.filter((a) => a.tem_hm).length,
    placa: base.filter((a) => a.tem_placa).length,
    depoimento: base.filter((a) => a.tem_depoimento).length,
    sip: base.filter((a) => a.sip_registrado).length,
    aurum: base.filter((a) => a.turma_aurum_id != null).length,
    socios: alunos.filter((a) => a.eh_socio).length,
    totalTitulares: base.filter((a) => !a.eh_socio).length,
    totalSocios: base.filter((a) => a.eh_socio).length,
    espacoKpi: ESPACO_KPI.map(({ key, label }) => {
      const rows = base.filter((a) => a.espaco_instrucao === key);
      return { key, label, total: rows.length, titulares: rows.filter((a) => !a.eh_socio).length, socios: rows.filter((a) => a.eh_socio).length, color: ESPACO_COLOR[key] || 'var(--nivel-base)' };
    }),
    porEspaco,
    porEstado: (() => {
      const byUf = new Map<string, { t: number; s: number }>();
      for (const a of base) {
        const uf = String(a.estado ?? '').toUpperCase();
        if (!uf) continue;
        const cur = byUf.get(uf) ?? { t: 0, s: 0 };
        if (a.eh_socio) cur.s += 1; else cur.t += 1;
        byUf.set(uf, cur);
      }
      return Array.from(byUf.entries())
        .map(([key, v]) => ({ key, label: key, count: v.t + v.s, titulares: v.t, socios: v.s }))
        .sort((x, y) => y.count - x.count)
        .slice(0, 8);
    })(),
    porAnoEspaco: (() => {
      const anos = Array.from(new Set(base.filter((a) => a.data_compra_importada).map((a) => String(a.data_compra_importada).slice(0, 4)))).sort();
      return anos.map((year) => {
        const rows = base.filter((a) => String(a.data_compra_importada ?? '').slice(0, 4) === year);
        const segs = ESPACO_KPI.map(({ key }) => ({ key, count: rows.filter((a) => a.espaco_instrucao === key).length, color: ESPACO_COLOR[key] || 'var(--nivel-base)' })).filter((s) => s.count > 0);
        return { year, total: rows.length, segs };
      });
    })(),
    porTurma: (() => {
      const map = new Map<string, number>();
      for (const a of base) if (a.turma_codigo) map.set(a.turma_codigo, (map.get(a.turma_codigo) ?? 0) + 1);
      return Array.from(map.entries())
        .map(([key, count]) => ({ key, label: key, count }))
        .sort((x, y) => y.key.localeCompare(x.key, 'pt-BR', { numeric: true, sensitivity: 'base' })); // T38 → T1
    })(),
  };
}
