// Agregações da visão executiva do dashboard de alunos — puras, sobre a base já filtrada
// (applyDashFilters). Sem query: tudo sai dos campos que a lista de alunos já carrega.
import { NIVEL_CATALOG, NIVEL_ORDERED_KEYS, nivelNormalize } from '@/shared/domain/nivel-resultado';
import { ESPACO_LABEL, SITUACAO, type Aluno360 } from './aluno-360';

export interface Fatia { key: string; label: string; count: number; pct: number }

const pct = (n: number, t: number) => (t ? Math.round((n / t) * 100) : 0);
const ordemTurma = (x: string, y: string) => y.localeCompare(x, 'pt-BR', { numeric: true, sensitivity: 'base' });

/**
 * Turmas em ordem decrescente (T40 → T1). Com mais de `topN`, ficam as `topN` maiores (ainda na
 * ordem das turmas) e o resto vira uma linha "Outras". % sobre quem tem turma naquele campo.
 */
export function distribuicaoTurmas(base: Aluno360[], campo: 'turma_codigo' | 'turma_aurum_codigo', topN = 12): {
  fatias: Fatia[]; comTurma: number; semTurma: number;
} {
  const cont = new Map<string, number>();
  for (const a of base) {
    const t = String(a[campo] ?? '').trim();
    if (t) cont.set(t, (cont.get(t) ?? 0) + 1);
  }
  const comTurma = Array.from(cont.values()).reduce((s, n) => s + n, 0);
  const todas = Array.from(cont.entries()).map(([key, count]) => ({ key, label: key, count, pct: pct(count, comTurma) }));
  const top = todas.length > topN ? [...todas].sort((x, y) => y.count - x.count || ordemTurma(x.key, y.key)).slice(0, topN) : todas;
  const fatias = top.sort((x, y) => ordemTurma(x.key, y.key));
  const resto = todas.length - top.length;
  if (resto > 0) {
    const n = comTurma - fatias.reduce((s, f) => s + f.count, 0);
    fatias.push({ key: '__outras__', label: `Outras ${resto} turmas`, count: n, pct: pct(n, comTurma) });
  }
  return { fatias, comTurma, semTurma: base.length - comTurma };
}

/** Níveis na ordem da escala (Iniciante → Diamante Vermelho) e "Sem nível" ao fim. % sobre o recorte. */
export function distribuicaoNivel(base: Aluno360[]): Fatia[] {
  const cont = new Map<string, number>();
  for (const a of base) {
    const k = nivelNormalize(a.nivel_resultado) ?? '__none__';
    cont.set(k, (cont.get(k) ?? 0) + 1);
  }
  const out: Fatia[] = NIVEL_ORDERED_KEYS.filter((k) => cont.has(k))
    .map((k) => ({ key: k, label: NIVEL_CATALOG[k].label, count: cont.get(k)!, pct: pct(cont.get(k)!, base.length) }));
  if (cont.has('__none__')) out.push({ key: '__none__', label: 'Sem nível', count: cont.get('__none__')!, pct: pct(cont.get('__none__')!, base.length) });
  return out;
}

/** Situação de acesso na ordem de SITUACAO (em dia → acompanha titular) e "Sem situação" ao fim. */
export function distribuicaoSituacao(base: Aluno360[]): Fatia[] {
  const cont = new Map<string, number>();
  for (const a of base) {
    const k = a.situacao_acesso && SITUACAO[a.situacao_acesso] ? a.situacao_acesso : '__none__';
    cont.set(k, (cont.get(k) ?? 0) + 1);
  }
  return [...Object.keys(SITUACAO), '__none__']
    .filter((k) => cont.has(k))
    .map((k) => ({ key: k, label: SITUACAO[k]?.label ?? 'Sem situação', count: cont.get(k)!, pct: pct(cont.get(k)!, base.length) }));
}

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
/** Índice de mês (ano*12+mês) de uma data `YYYY-MM…`; null se inválida. */
const idxMes = (v: unknown): number | null => {
  const m = /^(\d{4})-(\d{2})/.exec(String(v ?? ''));
  return m && Number(m[2]) >= 1 && Number(m[2]) <= 12 ? Number(m[1]) * 12 + Number(m[2]) - 1 : null;
};

export interface ColunaEntrada {
  key: string;
  /** Rótulo do eixo: "mar/25" no mensal, "2025" no anual. */
  rotulo: string;
  /** Para tooltip e leitor de tela: "mar/2025". */
  rotuloLongo: string;
  /** No mensal: janeiro (marca o ano) e trimestre (abr, jul, out) recebem rótulo no eixo. */
  marco: 'ano' | 'trimestre' | null;
  total: number;
  /** Por espaço de instrução; quem não tem espaço destacado cai em `__outros__`. */
  segs: { key: string; count: number }[];
}

/** Acima disto o eixo mensal fica ilegível: a série passa a ser anual. */
export const MESES_MAX_SERIE_MENSAL = 36;

/**
 * Ingressos por período pela `data_compra_importada` (mesma data da série anual de antes).
 * Até 36 meses entre o 1º e o último ingresso: um ponto por mês; acima disso, por ano.
 * Períodos vazios entre o primeiro e o último entram zerados, para o eixo não pular.
 */
export function serieEntrada(base: Aluno360[]): { granularidade: 'mes' | 'ano'; colunas: ColunaEntrada[] } {
  const comData = base.map((a) => ({ a, i: idxMes(a.data_compra_importada) })).filter((x): x is { a: Aluno360; i: number } => x.i != null);
  if (!comData.length) return { granularidade: 'ano', colunas: [] };
  const min = Math.min(...comData.map((x) => x.i));
  const max = Math.max(...comData.map((x) => x.i));
  const mensal = max - min + 1 <= MESES_MAX_SERIE_MENSAL;
  const passo = (i: number) => (mensal ? i : Math.floor(i / 12));
  const ini = passo(min), fim = passo(max);
  const colunas: ColunaEntrada[] = [];
  for (let p = ini; p <= fim; p++) {
    const ano = mensal ? Math.floor(p / 12) : p;
    const mes = mensal ? p % 12 : 0;
    colunas.push({
      key: String(p),
      rotulo: mensal ? `${MESES[mes]}/${String(ano).slice(2)}` : String(ano),
      rotuloLongo: mensal ? `${MESES[mes]}/${ano}` : String(ano),
      marco: !mensal ? 'ano' : mes === 0 ? 'ano' : mes % 3 === 0 ? 'trimestre' : null,
      total: 0,
      segs: [],
    });
  }
  for (const { a, i } of comData) {
    const c = colunas[passo(i) - ini];
    c.total += 1;
    const k = a.espaco_instrucao && ESPACO_LABEL[a.espaco_instrucao] ? a.espaco_instrucao : '__outros__';
    const s = c.segs.find((x) => x.key === k);
    if (s) s.count += 1; else c.segs.push({ key: k, count: 1 });
  }
  const ordem = [...Object.keys(ESPACO_LABEL), '__outros__'];
  for (const c of colunas) c.segs.sort((x, y) => ordem.indexOf(x.key) - ordem.indexOf(y.key));
  return { granularidade: mensal ? 'mes' : 'ano', colunas };
}

/** Ingressos nos 12 meses até o mês de `hoje` (inclusive) × os 12 anteriores, e a série mês a mês. */
export function ingressos12m(base: Aluno360[], hoje: string): { atual: number; anterior: number; meses: number[] } {
  const h = idxMes(hoje);
  const meses = Array<number>(12).fill(0);
  let anterior = 0;
  if (h == null) return { atual: 0, anterior, meses };
  for (const a of base) {
    const i = idxMes(a.data_compra_importada);
    if (i == null) continue;
    const d = h - i;
    if (d >= 0 && d < 12) meses[11 - d] += 1;
    else if (d >= 12 && d < 24) anterior += 1;
  }
  return { atual: meses.reduce((s, n) => s + n, 0), anterior, meses };
}
