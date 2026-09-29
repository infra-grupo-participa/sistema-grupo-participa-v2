// Base auditável da Previsão de caixa (#receber?ver=base). Funções PURAS sobre as linhas JÁ CARREGADAS do cenário ativo
// (a mesma resposta de fn_fin_receber_semanal que monta a grade): filtro, soma do filtrado, resumo centro de custo × mês
// e o CSV. Nenhuma consulta nova.
//
// Regra da soma (a mesma da grade): só situacao 'a_receber' soma. 'realizada', 'em_atraso_fora', 'coberta_informado',
// 'sem_base' e 'informativo' aparecem e são CONTADAS, nunca somadas.
//
// Dado pessoal no CSV (padrão dos relatórios do Financeiro, shared/ui/pdf/nivel.ts): 'completo' leva o rótulo como veio;
// 'sem_dado_pessoal' troca o rótulo das linhas que são pessoas por "Pessoa N", estável por contrato/cadastro (bloco + ref)
// dentro do arquivo. Rótulo de pessoa = blocos 2 (nome do contrato), 5 (cliente do informado) e 8 (nome do card); nos
// blocos 1, 3, 4 e 6 o rótulo é a base do cálculo, não pessoa. Bloco desconhecido é tratado como pessoa (nega por padrão).
// A `ref` nunca sai no arquivo (bloco 2 é chave opaca de e-mail|oferta).
import { celulaCsv } from '../../domain/hotmart';
import { semanaDe, type LinhaReceber, type Semana, type SituacaoReceber } from '../../domain/contas-receber';
import { BASE_AUDITAVEL as T } from './textos';
import { rotuloBloco, rotuloCerteza, rotuloComponente, rotuloSituacaoLinha } from './rotulos-receber';

/** Valor dos filtros de lista "sem valor" (centro de custo / certeza NULL). */
export const SEM_VALOR = '__sem';
export const TODOS = '__todos';

export interface FiltroBase {
  /** Situação da linha, ou TODOS. Padrão: 'a_receber'. */
  situacao: SituacaoReceber | typeof TODOS;
  /** Número do bloco em texto, ou TODOS. */
  bloco: string;
  /** Centro de custo exato, SEM_VALOR ou TODOS. */
  centro: string;
  /** Certeza exata, SEM_VALOR ou TODOS. */
  certeza: string;
  busca: string;
  /** Data de caixa (YYYY-MM-DD) inclusive; '' = sem limite. Com limite, linha sem data de caixa sai. */
  de: string;
  ate: string;
}

export const FILTRO_BASE_PADRAO: FiltroBase = {
  situacao: 'a_receber', bloco: TODOS, centro: TODOS, certeza: TODOS, busca: '', de: '', ate: '',
};

/** Ordem das situações nos filtros e na contagem "fora da soma". */
export const SITUACOES_BASE: readonly SituacaoReceber[] = [
  'a_receber', 'realizada', 'em_atraso_fora', 'coberta_informado', 'sem_base', 'informativo',
];

/** Centros de custo de ENTRADA na ordem do fluxo de caixa do financeiro (C02). Os que vierem fora da lista vão ao fim. */
export const CENTROS_ENTRADA = [
  '1. Receita de vendas (Hotmart)',
  '4. Receita de vendas (Direta de clientes)',
  '3. (Devoluções)',
] as const;

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const casa = (v: string | null, f: string) => f === TODOS || (f === SEM_VALOR ? v == null : v === f);

/** Linhas do filtro, ordenadas por data de caixa (sem data no fim), bloco, grupo, componente e descrição. */
export function filtrarBase(linhas: LinhaReceber[], f: FiltroBase): LinhaReceber[] {
  const termo = semAcento(f.busca.trim());
  const out = linhas.filter((l) => {
    if (f.situacao !== TODOS && l.situacao !== f.situacao) return false;
    if (f.bloco !== TODOS && String(l.bloco) !== f.bloco) return false;
    if (!casa(l.centro_custo, f.centro) || !casa(l.certeza, f.certeza)) return false;
    if (f.de && (!l.data_caixa || l.data_caixa < f.de)) return false;
    if (f.ate && (!l.data_caixa || l.data_caixa > f.ate)) return false;
    if (termo) {
      const alvo = semAcento([l.grupo, l.rotulo, l.produto, l.tratamento, l.centro_custo].filter(Boolean).join(' '));
      if (!alvo.includes(termo)) return false;
    }
    return true;
  });
  return out.sort((a, b) => {
    if (a.data_caixa !== b.data_caixa) {
      if (a.data_caixa == null) return 1;
      if (b.data_caixa == null) return -1;
      return a.data_caixa < b.data_caixa ? -1 : 1;
    }
    return a.bloco - b.bloco || a.grupo.localeCompare(b.grupo, 'pt-BR') || a.componente.localeCompare(b.componente)
      || (a.rotulo ?? '').localeCompare(b.rotulo ?? '', 'pt-BR');
  });
}

/** Opções dos filtros de lista, tiradas das linhas carregadas (nada some por não estar numa lista fixa). */
export function opcoesBase(linhas: LinhaReceber[]) {
  const blocos = [...new Set(linhas.map((l) => l.bloco))].sort((a, b) => a - b);
  const centros = [...new Set(linhas.map((l) => l.centro_custo).filter((c): c is string => c != null))].sort(ordemCentro);
  const certezas = [...new Set(linhas.map((l) => l.certeza).filter((c): c is string => c != null))].sort();
  return {
    blocos, centros, certezas,
    temSemCentro: linhas.some((l) => l.centro_custo == null),
    temSemCerteza: linhas.some((l) => l.certeza == null),
  };
}

function ordemCentro(a: string, b: string): number {
  const ia = (CENTROS_ENTRADA as readonly string[]).indexOf(a);
  const ib = (CENTROS_ENTRADA as readonly string[]).indexOf(b);
  return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib) || a.localeCompare(b, 'pt-BR');
}

const c = (v: number) => Math.round(v * 100);

export interface SomaBase {
  /** Linhas a_receber do filtro e a soma (esperado e bruto). */
  aReceber: { linhas: number; valor: number; bruto: number };
  /** Contagem por situação que NÃO soma, na ordem de SITUACOES_BASE; só as com linha. */
  foraDaSoma: { situacao: SituacaoReceber | string; linhas: number }[];
}

export function somarBase(linhas: LinhaReceber[]): SomaBase {
  let n = 0;
  let cv = 0;
  let cb = 0;
  const fora = new Map<string, number>();
  for (const l of linhas) {
    if (l.situacao === 'a_receber') { n += 1; cv += c(l.valor); cb += c(l.valor_bruto); continue; }
    fora.set(l.situacao, (fora.get(l.situacao) ?? 0) + 1);
  }
  const ordem = (s: string) => { const i = SITUACOES_BASE.indexOf(s as SituacaoReceber); return i === -1 ? 99 : i; };
  return {
    aReceber: { linhas: n, valor: cv / 100, bruto: cb / 100 },
    foraDaSoma: [...fora.entries()].sort((a, b) => ordem(a[0]) - ordem(b[0])).map(([situacao, linhas]) => ({ situacao, linhas })),
  };
}

export interface ResumoCentroMes {
  meses: string[];
  /** Os 3 centros de entrada sempre aparecem (zero é '–' na tela); outro centro ou NULL entram depois. */
  linhas: { centro: string | null; porMes: number[]; total: number }[];
  totalPorMes: number[];
  total: number;
  /** a_receber sem data de caixa: fora do resumo, mas não some em silêncio. */
  semData: { linhas: number; valor: number };
}

/** Resumo centro de custo × mês (mês da data de caixa) do ESPERADO a receber das linhas recebidas. */
export function resumoCentroMes(linhas: LinhaReceber[]): ResumoCentroMes {
  const somaveis = linhas.filter((l) => l.situacao === 'a_receber');
  const comData = somaveis.filter((l) => l.data_caixa != null);
  const meses = [...new Set(comData.map((l) => l.data_caixa!.slice(0, 7)))].sort();
  const idx = new Map(meses.map((m, i) => [m, i]));
  const porCentro = new Map<string | null, number[]>(CENTROS_ENTRADA.map((x) => [x, new Array(meses.length).fill(0)]));
  for (const l of comData) {
    let v = porCentro.get(l.centro_custo);
    if (!v) { v = new Array(meses.length).fill(0); porCentro.set(l.centro_custo, v); }
    v[idx.get(l.data_caixa!.slice(0, 7))!] += c(l.valor);
  }
  const chaves = [...porCentro.keys()].sort((a, b) => (a == null ? 1 : b == null ? -1 : ordemCentro(a, b)));
  const totalC = new Array(meses.length).fill(0);
  const out = chaves.map((centro) => {
    const v = porCentro.get(centro)!;
    v.forEach((x, i) => { totalC[i] += x; });
    return { centro, porMes: v.map((x) => x / 100), total: v.reduce((s, x) => s + x, 0) / 100 };
  });
  const semData = somaveis.filter((l) => l.data_caixa == null);
  return {
    meses, linhas: out, totalPorMes: totalC.map((x) => x / 100), total: totalC.reduce((s, x) => s + x, 0) / 100,
    semData: { linhas: semData.length, valor: semData.reduce((s, l) => s + c(l.valor), 0) / 100 },
  };
}

/** Semana da grade que contém a data de caixa: 'S3'; fora do período ou sem data: ''. */
export function rotuloSemanaDaLinha(semanas: Semana[], dataCaixa: string | null): string {
  if (!dataCaixa) return '';
  const i = semanaDe(semanas, dataCaixa);
  return i === -1 ? '' : `S${semanas[i].n}`;
}

// ─── CSV ─────────────────────────────────────────────────────────────────────
export type NivelCsvBase = 'completo' | 'sem_dado_pessoal';
export const NIVEIS_CSV_BASE: readonly NivelCsvBase[] = ['completo', 'sem_dado_pessoal'];

/** Blocos em que o rótulo NÃO é pessoa (é a base do cálculo). Qualquer outro bloco: o rótulo é tratado como pessoa. */
const BLOCOS_ROTULO_NAO_PESSOA: readonly number[] = [1, 3, 4, 6];
export const rotuloEPessoa = (bloco: number) => !BLOCOS_ROTULO_NAO_PESSOA.includes(bloco);

/** 'YYYY-MM-DD' → 'dd/mm/aaaa' (sem fuso, sem locale). */
export const dataCsv = (d: string | null) => (d ? `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}` : '');
/** Decimal com vírgula, sem separador de milhar, 2 casas: -1234.5 → '-1234,50'. Número nunca passa por celulaCsv
 * (o apóstrofo antifórmula estragaria o negativo da reserva). */
export const moedaCsv = (v: number) => v.toFixed(2).replace('.', ',');
/** Fator com até 6 casas, sem zero à direita: 0.857375 → '0,857375'; 1 → '1'. */
export const fatorCsv = (f: number) => String(Number(f.toFixed(6))).replace('.', ',');

/**
 * Descrição sem dado pessoal, na ordem em que as linhas passam: rótulo de pessoa vira "Pessoa N", estável por
 * contrato/cadastro (bloco + ref) dentro do documento; linha de pessoa sem ref ganha número próprio. Rótulo que não é
 * pessoa sai como veio. Regra ÚNICA do CSV e do PDF (ui/pdf/documentos.ts) da Base auditável.
 */
export function pseudonimizadorBase(): (l: LinhaReceber) => string {
  const pessoas = new Map<string, number>();
  let semRef = 0;
  return (l) => {
    if (!rotuloEPessoa(l.bloco) || l.rotulo == null) return l.rotulo ?? '';
    const chave = l.ref != null ? `${l.bloco}\u0000${l.ref}` : `\u0001${semRef++}`;
    let n = pessoas.get(chave);
    if (n == null) { n = pessoas.size + 1; pessoas.set(chave, n); }
    return T.pessoa(n);
  };
}

/**
 * CSV das linhas recebidas (já filtradas e ordenadas pela tela): separador ';', decimal ',', datas dd/mm/aaaa,
 * UTF-8 com BOM. Texto passa por celulaCsv (antifórmula). Linha 'sem_base' sai com os valores VAZIOS (não zero).
 */
export function csvBaseAuditavel(linhas: LinhaReceber[], semanas: Semana[], nivel: NivelCsvBase, cenario: string): string {
  const pseudonimo = pseudonimizadorBase();
  const descricao = (l: LinhaReceber): string => (nivel === 'completo' ? l.rotulo ?? '' : pseudonimo(l));
  const cab = [
    T.dataCaixa, T.semana, T.bloco, T.grupo, T.componente, T.descricao, T.produto, T.valorEsperado, T.valorBruto,
    T.fator, T.centroCusto, T.certeza, T.situacao, T.tratamento, T.cenario,
  ];
  const txt = (v: unknown) => celulaCsv(v);
  const corpo = linhas.map((l) => {
    const semBase = l.situacao === 'sem_base';
    return [
      dataCsv(l.data_caixa),
      rotuloSemanaDaLinha(semanas, l.data_caixa),
      txt(`${l.bloco}. ${rotuloBloco(l.bloco)}`),
      txt(l.grupo),
      txt(rotuloComponente(l.componente)),
      txt(descricao(l)),
      txt(l.produto ?? ''),
      semBase ? '' : moedaCsv(l.valor),
      semBase ? '' : moedaCsv(l.valor_bruto),
      fatorCsv(l.fator),
      txt(l.centro_custo ?? ''),
      txt(l.certeza == null ? '' : rotuloCerteza(l.certeza)),
      txt(rotuloSituacaoLinha(l.situacao)),
      txt(l.tratamento ?? ''),
      txt(cenario),
    ].join(';');
  });
  return '﻿' + [cab.map(txt).join(';'), ...corpo].join('\r\n');
}

/** Nome do arquivo: data (São Paulo), cenário e nível. */
export function nomeArquivoCsvBase(hojeISO: string, cenario: string, nivel: NivelCsvBase): string {
  return `previsao-caixa-base-auditavel-${hojeISO}-${cenario}-${nivel === 'completo' ? 'completo' : 'sem-dado-pessoal'}.csv`;
}
