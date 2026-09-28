// Contas a Receber — fase 1 (28/09/2026). Função PURA, sem I/O. Substitui, na planilha semanal do financeiro
// ("Contas a Receber Semanal Set-Dez26"), só o que é CERTO:
//   bloco 1 — vendas já feitas, dinheiro ainda a cair (90% − 3,89% em D+2 útil; 10% no 1º dia útil ≥ D+30);
//   bloco 2 — assinaturas e parcelas futuras já contratadas.
// Blocos 3–7 da planilha (vendas novas, evento, recebimentos informados, ajustes, Soluções) ficam para depois.
//
// Fonte: public.fn_fin_contas_receber(p_corte, p_ate) — UMA chamada; o cálculo de data de caixa (dias úteis,
// feriados) e a baixa do que já se realizou moram no banco. Aqui só: tipar, converter numeric, cortar em semanas e somar.
//
// Esta é a ÚNICA fonte da semana: a tela e o PDF futuro usam `semanas()` e `agregarReceber()` daqui.

export type ComponenteReceber = 'antecipacao' | 'garantia' | 'cheio';
/** `realizada` vem só para auditoria; `em_atraso_fora` saiu da projeção. Nenhum dos dois soma. */
export type SituacaoReceber = 'a_receber' | 'realizada' | 'em_atraso_fora';

/** Bloco 1: uma venda do dia que compõe a antecipação/garantia daquele dia. */
export interface VendaDoDia {
  transacao: string;
  produto: string | null;
  nome: string | null;
  /** Líquido da VENDA (não o valor que cai: esse é a linha). */
  liquido: number;
}

/** Uma linha de fn_fin_contas_receber, já normalizada. */
export interface LinhaReceber {
  bloco: number;
  grupo: string;
  componente: ComponenteReceber;
  /** Dia em que o dinheiro fica disponível (YYYY-MM-DD). É o eixo da grade. */
  data_caixa: string;
  valor: number;
  situacao: SituacaoReceber;
  /** Bloco 1: dia da venda. Bloco 2: dia previsto da cobrança. */
  origem_dia: string | null;
  /** Chave opaca da cobrança (bloco 2). */
  ref: string | null;
  rotulo: string | null;
  produto: string | null;
  /** Meses à frente. */
  k: number | null;
  /** Bloco 1: vendas do dia. Bloco 2: vazio. */
  detalhe: VendaDoDia[];
}

export const GRUPO_BLOCO_1 = 'Vendas já realizadas';
/** Ordem das linhas do bloco 2 na grade (a mesma da planilha). Grupo desconhecido vai para o fim, nunca some. */
export const GRUPOS_BLOCO_2 = [
  'Assinaturas Serviço Diamante',
  'Assinaturas Holding - Holding Masters',
  'Parcelas a vencer HM',
  'Parcelas a vencer Aurum',
  'Parcelas a vencer outros',
  'Outras assinaturas',
] as const;

// ─── Conversão (numeric do PostgREST pode chegar como texto) ────────────────
const num = (v: unknown): number => Number(v ?? 0) || 0;
const numOuNull = (v: unknown): number | null => (v == null || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));

function lerDetalhe(v: unknown): VendaDoDia[] {
  let bruto: unknown = v;
  if (typeof bruto === 'string') {
    try { bruto = JSON.parse(bruto); } catch { return []; }
  }
  if (!Array.isArray(bruto)) return [];
  return bruto.map((x) => {
    const o = (x ?? {}) as Record<string, unknown>;
    return {
      transacao: String(o.transacao ?? ''),
      produto: o.produto == null ? null : String(o.produto),
      nome: o.nome == null ? null : String(o.nome),
      liquido: num(o.liquido),
    };
  });
}

export function normalizarLinhaReceber(r: Record<string, unknown>): LinhaReceber {
  const situacao = String(r.situacao ?? '') as SituacaoReceber;
  const componente = String(r.componente ?? '') as ComponenteReceber;
  return {
    bloco: num(r.bloco),
    grupo: String(r.grupo ?? ''),
    // Valor fora do contrato é mantido cru e NÃO vira a_receber: não soma e a lista mostra o valor como veio.
    situacao,
    componente,
    data_caixa: dia(r.data_caixa) ?? '',
    valor: num(r.valor),
    origem_dia: dia(r.origem_dia),
    ref: r.ref == null ? null : String(r.ref),
    rotulo: r.rotulo == null ? null : String(r.rotulo),
    produto: r.produto == null ? null : String(r.produto),
    k: numOuNull(r.k),
    detalhe: lerDetalhe(r.detalhe),
  };
}

// ─── Calendário (UTC puro, sem fuso) ────────────────────────────────────────
const ms = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);
const DIA = 86_400_000;

/** Último dia do mês de `iso` (YYYY-MM-DD). */
export function fimDoMes(d: string): string {
  const [y, m] = d.split('-').map(Number);
  return iso(Date.UTC(y, m, 0));
}

export interface Semana {
  /** 1, 2, 3… na ordem do período. */
  n: number;
  inicio: string;
  fim: string;
  /** YYYY-MM — a semana nunca cruza mês. */
  mes: string;
}

/**
 * Semanas de `inicio` a `fim` (inclusive): segunda a domingo, cortadas na virada do mês e no início do período.
 * Uma semana nova começa na segunda-feira, no dia 1º do mês e no próprio `inicio`.
 */
export function semanas(inicio: string, fim: string): Semana[] {
  const out: Semana[] = [];
  const a = ms(inicio);
  const b = ms(fim);
  if (!(a <= b)) return out;
  let cur: Semana | null = null;
  for (let t = a; t <= b; t += DIA) {
    const d = new Date(t);
    const novo = cur == null || d.getUTCDay() === 1 || d.getUTCDate() === 1;
    const hoje = iso(t);
    if (novo) {
      cur = { n: out.length + 1, inicio: hoje, fim: hoje, mes: hoje.slice(0, 7) };
      out.push(cur);
    } else if (cur) {
      cur.fim = hoje;
    }
  }
  return out;
}

/** Índice da semana que contém `d`, ou -1 fora do período. */
export function semanaDe(sems: Semana[], d: string): number {
  for (let i = 0; i < sems.length; i++) if (d >= sems[i].inicio && d <= sems[i].fim) return i;
  return -1;
}

// ─── Agregação semana × bloco × grupo (só a_receber) ────────────────────────
export interface LinhaGrade {
  bloco: number;
  grupo: string;
  porSemana: number[];
  total: number;
}

export interface MesGrade {
  mes: string;
  /** Índices das semanas do mês (contíguos). */
  semanas: number[];
  total: number;
  acumulado: number;
}

export interface GradeReceber {
  semanas: Semana[];
  linhas: LinhaGrade[];
  /** Subtotal por bloco, por semana (bloco 2 tem vários grupos). */
  blocos: { bloco: number; porSemana: number[]; total: number }[];
  totalPorSemana: number[];
  acumuladoPorSemana: number[];
  meses: MesGrade[];
  total: number;
  /** a_receber com data_caixa fora do período: não entra na grade, mas não some em silêncio. */
  foraDoPeriodo: { linhas: number; valor: number };
}

/** Soma em centavos: 0,1 + 0,2 não vira 0,30000000000000004 no total da semana. */
const c = (v: number) => Math.round(v * 100);
const r = (centavos: number) => centavos / 100;

function ordemGrupo(bloco: number, grupo: string): number {
  if (bloco === 1) return grupo === GRUPO_BLOCO_1 ? 0 : 1;
  const i = (GRUPOS_BLOCO_2 as readonly string[]).indexOf(grupo);
  return i === -1 ? GRUPOS_BLOCO_2.length : i;
}

export function agregarReceber(linhas: LinhaReceber[], inicio: string, fim: string): GradeReceber {
  const sems = semanas(inicio, fim);
  const n = sems.length;
  const porGrupo = new Map<string, { bloco: number; grupo: string; cs: number[] }>();
  let foraN = 0;
  let foraC = 0;
  for (const l of linhas) {
    if (l.situacao !== 'a_receber') continue;
    const i = semanaDe(sems, l.data_caixa);
    if (i === -1) { foraN += 1; foraC += c(l.valor); continue; }
    const chave = `${l.bloco}\u0000${l.grupo}`;
    let g = porGrupo.get(chave);
    if (!g) { g = { bloco: l.bloco, grupo: l.grupo, cs: new Array(n).fill(0) }; porGrupo.set(chave, g); }
    g.cs[i] += c(l.valor);
  }
  const grupos = [...porGrupo.values()].sort((a, b) =>
    a.bloco - b.bloco || ordemGrupo(a.bloco, a.grupo) - ordemGrupo(b.bloco, b.grupo) || a.grupo.localeCompare(b.grupo, 'pt-BR'));

  const totalC = new Array(n).fill(0);
  const porBloco = new Map<number, number[]>();
  for (const g of grupos) {
    let b = porBloco.get(g.bloco);
    if (!b) { b = new Array(n).fill(0); porBloco.set(g.bloco, b); }
    for (let i = 0; i < n; i++) { totalC[i] += g.cs[i]; b[i] += g.cs[i]; }
  }
  const acumC: number[] = [];
  totalC.reduce((s, v, i) => (acumC[i] = s + v), 0);

  const meses: MesGrade[] = [];
  for (let i = 0; i < n; i++) {
    const ultimo = meses[meses.length - 1];
    if (ultimo && ultimo.mes === sems[i].mes) { ultimo.semanas.push(i); ultimo.total += totalC[i]; } else meses.push({ mes: sems[i].mes, semanas: [i], total: totalC[i], acumulado: 0 });
  }
  let acM = 0;
  for (const m of meses) { acM += m.total; m.acumulado = r(acM); m.total = r(m.total); }

  const soma = (xs: number[]) => xs.reduce((s, v) => s + v, 0);
  return {
    semanas: sems,
    linhas: grupos.map((g) => ({ bloco: g.bloco, grupo: g.grupo, porSemana: g.cs.map(r), total: r(soma(g.cs)) })),
    blocos: [...porBloco.entries()].sort((a, b) => a[0] - b[0]).map(([bloco, cs]) => ({ bloco, porSemana: cs.map(r), total: r(soma(cs)) })),
    totalPorSemana: totalC.map(r),
    acumuladoPorSemana: acumC.map(r),
    meses,
    total: r(soma(totalC)),
    foraDoPeriodo: { linhas: foraN, valor: r(foraC) },
  };
}

/**
 * Período da grade: de hoje (ou da 1ª data a receber, se anterior) até o fim do mês da última data a receber.
 * Nada a receber → só o mês corrente.
 */
export function periodoReceber(linhas: LinhaReceber[], hojeISO: string): { inicio: string; fim: string } {
  let min = hojeISO;
  let max = hojeISO;
  for (const l of linhas) {
    if (l.situacao !== 'a_receber' || !l.data_caixa) continue;
    if (l.data_caixa < min) min = l.data_caixa;
    if (l.data_caixa > max) max = l.data_caixa;
  }
  return { inicio: min, fim: fimDoMes(max) };
}

/** Quem compõe uma célula (grupo × semana), SEM consulta nova: as linhas a_receber daquele grupo naquela semana. */
export function composicaoDaCelula(
  linhas: LinhaReceber[], sem: Semana | null, bloco: number, grupo: string,
): LinhaReceber[] {
  return linhas
    .filter((l) => l.situacao === 'a_receber' && l.bloco === bloco && l.grupo === grupo
      && (sem == null || (l.data_caixa >= sem.inicio && l.data_caixa <= sem.fim)))
    .sort((a, b) => a.data_caixa.localeCompare(b.data_caixa) || (a.rotulo ?? '').localeCompare(b.rotulo ?? '', 'pt-BR'));
}

// ─── Recorrências (bloco 2, todas as situações) ─────────────────────────────
export interface CobrancaRecorrente {
  ref: string | null;
  grupo: string;
  rotulo: string | null;
  produto: string | null;
  /** Dia previsto da cobrança (origem_dia; sem ele, a 1ª data de caixa). */
  prevista: string;
  /** Dias em que as partes (D+2 / garantia / cheio) caem no caixa. */
  caixa: string[];
  valor: number;
  situacao: SituacaoReceber;
  k: number | null;
}

/** Junta as partes (antecipação + garantia) da mesma cobrança pela `ref`; sem ref, cada linha é uma cobrança. */
export function cobrancasRecorrentes(linhas: LinhaReceber[]): CobrancaRecorrente[] {
  const mapa = new Map<string, CobrancaRecorrente & { cents: number }>();
  let semRef = 0;
  for (const l of linhas) {
    if (l.bloco !== 2) continue;
    const chave = l.ref != null ? `${l.ref}\u0000${l.situacao}` : `\u0001${semRef++}`;
    let x = mapa.get(chave);
    if (!x) {
      x = {
        ref: l.ref, grupo: l.grupo, rotulo: l.rotulo, produto: l.produto, prevista: l.origem_dia ?? l.data_caixa,
        caixa: [], valor: 0, cents: 0, situacao: l.situacao, k: l.k,
      };
      mapa.set(chave, x);
    }
    x.cents += c(l.valor);
    if (l.data_caixa && !x.caixa.includes(l.data_caixa)) x.caixa.push(l.data_caixa);
    if (!l.origem_dia && l.data_caixa < x.prevista) x.prevista = l.data_caixa;
  }
  return [...mapa.values()]
    .map(({ cents, ...x }) => ({ ...x, valor: r(cents), caixa: x.caixa.sort() }))
    .sort((a, b) => a.prevista.localeCompare(b.prevista) || (a.rotulo ?? '').localeCompare(b.rotulo ?? '', 'pt-BR'));
}
