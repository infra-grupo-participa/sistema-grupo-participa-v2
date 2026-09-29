// Visão geral do Contas a Receber (#visao, fatia F4) — funções PURAS, sem I/O.
// Fontes (z69): fn_fin_receber_fotos_listar(), fn_fin_receber_mudancas(foto_a, foto_b) e
// fn_fin_receber_previsto_realizado(semanas); e, sem consulta nova, a carga do cenário base de fn_fin_receber_semanal
// (a mesma da grade). A regra (foto, motivo, previsto, realizado, acerto, perda medida) mora no banco; aqui só: tipar,
// converter numeric, somar por semana e agrupar para a tela.
import { BLOCO_CONTRATOS, secaoDaLinha, secaoDoGrupo, type CobrancaRecorrente, type LinhaReceber } from './contas-receber';

// ─── Tipos do contrato z69 ──────────────────────────────────────────────────
export interface FotoReceber {
  foto_em: string;
  /** Dia do corte em São Paulo (YYYY-MM-DD). */
  dia: string;
  cenario: string;
  corte: string | null;
  ate: string | null;
  linhas: number;
  soma_a_receber: number;
  /** Tirada depois do dia do corte (chamada manual): os dados são de quando foi tirada. */
  reconstruida: boolean;
}

export type MotivoMudanca =
  'entrou' | 'saiu_pagamento' | 'saiu_atraso' | 'saiu_periodo' | 'saiu_outro' | 'mudou_valor' | 'mudou_premissa';

export interface MotivoItem {
  /** Motivo fora do contrato fica cru (a tela mostra como veio). */
  motivo: string;
  itens: number;
  valor: number;
}

export interface MudancaReceber {
  bloco: number;
  grupo: string;
  valor_a: number;
  valor_b: number;
  delta: number;
  motivos: MotivoItem[];
}

export interface LinhaPrevistoRealizado {
  linha: 'semana' | 'perda' | string;
  semana_de: string | null;
  semana_ate: string | null;
  janela_de: string | null;
  janela_ate: string | null;
  foto_em: string | null;
  /** NULL na linha 'semana' = "Fora da foto (vendas novas e outros)" ou semana sem foto. */
  bloco: number | null;
  grupo: string | null;
  previsto: number | null;
  previsto_bruto: number | null;
  /** NULL = não medido (blocos estimados: a venda nova realizada cai em "Fora da foto"). */
  realizado: number | null;
  desvio: number | null;
  acerto_pct: number | null;
  chave_premissa: string | null;
  /** Fração (0,05 = 5%). NULL = sem cobrança resolvida. */
  perda_medida: number | null;
  /** Fração, a premissa em uso hoje. */
  premissa_atual: number | null;
  cobrancas_resolvidas: number | null;
  cobrancas_perdidas: number | null;
  valor_resolvido: number | null;
  valor_perdido: number | null;
  nota: string | null;
}

// ─── Conversão (numeric do PostgREST pode chegar como texto) ────────────────
const num = (v: unknown): number => Number(v ?? 0) || 0;
const numOuNull = (v: unknown): number | null => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const texto = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));

export function normalizarFoto(r: Record<string, unknown>): FotoReceber {
  return {
    foto_em: String(r.foto_em ?? ''),
    dia: String(r.dia ?? '').slice(0, 10),
    cenario: String(r.cenario ?? ''),
    corte: texto(r.corte),
    ate: dia(r.ate),
    linhas: num(r.linhas),
    soma_a_receber: num(r.soma_a_receber),
    reconstruida: r.reconstruida === true || r.reconstruida === 'true',
  };
}

function lerMotivos(v: unknown): MotivoItem[] {
  let bruto: unknown = v;
  if (typeof bruto === 'string') {
    try { bruto = JSON.parse(bruto); } catch { return []; }
  }
  if (!Array.isArray(bruto)) return [];
  return bruto.map((x) => {
    const o = (x ?? {}) as Record<string, unknown>;
    return { motivo: String(o.motivo ?? ''), itens: num(o.itens), valor: num(o.valor) };
  });
}

export function normalizarMudanca(r: Record<string, unknown>): MudancaReceber {
  return {
    bloco: num(r.bloco),
    grupo: String(r.grupo ?? ''),
    valor_a: num(r.valor_a),
    valor_b: num(r.valor_b),
    delta: num(r.delta),
    motivos: lerMotivos(r.motivos),
  };
}

export function normalizarPrevistoRealizado(r: Record<string, unknown>): LinhaPrevistoRealizado {
  return {
    linha: String(r.linha ?? ''),
    semana_de: dia(r.semana_de),
    semana_ate: dia(r.semana_ate),
    janela_de: dia(r.janela_de),
    janela_ate: dia(r.janela_ate),
    foto_em: texto(r.foto_em),
    bloco: numOuNull(r.bloco),
    grupo: texto(r.grupo),
    previsto: numOuNull(r.previsto),
    previsto_bruto: numOuNull(r.previsto_bruto),
    realizado: numOuNull(r.realizado),
    desvio: numOuNull(r.desvio),
    acerto_pct: numOuNull(r.acerto_pct),
    chave_premissa: texto(r.chave_premissa),
    perda_medida: numOuNull(r.perda_medida),
    premissa_atual: numOuNull(r.premissa_atual),
    cobrancas_resolvidas: numOuNull(r.cobrancas_resolvidas),
    cobrancas_perdidas: numOuNull(r.cobrancas_perdidas),
    valor_resolvido: numOuNull(r.valor_resolvido),
    valor_perdido: numOuNull(r.valor_perdido),
    nota: texto(r.nota),
  };
}

// ─── Calendário (UTC puro, sem fuso) ────────────────────────────────────────
const DIA = 86_400_000;
const ms = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);
export const somarDias = (d: string, n: number): string => iso(ms(d) + n * DIA);
/** Domingo da semana (seg–dom) que contém `d`. */
export const domingoDe = (d: string): string => somarDias(d, (7 - new Date(ms(d)).getUTCDay()) % 7);
/** A 1ª segunda-feira >= `d` (o próprio `d` se já for segunda). */
export const segundaEmOuDepois = (d: string): string => somarDias(d, (8 - new Date(ms(d)).getUTCDay()) % 7);

/** Soma em centavos: 0,1 + 0,2 não vira 0,30000000000000004. */
const c = (v: number) => Math.round(v * 100);
const r = (centavos: number) => centavos / 100;

// ─── Próximas 4 semanas (sem consulta: a carga base da grade) ───────────────
export interface SemanaVisao {
  inicio: string;
  fim: string;
  certo: number;
  estimado: number;
  total: number;
}

export interface Proximas4Semanas {
  semanas: SemanaVisao[];
  certo: number;
  estimado: number;
  total: number;
}

/**
 * As 4 semanas seg–dom a partir da semana de hoje: a 1ª vai de hoje ao domingo; as 3 seguintes são inteiras. Soma só o
 * que a grade soma (situacao 'a_receber', o esperado). A receber com data de caixa ANTES de hoje (atraso dentro da
 * tolerância) entra na 1ª semana — a grade também o põe na 1ª coluna. Informativo (bloco 8) e sem base: fora.
 */
export function proximas4Semanas(linhas: LinhaReceber[], hojeISO: string): Proximas4Semanas {
  const dom0 = domingoDe(hojeISO);
  const sems = [0, 1, 2, 3].map((i) => ({
    inicio: i === 0 ? hojeISO : somarDias(dom0, 1 + 7 * (i - 1)),
    fim: somarDias(dom0, 7 * i),
    certo: 0, estimado: 0,
  }));
  const fim = sems[3].fim;
  for (const l of linhas) {
    if (l.situacao !== 'a_receber' || !l.data_caixa || l.data_caixa > fim) continue;
    const i = l.data_caixa <= dom0 ? 0 : sems.findIndex((s) => l.data_caixa! >= s.inicio && l.data_caixa! <= s.fim);
    if (i === -1) continue;
    if (secaoDaLinha(l) === 'estimado') sems[i].estimado += c(l.valor); else sems[i].certo += c(l.valor);
  }
  const semanas = sems.map((s) => ({ inicio: s.inicio, fim: s.fim, certo: r(s.certo), estimado: r(s.estimado), total: r(s.certo + s.estimado) }));
  const certo = sems.reduce((a, s) => a + s.certo, 0);
  const estimado = sems.reduce((a, s) => a + s.estimado, 0);
  return { semanas, certo: r(certo), estimado: r(estimado), total: r(certo + estimado) };
}

// ─── Alertas (sem consulta: a carga base da grade + a lista de eventos, se veio) ──
export interface AlertasReceber {
  /** Bloco 2 'em_atraso_fora': cobranças (antecipação + garantia contam 1), como em Recorrências. */
  foraDaProjecao: { n: number; valor: number };
  /** Blocos 5 e 7 'em_atraso_fora' = recebimento informado (ou contrato Holding Familiar) em atraso, a cobrar. */
  informadosACobrar: { n: number; valor: number };
  /** Grupos estimados sem base medida (fora da soma). */
  semBase: { bloco: number; grupo: string }[];
  /**
   * A premissa projecao_no_receber desliga os blocos 3, 4, 6 e 8 inteiros (z67/z69): ligada, o bloco 3 sempre traz
   * linha (valor ou 'sem_base'). Nenhuma linha desses blocos = projeção desligada.
   */
  projecaoDesligada: boolean;
}

export function alertasReceber(linhas: LinhaReceber[], recorrencias: CobrancaRecorrente[]): AlertasReceber {
  const fora = recorrencias.filter((x) => x.situacao === 'em_atraso_fora');
  let infN = 0;
  let infC = 0;
  const semBase: AlertasReceber['semBase'] = [];
  for (const l of linhas) {
    if ((l.bloco === 5 || l.bloco === BLOCO_CONTRATOS) && l.situacao === 'em_atraso_fora') { infN += 1; infC += c(l.valor); }
    if (l.situacao === 'sem_base' && !semBase.some((x) => x.bloco === l.bloco && x.grupo === l.grupo)) semBase.push({ bloco: l.bloco, grupo: l.grupo });
  }
  return {
    foraDaProjecao: { n: fora.length, valor: r(fora.reduce((a, x) => a + c(x.valor), 0)) },
    informadosACobrar: { n: infN, valor: r(infC) },
    semBase: semBase.sort((a, b) => a.bloco - b.bloco || a.grupo.localeCompare(b.grupo, 'pt-BR')),
    projecaoDesligada: !linhas.some((l) => l.bloco === 3 || l.bloco === 4 || l.bloco === 6 || l.bloco === 8),
  };
}

// ─── Fotos ──────────────────────────────────────────────────────────────────
/** Fotos do cenário base, mais nova primeiro (o cron só tira a base; outra, manual, não entra na comparação). */
export const fotosBase = (fotos: FotoReceber[]): FotoReceber[] =>
  fotos.filter((f) => f.cenario === 'base').sort((a, b) => b.foto_em.localeCompare(a.foto_em));

/** As duas fotos base mais novas: A = a anterior, B = a mais recente. Menos de 2: sem comparação. */
export function parComparacao(fotos: FotoReceber[]): { anterior: FotoReceber; recente: FotoReceber } | null {
  const b = fotosBase(fotos);
  return b.length >= 2 ? { anterior: b[1], recente: b[0] } : null;
}

/** Hora do cron da foto semanal ('11 9 * * 1' em UTC = segunda 06:11 em São Paulo). */
export const HORA_FOTO = { h: 6, m: 11 } as const;

/**
 * Dia (YYYY-MM-DD, São Paulo) da próxima foto: a próxima segunda às 06:11. Hoje segunda antes das 06:11 = hoje.
 * `hojeISO` e `minutosDoDia` são os de São Paulo (o chamador converte).
 */
export function proximaFoto(hojeISO: string, minutosDoDia: number): string {
  const seg = segundaEmOuDepois(hojeISO);
  if (seg === hojeISO && minutosDoDia >= HORA_FOTO.h * 60 + HORA_FOTO.m) return somarDias(hojeISO, 7);
  return seg;
}

/**
 * Semana do 1º previsto × realizado possível: a foto base mais ANTIGA é a "foto da semana" que começa na 1ª segunda
 * >= dia dela (foto da semana = dia do corte em (seg − 7, seg]); o resultado sai quando essa semana termina.
 */
export function primeiraSemanaComparavel(fotos: FotoReceber[]): { de: string; ate: string; sai: string } | null {
  const b = fotosBase(fotos);
  if (!b.length) return null;
  const de = segundaEmOuDepois(b[b.length - 1].dia);
  return { de, ate: somarDias(de, 6), sai: somarDias(de, 7) };
}

// ─── O que mudou ────────────────────────────────────────────────────────────
/** Só os grupos que mudaram (delta ≠ 0 ou algum motivo); o resto vira contagem. Ordem do banco (bloco, grupo). */
export function separarMudancas(m: MudancaReceber[]): { mudaram: MudancaReceber[]; semMudanca: number } {
  const mudaram = m.filter((x) => c(x.delta) !== 0 || x.motivos.length > 0);
  return { mudaram, semMudanca: m.length - mudaram.length };
}

// ─── Previsto × realizado ───────────────────────────────────────────────────
/** Mesma fórmula do banco: max(0, 100 × (1 − |realizado − previsto| ÷ previsto)), 1 casa; NULL sem previsto. */
export function acertoPct(previsto: number, realizado: number): number | null {
  if (!(previsto > 0)) return null;
  return Math.round(Math.max(0, 100 * (1 - Math.abs(realizado - previsto) / previsto)) * 10) / 10;
}

export interface SemanaPrevistoRealizado {
  de: string;
  ate: string;
  janelaDe: string | null;
  janelaAte: string | null;
  fotoEm: string | null;
  /** Certo (blocos 1, 2, 5 e os contratos assinados do 7): o que a foto previa e o que caiu, medidos. */
  certoPrevisto: number;
  certoRealizado: number;
  certoAcerto: number | null;
  /** Estimado (3, 4, 6 e os contratos sem assinatura do 7): só o previsto; a venda nova que caiu entra em "Fora da foto". */
  estimadoPrevisto: number;
  /** Soma do realizado das linhas estimadas que o banco mediu (hoje só contrato sem assinatura, bloco 7). NULL =
   *  nenhuma linha estimada da semana trouxe realizado (blocos 3, 4 e 6 chegam com realizado NULL do banco). */
  estimadoRealizado: number | null;
  /** Bloco NULL: vendas novas e outros que caíram sem estar na foto. */
  foraDaFoto: number;
  linhas: LinhaPrevistoRealizado[];
  notas: string[];
}

export interface PrevistoRealizadoResumo {
  /** Semanas COM foto, mais nova primeiro. */
  semanas: SemanaPrevistoRealizado[];
  /** Semanas sem foto base no início (antes da 1ª foto). */
  semanasSemFoto: number;
  perda: LinhaPrevistoRealizado[];
}

export function resumirPrevistoRealizado(linhas: LinhaPrevistoRealizado[]): PrevistoRealizadoResumo {
  const porSemana = new Map<string, LinhaPrevistoRealizado[]>();
  const perda: LinhaPrevistoRealizado[] = [];
  for (const l of linhas) {
    if (l.linha === 'perda') { perda.push(l); continue; }
    if (l.linha !== 'semana' || !l.semana_de) continue;
    const xs = porSemana.get(l.semana_de) ?? [];
    xs.push(l);
    porSemana.set(l.semana_de, xs);
  }
  const semanas: SemanaPrevistoRealizado[] = [];
  let semanasSemFoto = 0;
  for (const [de, xs] of porSemana) {
    const comFoto = xs.find((x) => x.foto_em);
    if (!comFoto) { semanasSemFoto += 1; continue; }
    let cp = 0; let cr = 0; let ep = 0; let er = 0; let temEr = false; let ff = 0;
    for (const x of xs) {
      if (x.bloco == null) { ff += c(x.realizado ?? 0); continue; }
      if (secaoDoGrupo(x.bloco, x.grupo) === 'estimado') {
        ep += c(x.previsto ?? 0);
        if (x.realizado != null) { er += c(x.realizado); temEr = true; }
        continue;
      }
      cp += c(x.previsto ?? 0);
      cr += c(x.realizado ?? 0);
    }
    semanas.push({
      de, ate: xs[0].semana_ate ?? de, janelaDe: comFoto.janela_de, janelaAte: comFoto.janela_ate, fotoEm: comFoto.foto_em,
      certoPrevisto: r(cp), certoRealizado: r(cr), certoAcerto: acertoPct(r(cp), r(cr)),
      estimadoPrevisto: r(ep), estimadoRealizado: temEr ? r(er) : null, foraDaFoto: r(ff),
      linhas: xs.filter((x) => x.grupo != null || x.bloco != null),
      notas: [...new Set(xs.map((x) => x.nota).filter((n): n is string => !!n))],
    });
  }
  semanas.sort((a, b) => b.de.localeCompare(a.de));
  return { semanas, semanasSemFoto, perda };
}
