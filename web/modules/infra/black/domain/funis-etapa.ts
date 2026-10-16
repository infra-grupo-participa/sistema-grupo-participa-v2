// Funis de uma etapa lado a lado (modal aberto pelo card da Visão geral), tudo pela LINHA do CONJUNTO que o banco devolve
// (padrão do Caio, 16/10/2026). C1: uma coluna por peça (`no`: Teaser, Manifesto, Reels pago) e a Distribuição (PF) à parte.
// Consultoria: o conjunto de `CAPTAÇÃO | ISCAS` com isca CONSULTORIA. Iscas: uma coluna por isca, sem a consultoria.
// C3: uma coluna por subtipo da campanha (ou o nome exato dela, quando não há subtipo). Campanha sem classificação NÃO
// entra em coluna: vai para "fora", com o nome exato. Pré-captação (CPF01, ENTRESAFRA) não conta em lugar nenhum.
import type { Campanha, Conjunto, DesempenhoDia, Funil, LinhaPerfil, NoBlack, TrafegoBlack, Valor } from './tipos';
import { ROTULO_NO } from './tipos';
import { linhaDaCampanha, linhaNoFunil, noDoConjunto } from './linha-black';
import type { IndiceTrafego } from './metricas';
import { ratear } from './rateio';

export interface ColunaFunil {
  /** Título da coluna: peça do C1, isca (Iscas), Consultoria, subtipo ou nome da campanha (C3). */
  rotulo: string;
  campanhas: Campanha[];
  /** Conjuntos da coluna que tiveram dado no recorte. */
  conjuntos: Conjunto[];
  dias: DesempenhoDia[];
  linhas: LinhaPerfil[];
  /**
   * Investimento da coluna. Campanha que cabe inteira na coluna entra pelo gasto da campanha (dias_campanha); campanha
   * repartida entre colunas (ou mista) entra com a parte do gasto da campanha proporcional aos anúncios dos conjuntos da
   * coluna (rateio.ts: a campanha é o dinheiro, o anúncio só divide). null = sem dado de alguma.
   */
  gasto: Valor;
}

export type MotivoFora = 'sem classificação';
export interface CampanhaFora { campanha: Campanha; motivo: MotivoFora }

export interface FunisDaEtapa {
  colunas: ColunaFunil[];
  /** Campanhas com dado no recorte que o banco não classificou (valem para qualquer etapa aberta). */
  fora: CampanhaFora[];
  /** Iscas: conjuntos de isca sem isca reconhecida pelo banco. */
  conjuntosSemIsca: Conjunto[];
}

export function motivoFora(c: Campanha): MotivoFora | null {
  return linhaDaCampanha(c) === null ? 'sem classificação' : null;
}

/** Peça do C1 em coluna: o `no` do conjunto; a distribuição (PF) tem coluna própria; sem peça, o nome da linha. */
function rotuloC1(no: NoBlack | null, linha: string | null): string {
  if (linha === 'distribuicao') return 'Distribuição';
  return no ? ROTULO_NO[no] : 'Sem peça';
}

/**
 * `dias` e `linhas` chegam já no período e no canal escolhidos, de todos os funis (o rateio precisa de todas as linhas da
 * campanha, não só as de um funil). Só entram conjuntos com dado no recorte (dia de desempenho). As linhas de cada coluna
 * (`col.dias`) saem já rateadas, então impressões e CPM da coluna continuam sobre o mesmo gasto do Investimento.
 */
export function funisDaEtapa(funil: Funil, trafego: TrafegoBlack, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego): FunisDaEtapa {
  const comDado = new Map<string, DesempenhoDia[]>();
  for (const d of ratear(dias, trafego, idx).dias) {
    const cj = idx.conjuntoDoAnuncio(d.anuncioId);
    if (!cj) continue;
    comDado.set(cj.id, [...(comDado.get(cj.id) ?? []), d]);
  }
  const campanhasComDado = new Set<string>();
  for (const id of comDado.keys()) { const cj = idx.conjunto.get(id); if (cj) campanhasComDado.add(cj.campanhaId); }

  const fora: CampanhaFora[] = [];
  for (const c of trafego.campanhas) {
    if (!campanhasComDado.has(c.id)) continue;
    const motivo = motivoFora(c);
    if (motivo) fora.push({ campanha: c, motivo });
  }

  // Conjuntos da etapa com dado: pela linha do conjunto (C2 mista separa consultoria de iscas aqui).
  const doFunil: Conjunto[] = [];
  for (const [id] of comDado) {
    const cj = idx.conjunto.get(id);
    if (!cj) continue;
    const linha = idx.linhaDoConjuntoPorId(id);
    if (linha === null || !linhaNoFunil(funil, linha)) continue;
    doFunil.push(cj);
  }

  const chaveDe = (cj: Conjunto): { chave: string; rotulo: string } | null => {
    const c = idx.campanha.get(cj.campanhaId);
    if (!c) return null;
    const linha = idx.linhaDoConjuntoPorId(cj.id);
    if (funil === 'c1') { const r = rotuloC1(noDoConjunto(cj, c), linha); return { chave: r, rotulo: r }; }
    if (funil === 'consultoria') return { chave: 'Consultoria', rotulo: 'Consultoria' };
    if (funil === 'iscas') return cj.isca ? { chave: cj.isca, rotulo: cj.isca } : null;
    const r = c.subtipo ?? c.nome; // C3
    return { chave: r, rotulo: r };
  };

  const grupos = new Map<string, { rotulo: string; conjuntos: Conjunto[] }>();
  const conjuntosSemIsca: Conjunto[] = [];
  for (const cj of doFunil) {
    const k = chaveDe(cj);
    if (!k) { if (funil === 'iscas') conjuntosSemIsca.push(cj); continue; }
    const g = grupos.get(k.chave) ?? { rotulo: k.rotulo, conjuntos: [] };
    g.conjuntos.push(cj); grupos.set(k.chave, g);
  }

  const colunas = [...grupos.values()].map((g): ColunaFunil => {
    const idsConjunto = new Set(g.conjuntos.map((j) => j.id));
    const idsCampanha = new Set(g.conjuntos.map((j) => j.campanhaId));
    const campanhas = trafego.campanhas.filter((c) => idsCampanha.has(c.id));
    const diasDaColuna = g.conjuntos.flatMap((j) => comDado.get(j.id) ?? []);
    // Uma campanha cabe inteira na coluna quando todos os seus conjuntos (do banco, não só os com dado) estão nela.
    const gastoPorCampanha = campanhas.map((c): Valor => {
      const todos = trafego.conjuntos.filter((j) => j.campanhaId === c.id);
      if (todos.every((j) => idsConjunto.has(j.id))) {
        const gc = trafego.gastoCampanhas?.find((x) => x.campanhaId === c.id);
        if (gc) return gc.gasto;
        if (c.semEntregaComprovada === true) return 0;
        return null;
      }
      const ds = diasDaColuna.filter((d) => idx.campanhaDoAnuncio(d.anuncioId)?.id === c.id);
      return ds.length ? ds.reduce((s, d) => s + Math.round(d.gasto * 100), 0) / 100 : null;
    });
    const gasto: Valor = gastoPorCampanha.length === 0 || gastoPorCampanha.some((x) => x === null) ? null : gastoPorCampanha.reduce<number>((s, x) => s + (x as number), 0);
    const leadsDaColuna = linhas.filter((l) => {
      if (l.conjuntoId) return idsConjunto.has(l.conjuntoId);
      // Sem conjunto casado: só entra quando a campanha inteira está na coluna e, nas Iscas, a isca do perfil é a da coluna.
      if (l.campanhaId === null || !idsCampanha.has(l.campanhaId)) return false;
      const todos = trafego.conjuntos.filter((j) => j.campanhaId === l.campanhaId);
      if (!todos.every((j) => idsConjunto.has(j.id))) return false;
      return funil !== 'iscas' || l.isca === g.rotulo;
    });
    return { rotulo: g.rotulo, campanhas, conjuntos: g.conjuntos, dias: diasDaColuna, linhas: leadsDaColuna, gasto };
  });
  return { colunas, fora, conjuntosSemIsca };
}
