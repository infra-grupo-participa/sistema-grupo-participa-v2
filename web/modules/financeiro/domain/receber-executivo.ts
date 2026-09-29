// Números da faixa executiva do Contas a Receber (KPIs e gráficos de cada sub-aba). Funções PURAS: agregam só o que a
// tela já carregou (linhas da grade, recorrências, informados, eventos, premissas, fotos). Nenhuma consulta, nenhuma
// regra nova: situação, esperado e sugestão vêm prontos do banco/domínio; aqui só se conta, soma e fatia.
// Dinheiro em centavos na soma (0,1 + 0,2 não vira 0,30000000000000004).
import type { CobrancaRecorrente, LinhaReceber } from './contas-receber';
import type { Informado } from './recebimentos-informados';
import { totalEsperado, type EventoPlanejado } from './eventos-planejados';
import { valorDaSugestao, type PremissaTela, type SugestaoPremissa } from './premissas-receber';
import type { MudancaReceber, SemanaPrevistoRealizado } from './visao-receber';

const c = (v: number) => Math.round(v * 100);
const r = (centavos: number) => centavos / 100;

export interface Soma { n: number; valor: number }

function somar<T>(xs: T[], valor: (x: T) => number): Soma {
  return { n: xs.length, valor: r(xs.reduce((a, x) => a + c(valor(x)), 0)) };
}

/** Dias de calendário de `de` até `ate` (YYYY-MM-DD). Negativo quando `ate` vem antes. */
export function diasEntre(de: string, ate: string): number {
  const t = (iso: string) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10)));
  return Math.round((t(ate) - t(de)) / 86_400_000);
}

/** Fração 0–100 com 1 casa; NULL sem denominador (zero não é 0%). */
const pct = (parte: number, todo: number): number | null => (todo > 0 ? Math.round((parte / todo) * 1000) / 10 : null);

// ─── Recorrências ───────────────────────────────────────────────────────────
export type FaixaAtraso = 'ate30' | 'de31a60' | 'mais60';
export const FAIXAS_ATRASO: readonly FaixaAtraso[] = ['ate30', 'de31a60', 'mais60'];

export interface ResumoRecorrencias {
  aReceber: Soma;
  realizada: Soma;
  atraso: Soma;
  coberta: Soma;
  /** Valor a receber ÷ (a receber + em atraso), em %. NULL quando os dois são zero. */
  pctEmDia: number | null;
  /** Atraso por idade (dias desde o vencimento até hoje). */
  aging: { faixa: FaixaAtraso; n: number; valor: number }[];
  maiorAtrasoDias: number | null;
  /** A receber por produto (sem produto: o grupo), maior primeiro, com a participação em %. */
  porProduto: { produto: string; n: number; valor: number; pct: number | null }[];
}

export function resumoRecorrencias(cobrancas: CobrancaRecorrente[], hojeISO: string): ResumoRecorrencias {
  const de = (s: string) => cobrancas.filter((x) => x.situacao === s);
  const aReceber = somar(de('a_receber'), (x) => x.valor);
  const atrasadas = de('em_atraso_fora');
  const atraso = somar(atrasadas, (x) => x.valor);
  const faixa = (dias: number): FaixaAtraso => (dias <= 30 ? 'ate30' : dias <= 60 ? 'de31a60' : 'mais60');
  const aging = FAIXAS_ATRASO.map((f) => {
    const xs = atrasadas.filter((x) => faixa(Math.max(0, diasEntre(x.prevista, hojeISO))) === f);
    return { faixa: f, ...somar(xs, (x) => x.valor) };
  });
  const dias = atrasadas.map((x) => diasEntre(x.prevista, hojeISO));
  const prod = new Map<string, { n: number; cents: number }>();
  for (const x of de('a_receber')) {
    const k = x.produto ?? x.grupo;
    const p = prod.get(k) ?? { n: 0, cents: 0 };
    p.n += 1; p.cents += c(x.valor);
    prod.set(k, p);
  }
  const porProduto = [...prod.entries()]
    .map(([produto, p]) => ({ produto, n: p.n, valor: r(p.cents), pct: pct(p.cents, c(aReceber.valor)) }))
    .sort((a, b) => b.valor - a.valor || a.produto.localeCompare(b.produto, 'pt-BR'));
  return {
    aReceber, realizada: somar(de('realizada'), (x) => x.valor), atraso, coberta: somar(de('coberta_informado'), (x) => x.valor),
    pctEmDia: pct(c(aReceber.valor), c(aReceber.valor) + c(atraso.valor)),
    aging, maiorAtrasoDias: dias.length ? Math.max(...dias) : null, porProduto,
  };
}

// ─── Recebimentos informados ────────────────────────────────────────────────
export interface ResumoInformados {
  aReceber: Soma;
  aCobrar: Soma;
  recebidoHotmart: Soma;
  baixadoFora: Soma;
  /** Dias do atraso mais antigo a cobrar (data prevista até hoje). NULL sem atraso datado. */
  atrasoMaisAntigoDias: number | null;
  /** Próxima data prevista a receber (hoje ou depois), com quantos e quanto caem nela. */
  proximo: { data: string; n: number; valor: number } | null;
}

export function resumoInformados(lista: Informado[], hojeISO: string): ResumoInformados {
  const de = (s: string) => lista.filter((x) => x.situacao === s);
  const aCobrar = de('em_atraso_cobrar');
  const dias = aCobrar.filter((x) => x.data_prevista).map((x) => diasEntre(x.data_prevista!, hojeISO));
  const futuros = de('a_receber').filter((x) => x.data_prevista && x.data_prevista >= hojeISO);
  const data = futuros.reduce<string | null>((m, x) => (m == null || x.data_prevista! < m ? x.data_prevista! : m), null);
  const naData = futuros.filter((x) => x.data_prevista === data);
  return {
    aReceber: somar(de('a_receber'), (x) => x.valor),
    aCobrar: somar(aCobrar, (x) => x.valor),
    recebidoHotmart: somar(de('realizado_hotmart'), (x) => x.valor),
    baixadoFora: somar(de('baixado_fora'), (x) => x.valor),
    atrasoMaisAntigoDias: dias.length ? Math.max(...dias) : null,
    proximo: data ? { data, ...somar(naData, (x) => x.valor) } : null,
  };
}

// ─── Eventos planejados ─────────────────────────────────────────────────────
export interface ResumoEventos {
  ativos: number;
  encerrados: number;
  /** Soma do total esperado (cenário base) dos ativos que têm venda de referência. */
  previstoAtivos: number;
  /** Ativos sem venda de referência medida (total esperado desconhecido — não é zero). */
  semReferencia: number;
  /** Próxima abertura (hoje ou depois) entre os ativos. */
  proximo: { nome: string; abertura: string } | null;
  /** Não arquivados, maior previsto primeiro; `previsto` NULL = sem venda de referência. */
  porEvento: { id: number; nome: string; situacao: string; abertura: string; previsto: number | null }[];
}

export function resumoEventos(eventos: EventoPlanejado[], hojeISO: string): ResumoEventos {
  const ativos = eventos.filter((e) => e.situacao === 'ativo');
  const comValor = ativos.map((e) => totalEsperado(e, 'base')).filter((v): v is number => v != null);
  const futuros = ativos.filter((e) => e.abertura >= hojeISO).sort((a, b) => a.abertura.localeCompare(b.abertura));
  const porEvento = eventos.filter((e) => e.situacao !== 'arquivado')
    .map((e) => ({ id: e.id, nome: e.nome, situacao: e.situacao, abertura: e.abertura, previsto: totalEsperado(e, 'base') }))
    .sort((a, b) => (b.previsto ?? -1) - (a.previsto ?? -1) || a.abertura.localeCompare(b.abertura));
  return {
    ativos: ativos.length,
    encerrados: eventos.filter((e) => e.situacao === 'encerrado').length,
    previstoAtivos: r(comValor.reduce((a, v) => a + c(v), 0)),
    semReferencia: ativos.length - comValor.length,
    proximo: futuros[0] ? { nome: futuros[0].nome, abertura: futuros[0].abertura } : null,
    porEvento,
  };
}

// ─── Premissas ──────────────────────────────────────────────────────────────
export interface ResumoPremissas {
  total: number;
  /** Premissas com sugestão medida (valor), no cenário base. */
  comSugestao: number;
  /** Com sugestão medida E valor gravado na base diferente dela. */
  divergentes: number;
  /** Sem vigência gravada na base (o banco usa a sugestão, quando há). */
  semVigente: number;
}

export function resumoPremissas(premissas: PremissaTela[], sugestoes: Map<string, SugestaoPremissa>): ResumoPremissas {
  let comSugestao = 0; let divergentes = 0; let semVigente = 0;
  for (const p of premissas) {
    const base = p.cenarios.find((x) => x.cenario === 'base')?.vigente ?? null;
    if (!base) semVigente += 1;
    const s = sugestoes.get(p.chave_base)?.sugestao;
    if (s == null) continue;
    comSugestao += 1;
    if (base && base.valor !== valorDaSugestao(s, p.unidade)) divergentes += 1;
  }
  return { total: premissas.length, comSugestao, divergentes, semVigente };
}

// ─── Visão geral: o que mudou e previsto × realizado ────────────────────────
export interface ResumoMudancas {
  /** Soma por motivo em todos os grupos; maior |valor| primeiro. */
  porMotivo: { motivo: string; itens: number; valor: number }[];
  entrou: number;
  saiu: number;
  liquido: number;
}

export function resumoMudancas(mudancas: MudancaReceber[]): ResumoMudancas {
  const m = new Map<string, { itens: number; cents: number }>();
  for (const x of mudancas) {
    for (const mo of x.motivos) {
      const a = m.get(mo.motivo) ?? { itens: 0, cents: 0 };
      a.itens += mo.itens; a.cents += c(mo.valor);
      m.set(mo.motivo, a);
    }
  }
  const porMotivo = [...m.entries()].map(([motivo, a]) => ({ motivo, itens: a.itens, valor: r(a.cents) }))
    .filter((x) => x.itens > 0 || c(x.valor) !== 0)
    .sort((a, b) => Math.abs(b.valor) - Math.abs(a.valor) || a.motivo.localeCompare(b.motivo));
  const entrou = porMotivo.reduce((a, x) => a + Math.max(0, c(x.valor)), 0);
  const saiu = porMotivo.reduce((a, x) => a + Math.min(0, c(x.valor)), 0);
  return { porMotivo, entrou: r(entrou), saiu: r(saiu), liquido: r(entrou + saiu) };
}

export interface ResumoAcerto {
  /** Acerto do certo na semana medida mais recente. */
  ultima: number | null;
  /** Diferença em pontos para a semana anterior medida. NULL sem as duas. */
  variacaoPp: number | null;
  /** Média simples do acerto das semanas medidas (1 casa). */
  media: number | null;
  semanas: number;
}

/** `semanas` como vem de resumirPrevistoRealizado: mais nova primeiro. */
export function resumoAcerto(semanas: SemanaPrevistoRealizado[]): ResumoAcerto {
  const xs = semanas.map((s) => s.certoAcerto).filter((v): v is number => v != null);
  const media = xs.length ? Math.round((xs.reduce((a, v) => a + v, 0) / xs.length) * 10) / 10 : null;
  const [u, ant] = [semanas[0]?.certoAcerto ?? null, semanas[1]?.certoAcerto ?? null];
  return { ultima: u, variacaoPp: u != null && ant != null ? Math.round((u - ant) * 10) / 10 : null, media, semanas: xs.length };
}

// ─── Base auditável ─────────────────────────────────────────────────────────
/** A maior linha que soma (a receber), para o KPI do recorte filtrado. NULL sem linha a receber. */
export function maiorAReceber(linhas: LinhaReceber[]): LinhaReceber | null {
  let m: LinhaReceber | null = null;
  for (const l of linhas) if (l.situacao === 'a_receber' && (m == null || l.valor > m.valor)) m = l;
  return m;
}
