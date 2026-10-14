// Aba "Criativos e páginas" (aprovada em 12/10): trilha Campanha › Conjunto › Criativo › Página com filtro
// cruzado. Cada painel vê os filtros dos OUTROS painéis (o próprio só destaca), para o escolhido continuar
// enxergando os irmãos. Métricas por soma sobre soma, no mesmo recorte de dias e leads.
import {
  agregar, cpm, ctr, custoPorVisualizacao, ehPago, farolCpl, taxaVideo75,
  type Farol, type IndiceTrafego, type Taxa,
} from './metricas';
import { connectRate, conversaoPagina, cplCaptacao, ingressoGrupoGeral, leadsDoTrafego, leadsPessoas, mql } from './numeros';
import { diaDe } from './recorte';
import type { Anuncio, DesempenhoDia, FiltroCriativos, LinhaPerfil, ReguaCpl, Valor } from './tipos';

export type PainelCriativos = 'campanha' | 'conjunto' | 'anuncio' | 'pagina';

/**
 * Criativo = todos os anúncios com o MESMO NOME, exato (Victor, 13/10/2026). No Meta o mesmo criativo vira um anúncio
 * por conjunto (74 anúncios para 18 nomes em 04-12/10); a tela mostra um cartão por nome, somando os conjuntos onde ele
 * roda. O id do cartão (e o `cr` da URL) é o do primeiro anúncio do grupo, em ordem de id, para ser estável.
 * Nome vazio não agrupa: cada anúncio sem nome é um criativo.
 */
const GRUPOS_POR_NOME = new WeakMap<object, Map<string, string[]>>();
function irmaosPorNome(idx: IndiceTrafego): Map<string, string[]> {
  const guardado = GRUPOS_POR_NOME.get(idx.anuncio);
  if (guardado) return guardado;
  const m = new Map<string, string[]>();
  for (const a of idx.anuncio.values()) { if (!a.nome) continue; (m.get(a.nome) ?? m.set(a.nome, []).get(a.nome)!).push(a.id); }
  for (const ids of m.values()) ids.sort();
  GRUPOS_POR_NOME.set(idx.anuncio, m);
  return m;
}
/** Todos os anúncios do mesmo criativo (inclui o próprio). Id desconhecido: só ele. */
export function anunciosDoCriativo(idx: IndiceTrafego, anuncioId: string): string[] {
  const a = idx.anuncio.get(anuncioId);
  return a?.nome ? irmaosPorNome(idx).get(a.nome) ?? [anuncioId] : [anuncioId];
}
/** Id que representa o criativo (o menor id entre os anúncios de mesmo nome). */
export const idDoCriativo = (idx: IndiceTrafego, anuncioId: string): string => anunciosDoCriativo(idx, anuncioId)[0];

/** O anúncio passa no filtro, ignorando o painel `exceto`. */
export function anuncioPassa(a: Anuncio, f: FiltroCriativos, idx: IndiceTrafego, exceto?: PainelCriativos): boolean {
  const cj = idx.conjunto.get(a.conjuntoId);
  if (exceto !== 'campanha' && f.campanha && cj?.campanhaId !== f.campanha) return false;
  if (exceto !== 'conjunto' && f.conjunto && a.conjuntoId !== f.conjunto) return false;
  if (exceto !== 'anuncio' && f.anuncio && idDoCriativo(idx, a.id) !== idDoCriativo(idx, f.anuncio)) return false;
  if (exceto !== 'pagina' && f.pagina && a.paginaId !== f.pagina) return false;
  return true;
}

export interface ResumoCriativo {
  gasto: number; impressoes: number; cpm: Valor; cliques: Valor; ctr: Taxa; lpv: Valor; connect: Taxa;
  leads: number; leadsPagos: number; mql: Taxa; conversao: Taxa & { recorte: string }; cpl: Valor; farol: Farol; video75: Taxa; custoVisualizacao: Valor;
  /** true = distribuição (C1/antecipação): a métrica principal é custo por visualização, não CPL. */
  distribuicao: boolean;
}

export function resumir(
  dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego, regua: ReguaCpl | null, distribuicao: boolean,
): ResumoCriativo {
  const a = agregar(dias);
  const pagos = leadsDoTrafego(linhas, idx).valor ?? 0;
  // A proporção por criativo é exatamente sobre leads pagos (a mesma base do CPL), não sobre todos os cadastros.
  const linhasPagas = linhas.filter(ehPago);
  const resultadoMql = mql(linhasPagas, 'pessoas únicas pagas neste criativo');
  const conversao = conversaoPagina(dias, linhas, idx);
  const valorCpl = distribuicao ? null : cplCaptacao(dias.length ? a.gasto : null, {
    valor: pagos, num: pagos, den: null, recorte: 'pessoas únicas pagas neste criativo', nota: null,
  }).valor;
  return {
    gasto: a.gasto, impressoes: a.impressoes, cpm: cpm(a), cliques: a.cliques.valor, ctr: ctr(a), lpv: a.lpv.valor,
    connect: connectRate(dias, idx), leads: leadsPessoas(linhas).valor ?? 0, leadsPagos: pagos,
    mql: resultadoMql, conversao, cpl: valorCpl,
    farol: distribuicao ? 'sem' : farolCpl(valorCpl, regua), video75: taxaVideo75(a), custoVisualizacao: custoPorVisualizacao(a), distribuicao,
  };
}

const ehDistribuicao = (idx: IndiceTrafego, anuncioId: string) => {
  const c = idx.campanhaDoAnuncio(anuncioId);
  return c === null || c.funil === 'c1' || c.funil === null;
};

export interface ItemPainel { id: string; nome: string; resumo: ResumoCriativo; anuncios: string[] }

/** Agrupa os anúncios que passam no filtro (menos o do próprio painel) pela chave do painel. */
export function painel(
  qual: PainelCriativos, f: FiltroCriativos, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego,
  regua: ReguaCpl | null, nomePagina: (id: string) => string,
): ItemPainel[] {
  const grupos = new Map<string, { nome: string; anuncios: Set<string> }>();
  for (const a of idx.anuncio.values()) {
    if (!anuncioPassa(a, f, idx, qual)) continue;
    const cj = idx.conjunto.get(a.conjuntoId);
    let id: string | null = null; let nome = '';
    if (qual === 'campanha') { const c = cj ? idx.campanha.get(cj.campanhaId) : undefined; if (c) { id = c.id; nome = c.nome; } }
    else if (qual === 'conjunto') { if (cj) { id = cj.id; nome = cj.nome; } }
    else if (qual === 'anuncio') { id = idDoCriativo(idx, a.id); nome = a.nome; }
    else if (a.paginaId) { id = a.paginaId; nome = nomePagina(a.paginaId); }
    if (id === null) continue;
    const g = grupos.get(id) ?? { nome, anuncios: new Set<string>() };
    g.anuncios.add(a.id); grupos.set(id, g);
  }
  const porAnuncioDias = new Map<string, DesempenhoDia[]>();
  for (const d of dias) (porAnuncioDias.get(d.anuncioId) ?? porAnuncioDias.set(d.anuncioId, []).get(d.anuncioId)!).push(d);
  const porAnuncioLinhas = new Map<string, LinhaPerfil[]>();
  for (const l of linhas) if (l.anuncioId) (porAnuncioLinhas.get(l.anuncioId) ?? porAnuncioLinhas.set(l.anuncioId, []).get(l.anuncioId)!).push(l);
  const out: ItemPainel[] = [];
  for (const [id, g] of grupos) {
    const ids = [...g.anuncios];
    const ds = ids.flatMap((x) => porAnuncioDias.get(x) ?? []);
    if (ds.length === 0) continue; // sem veiculação no período: fica fora do painel
    const ls = ids.flatMap((x) => porAnuncioLinhas.get(x) ?? []);
    out.push({ id, nome: g.nome, anuncios: ids, resumo: resumir(ds, ls, idx, regua, ids.every((x) => ehDistribuicao(idx, x))) });
  }
  return out.sort((a, b) => b.resumo.gasto - a.resumo.gasto);
}

export const ORDENS_GALERIA = ['leads', 'cpl', 'ctr', 'gasto', 'mql'] as const;
export type OrdemGaleria = (typeof ORDENS_GALERIA)[number];
export const ROTULO_ORDEM: Record<OrdemGaleria, string> = { leads: 'Mais leads', cpl: 'Menor CPL', ctr: 'Maior CTR', gasto: 'Mais gasto', mql: 'Maior % de MQL' };

/** Valor que a ordem usa (a galeria mostra este número no cartão, para a ordem ficar visível). */
export function valorOrdem(i: ItemPainel, ordem: OrdemGaleria): Valor {
  if (ordem === 'leads') return i.resumo.distribuicao ? null : i.resumo.leadsPagos;
  if (ordem === 'cpl') return i.resumo.cpl;
  if (ordem === 'ctr') return i.resumo.ctr.valor;
  if (ordem === 'mql') return i.resumo.leadsPagos < 5 ? null : i.resumo.mql.valor;
  return i.resumo.gasto;
}

/** Ordena a galeria. Sem dado vai para o fim, sempre. Empate: mais gasto primeiro, depois o nome (ordem estável). */
export function ordenar(itens: readonly ItemPainel[], ordem: OrdemGaleria): ItemPainel[] {
  const sinal = ordem === 'cpl' ? 1 : -1;
  return [...itens].sort((a, b) => {
    const x = valorOrdem(a, ordem); const y = valorOrdem(b, ordem);
    if (x === null && y !== null) return 1;
    if (y === null && x !== null) return -1;
    if (x !== null && y !== null && x !== y) return sinal * (x - y);
    if (a.resumo.gasto !== b.resumo.gasto) return b.resumo.gasto - a.resumo.gasto;
    return a.nome.localeCompare(b.nome, 'pt-BR');
  });
}

/** Etapa do funil do criativo. `ponte` = taxa de passagem da etapa ANTERIOR para esta (a primeira não tem). */
export interface EtapaFunil { chave: string; rotulo: string; valor: Valor; ponte: { rotulo: string; taxa: Taxa } | null; subtexto?: string }

/**
 * Funil do criativo (12/10, trapézios). Captação: impressões → cliques → views da página → leads pagos → total de MQL
 * → ingresso no grupo, com CTR, connect rate, conversão da página, % de MQL e taxa de ingresso nas pontes. Desde 13/10
 * o ingresso é o geral do criativo (sem janela de 48h) sobre os leads gerais, e a etapa de MQL entra antes dele. Distribuição (C1):
 * impressões → vídeo 75%. Toda taxa vem de `metricas.ts` (soma sobre soma, mesmo recorte de dias e leads).
 * Atenção: MQL e ingresso contam pessoas únicas de TODOS os leads do criativo (pagos ou não), não só os pagos.
 */
export function funilCriativo(
  r: ResumoCriativo, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[],
): EtapaFunil[] {
  if (r.distribuicao) {
    return [
      { chave: 'impressoes', rotulo: 'Impressões', valor: r.impressoes, ponte: null },
      { chave: 'video75', rotulo: 'Vídeo 75%', valor: r.video75.num, ponte: { rotulo: 'Taxa de vídeo 75%', taxa: r.video75 } },
    ];
  }
  const mql = resumoMql(linhas);
  const grupo = ingressoGrupoGeral(linhas);
  return [
    { chave: 'impressoes', rotulo: 'Impressões', valor: r.impressoes, ponte: null },
    { chave: 'cliques', rotulo: 'Cliques', valor: r.cliques, ponte: { rotulo: 'CTR', taxa: r.ctr } },
    { chave: 'lpv', rotulo: 'Views da página', valor: r.lpv, ponte: { rotulo: 'Connect rate', taxa: r.connect } },
    { chave: 'leads', rotulo: 'Leads pagos', valor: r.leadsPagos, ponte: { rotulo: 'Conversão da página', taxa: r.conversao } },
    { chave: 'mql', rotulo: 'Total de MQL', valor: mql.num, ponte: { rotulo: '% de MQL', taxa: mql } },
    { chave: 'grupo', rotulo: 'Ingresso geral · todos os leads', valor: grupo.num, ponte: { rotulo: 'Taxa geral de ingresso', taxa: grupo } },
  ];
}

function resumoMql(linhas: readonly LinhaPerfil[]) { return mql(linhas); }

/** Série diária do criativo: investimento, impressões e leads pagos por dia do período (dia sem nada = 0). */
export function serieDiariaAnuncio(anuncio: string | readonly string[], dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], periodo: readonly string[]) {
  const alvo = new Set(typeof anuncio === 'string' ? [anuncio] : anuncio);
  const g = new Map<string, number>(); const imp = new Map<string, number>(); const ld = new Map<string, number>();
  for (const d of dias) if (alvo.has(d.anuncioId)) { g.set(d.dia, (g.get(d.dia) ?? 0) + d.gasto); imp.set(d.dia, (imp.get(d.dia) ?? 0) + d.impressoes); }
  for (const l of linhas) if (l.anuncioId !== null && alvo.has(l.anuncioId) && ehPago(l)) { const k = diaDe(l.criadoEm); ld.set(k, (ld.get(k) ?? 0) + 1); }
  return periodo.map((dia) => ({ dia, gasto: g.get(dia) ?? 0, impressoes: imp.get(dia) ?? 0, leads: ld.get(dia) ?? 0 }));
}
