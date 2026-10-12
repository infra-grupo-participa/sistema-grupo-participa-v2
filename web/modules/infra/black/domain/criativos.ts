// Aba "Criativos e páginas" (aprovada em 12/10): trilha Campanha › Conjunto › Criativo › Página com filtro
// cruzado. Cada painel vê os filtros dos OUTROS painéis (o próprio só destaca), para o escolhido continuar
// enxergando os irmãos. Métricas por soma sobre soma, no mesmo recorte de dias e leads.
import {
  agregar, connectRate, cpl, cpm, ctr, custoPorVisualizacao, ehPago, farolCpl, taxaVideo75, type Farol, type IndiceTrafego, type Taxa,
} from './metricas';
import { diaDe } from './recorte';
import type { Anuncio, DesempenhoDia, FiltroCriativos, LinhaPerfil, Valor } from './tipos';

export type PainelCriativos = 'campanha' | 'conjunto' | 'anuncio' | 'pagina';

/** O anúncio passa no filtro, ignorando o painel `exceto`. */
export function anuncioPassa(a: Anuncio, f: FiltroCriativos, idx: IndiceTrafego, exceto?: PainelCriativos): boolean {
  const cj = idx.conjunto.get(a.conjuntoId);
  if (exceto !== 'campanha' && f.campanha && cj?.campanhaId !== f.campanha) return false;
  if (exceto !== 'conjunto' && f.conjunto && a.conjuntoId !== f.conjunto) return false;
  if (exceto !== 'anuncio' && f.anuncio && a.id !== f.anuncio) return false;
  if (exceto !== 'pagina' && f.pagina && a.paginaId !== f.pagina) return false;
  return true;
}

export interface ResumoCriativo {
  gasto: number; impressoes: number; cpm: Valor; cliques: Valor; ctr: Taxa; lpv: Valor; connect: Taxa;
  leads: number; leadsPagos: number; cpl: Valor; farol: Farol; video75: Taxa; custoVisualizacao: Valor;
  /** true = distribuição (C1/antecipação): a métrica principal é custo por visualização, não CPL. */
  distribuicao: boolean;
}

export function resumir(
  dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego, regua: { meta: number; teto: number }, distribuicao: boolean,
): ResumoCriativo {
  const a = agregar(dias);
  const pagos = linhas.filter(ehPago).length;
  const valorCpl = distribuicao ? null : cpl(dias.length ? a.gasto : null, pagos);
  return {
    gasto: a.gasto, impressoes: a.impressoes, cpm: cpm(a), cliques: a.cliques.valor, ctr: ctr(a), lpv: a.lpv.valor,
    connect: connectRate(dias, idx), leads: linhas.length, leadsPagos: pagos, cpl: valorCpl,
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
  regua: { meta: number; teto: number }, nomePagina: (id: string) => string,
): ItemPainel[] {
  const grupos = new Map<string, { nome: string; anuncios: Set<string> }>();
  for (const a of idx.anuncio.values()) {
    if (!anuncioPassa(a, f, idx, qual)) continue;
    const cj = idx.conjunto.get(a.conjuntoId);
    let id: string | null = null; let nome = '';
    if (qual === 'campanha') { const c = cj ? idx.campanha.get(cj.campanhaId) : undefined; if (c) { id = c.id; nome = c.nome; } }
    else if (qual === 'conjunto') { if (cj) { id = cj.id; nome = cj.nome; } }
    else if (qual === 'anuncio') { id = a.id; nome = a.nome; }
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

export const ORDENS_GALERIA = ['leads', 'cpl', 'ctr', 'gasto'] as const;
export type OrdemGaleria = (typeof ORDENS_GALERIA)[number];
export const ROTULO_ORDEM: Record<OrdemGaleria, string> = { leads: 'Mais leads', cpl: 'Menor CPL', ctr: 'Maior CTR', gasto: 'Mais gasto' };

/** Ordena a galeria. Sem dado vai para o fim, sempre. */
export function ordenar(itens: readonly ItemPainel[], ordem: OrdemGaleria): ItemPainel[] {
  const chave = (i: ItemPainel): Valor => {
    if (ordem === 'leads') return i.resumo.distribuicao ? null : i.resumo.leadsPagos;
    if (ordem === 'cpl') return i.resumo.cpl;
    if (ordem === 'ctr') return i.resumo.ctr.valor;
    return i.resumo.gasto;
  };
  const sinal = ordem === 'cpl' ? 1 : -1;
  return [...itens].sort((a, b) => {
    const x = chave(a); const y = chave(b);
    if (x === null && y === null) return 0;
    if (x === null) return 1;
    if (y === null) return -1;
    return sinal * (x - y);
  });
}

/** Mini-funil do criativo: impressões → cliques → LPV → leads pagos → grupo (48h). */
export function serieDiariaAnuncio(anuncioId: string, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], periodo: readonly string[]) {
  const g = new Map<string, number>(); const imp = new Map<string, number>(); const ld = new Map<string, number>();
  for (const d of dias) if (d.anuncioId === anuncioId) { g.set(d.dia, (g.get(d.dia) ?? 0) + d.gasto); imp.set(d.dia, (imp.get(d.dia) ?? 0) + d.impressoes); }
  for (const l of linhas) if (l.anuncioId === anuncioId && ehPago(l)) { const k = diaDe(l.criadoEm); ld.set(k, (ld.get(k) ?? 0) + 1); }
  return periodo.map((dia) => ({ dia, gasto: g.get(dia) ?? 0, impressoes: imp.get(dia) ?? 0, leads: ld.get(dia) ?? 0 }));
}
