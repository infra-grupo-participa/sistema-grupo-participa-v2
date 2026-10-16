// Classificação do tráfego da Black pelo que o BANCO devolve (campo `linha` de campanha e conjunto, `no` e `isca` do
// conjunto, `fase` da campanha em dados_black_trafego): padrão de nomes do Caio, 16/10/2026. Este é o ÚNICO lugar da
// classificação: nenhuma tela lê nome de campanha para decidir funil, fase ou captação.
//
// Ausência do campo (a RPC ainda não devolve `linha`): vale o LEGADO, derivado de funil, etapa e fase que o mapeador já
// montava. Existe só para o front poder subir antes do banco sem quebrar a produção. Campo presente com null = o banco
// não reconheceu o nome: "Sem classificação", que aparece na tela e nunca vira zero nem some.
//
// O tipo e as constantes ficam em tipos.ts; aqui ficam as funções.
import {
  LINHAS_BLACK, NOS_BLACK,
  type Campanha, type Conjunto, type FiltroFunil, type Funil, type LinhaBlack, type LinhaPerfil, type NoBlack,
} from './tipos';

export function lerLinha(v: unknown): LinhaBlack | null {
  return typeof v === 'string' && (LINHAS_BLACK as readonly string[]).includes(v) ? (v as LinhaBlack) : null;
}
export function lerNo(v: unknown): NoBlack | null {
  return typeof v === 'string' && (NOS_BLACK as readonly string[]).includes(v) ? (v as NoBlack) : null;
}

/** Só estruturas de leitura: o IndiceTrafego de metricas.ts as satisfaz (sem import circular). */
export interface IndiceLinhas {
  campanha: ReadonlyMap<string, Campanha>;
  conjunto: ReadonlyMap<string, Conjunto>;
}

// ─── Legado (campo ausente na RPC) ───────────────────────────────────────────────────────────────────────────
const ehEntresafraLegado = (c: Campanha) => c.subtipo?.toLocaleUpperCase('pt-BR') === 'ENTRESAFRA' || /\bENTRESAFRA\b/i.test(c.nome);

/** Linha da campanha quando o banco não devolveu `linha`: funil, etapa e fase que o mapeador já tinha. */
export function linhaLegadaDaCampanha(c: Campanha): LinhaBlack | null {
  if (ehEntresafraLegado(c)) return 'pre_captacao';
  if (c.fase === 'remarketing' || /\bREMARKETING\b/i.test(c.nome)) return 'remarketing_pagina';
  if (c.funil === 'c1') return 'c1';
  if (c.funil === 'consultoria') return 'consultoria';
  if (c.funil === 'iscas') return 'iscas';
  if (c.funil === 'c3') return 'c3';
  if (c.fase === 'aquecimento') return 'lembrete';
  if (c.fase === 'live_carrinho') return 'carrinho';
  return null;
}

export function linhaDaCampanha(c: Campanha): LinhaBlack | null {
  return c.linha !== undefined ? c.linha : linhaLegadaDaCampanha(c);
}

/**
 * Linha do conjunto. O banco manda; sem o campo, herda da campanha, e na campanha `c2` (mistura) separa consultoria de
 * iscas pelo nó ou pela isca que o banco devolveu.
 */
export function linhaDoConjunto(cj: Conjunto, campanha: Campanha | null | undefined): LinhaBlack | null {
  if (cj.linha !== undefined) return cj.linha;
  const lc = campanha ? linhaDaCampanha(campanha) : null;
  if (lc === 'c2') return cj.no === 'consultoria' || cj.iscaBanco?.toLocaleUpperCase('pt-BR') === 'CONSULTORIA' ? 'consultoria' : 'iscas';
  return lc;
}

const PECA_C1: Record<string, NoBlack> = { TEASER: 'teaser', MANIFESTO: 'manifesto', REELS: 'reels_pago' };

/** Nó do conjunto. Sem o campo, deriva da linha (e, no C1, do subtipo que a campanha trouxe). */
export function noDoConjunto(cj: Conjunto, campanha: Campanha | null | undefined): NoBlack | null {
  if (cj.no !== undefined) return cj.no;
  const l = linhaDoConjunto(cj, campanha);
  switch (l) {
    case 'iscas': case 'consultoria': case 'c3': case 'remarketing_pagina': case 'lembrete': case 'fake_live':
    case 'remarketing_live': case 'carrinho': case 'pre_captacao': return l;
    case 'c1': return campanha?.subtipo ? PECA_C1[campanha.subtipo.toLocaleUpperCase('pt-BR')] ?? null : null;
    default: return null;
  }
}

// ─── Funil e captação a partir da linha ──────────────────────────────────────────────────────────────────────
/** Funil da tela de uma linha: C1 inclui a distribuição (PF), que a tela mostra separada dentro dele. */
export function funilDaLinha(l: LinhaBlack | null | undefined): Funil | null {
  switch (l) {
    case 'c1': case 'distribuicao': return 'c1';
    case 'consultoria': return 'consultoria';
    case 'iscas': case 'c2': return 'iscas';
    case 'c3': return 'c3';
    default: return null;
  }
}

/** Linhas que contam no investimento, no CPL e nas métricas de captação (decisão do Victor, 16/10/2026). */
export const LINHAS_CAPTACAO: ReadonlySet<LinhaBlack> = new Set<LinhaBlack>(['iscas', 'consultoria', 'c2', 'c3', 'remarketing_pagina']);
export const linhaEhCaptacao = (l: LinhaBlack | null | undefined): boolean => l != null && LINHAS_CAPTACAO.has(l);

/** O PREDICADO ÚNICO de captação para uma campanha. Pré-captação (CPF01, ENTRESAFRA) fica fora. */
export const contaNoInvestimentoCaptacao = (c: Campanha): boolean => linhaEhCaptacao(linhaDaCampanha(c));
export const ehPreCaptacao = (c: Campanha | null | undefined): boolean => !!c && linhaDaCampanha(c) === 'pre_captacao';

/** A linha entra no filtro global de funil? C2 = consultoria + iscas. Pré-captação nunca entra. */
export function linhaNoFunil(filtro: FiltroFunil, l: LinhaBlack | null | undefined): boolean {
  if (l === 'pre_captacao') return false;
  switch (filtro) {
    case 'todos': return true;
    case 'c1': return l === 'c1' || l === 'distribuicao';
    case 'c2': return l === 'consultoria' || l === 'iscas' || l === 'c2';
    case 'consultoria': return l === 'consultoria';
    case 'iscas': return l === 'iscas';
    case 'c3': return l === 'c3';
  }
}

/** 'divide' = campanha `c2` (mistura) diante de Consultoria ou Iscas: só o conjunto separa, e o gasto vem por anúncio. */
export function campanhaNoFunil(filtro: FiltroFunil, c: Campanha): 'sim' | 'nao' | 'divide' {
  const l = linhaDaCampanha(c);
  if (l === 'c2' && (filtro === 'consultoria' || filtro === 'iscas')) return 'divide';
  return linhaNoFunil(filtro, l) ? 'sim' : 'nao';
}

/** Funil pela porta do cadastro, só para lead que não casou com anúncio do tráfego. */
export function funilPortaIncluido(filtro: FiltroFunil, funil: Funil | null | undefined): boolean {
  return filtro === 'todos' || (filtro === 'c2' ? funil === 'consultoria' || funil === 'iscas' : funil === filtro);
}

/**
 * Linha do cadastro pelo conjunto (ou campanha) do anúncio que o trouxe. undefined = o cadastro não casou com anúncio
 * do tráfego (a tela usa a porta). Na campanha `c2` sem conjunto casado, a linha fica `c2` (só serve a C2 e Todos).
 */
export function linhaDoLead(l: Pick<LinhaPerfil, 'conjuntoId' | 'campanhaId'>, idx: IndiceLinhas): LinhaBlack | null | undefined {
  const cj = l.conjuntoId ? idx.conjunto.get(l.conjuntoId) : undefined;
  const c = cj ? idx.campanha.get(cj.campanhaId) : l.campanhaId ? idx.campanha.get(l.campanhaId) : undefined;
  if (!c) return undefined;
  return cj ? linhaDoConjunto(cj, c) : linhaDaCampanha(c);
}

/** O cadastro está no filtro de funil? Atribuído: pela linha do banco. Sem anúncio casado: pela porta. */
export function leadNoFunil(filtro: FiltroFunil, l: Pick<LinhaPerfil, 'conjuntoId' | 'campanhaId' | 'funil'>, idx?: IndiceLinhas): boolean {
  if (filtro === 'todos') return true;
  const linha = idx ? linhaDoLead(l, idx) : undefined;
  return linha === undefined ? funilPortaIncluido(filtro, l.funil) : linhaNoFunil(filtro, linha);
}

/** Isca do banco (string exata) -> rótulo das 3 iscas de página. CONSULTORIA é linha própria, não isca de página. */
export function iscaDoBanco(v: string | null | undefined): 'Fluxograma' | 'Futurômetro' | 'Checkup' | null {
  const s = (v ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').trim().toUpperCase();
  if (s === 'CHECKUP') return 'Checkup';
  if (s === 'FLUXOGRAMA') return 'Fluxograma';
  if (s === 'FUTUROMETRO') return 'Futurômetro';
  return null;
}
