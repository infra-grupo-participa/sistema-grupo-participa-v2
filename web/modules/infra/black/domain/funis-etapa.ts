// Funis de uma etapa lado a lado (modal aberto pelo card da Visão geral).
// Uma coluna por subtipo do banco (mkt_trafego.etapa_black) dentro da etapa; nas Iscas, uma coluna por isca (último
// bloco do nome do conjunto). Campanha sem etapa, com conflito ou sem subtipo reconhecido NÃO entra em coluna: vai para
// "fora dos funis", com o nome exato, para o modal avisar quantas ficaram de fora. Nada aqui inventa rótulo.
import type { Campanha, Conjunto, DesempenhoDia, Funil, LinhaPerfil, TrafegoBlack } from './tipos';
import { ehEntresafraCampanha, type IndiceTrafego } from './metricas';
import { iscaDoNomeConjunto } from './ritmo';

export interface ColunaFunil {
  /** Subtipo exato do banco (C1, Consultoria, C3) ou isca (Iscas): é o título da coluna. */
  rotulo: string;
  campanhas: Campanha[];
  /** Só nas Iscas: conjuntos cuja isca (último bloco do nome) é a da coluna. */
  conjuntos: Conjunto[];
  dias: DesempenhoDia[];
  linhas: LinhaPerfil[];
}

export type MotivoFora = 'sem etapa' | 'conflito de subtipo' | 'sem subtipo reconhecido';
export interface CampanhaFora { campanha: Campanha; motivo: MotivoFora }

export interface FunisDaEtapa {
  colunas: ColunaFunil[];
  /** Campanhas com dado no recorte que não entram em nenhum funil (valem para qualquer etapa aberta). */
  fora: CampanhaFora[];
  /** Iscas: conjuntos de campanha de isca sem isca reconhecida no nome. */
  conjuntosSemIsca: Conjunto[];
}

export function motivoFora(c: Campanha): MotivoFora | null {
  if (c.etapa === null || c.etapa === undefined) return 'sem etapa';
  if (c.conflito === true) return 'conflito de subtipo';
  if (c.funil === null || !c.subtipo) return 'sem subtipo reconhecido';
  return null;
}

/**
 * `dias` e `linhas` chegam já no período e no canal escolhidos, de todos os funis. Só entram campanhas com dado no
 * recorte (dia de desempenho) e fora da Entresafra, que não conta em lugar nenhum.
 */
export function funisDaEtapa(funil: Funil, trafego: TrafegoBlack, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego): FunisDaEtapa {
  const comDado = new Set(dias.map((x) => idx.campanhaDoAnuncio(x.anuncioId)?.id).filter((x): x is string => Boolean(x)));
  const candidatas = trafego.campanhas.filter((c) => comDado.has(c.id) && !ehEntresafraCampanha(c));
  const fora: CampanhaFora[] = [];
  const dentro: Campanha[] = [];
  for (const c of candidatas) {
    const motivo = motivoFora(c);
    if (motivo) fora.push({ campanha: c, motivo });
    else if (c.funil === funil) dentro.push(c);
  }
  const diasDe = (ids: ReadonlySet<string>) => dias.filter((x) => { const c = idx.campanhaDoAnuncio(x.anuncioId); return !!c && ids.has(c.id); });

  if (funil !== 'iscas') {
    const porSubtipo = new Map<string, Campanha[]>();
    for (const c of dentro) {
      const chave = c.subtipo as string;
      porSubtipo.set(chave, [...(porSubtipo.get(chave) ?? []), c]);
    }
    const colunas = [...porSubtipo.entries()].map(([rotulo, campanhas]): ColunaFunil => {
      const ids = new Set(campanhas.map((c) => c.id));
      return { rotulo, campanhas, conjuntos: [], dias: diasDe(ids), linhas: linhas.filter((l) => l.campanhaId !== null && ids.has(l.campanhaId)) };
    });
    return { colunas, fora, conjuntosSemIsca: [] };
  }

  const idsIsca = new Set(dentro.map((c) => c.id));
  const conjuntos = trafego.conjuntos.filter((j) => idsIsca.has(j.campanhaId));
  const iscaDoConjunto = new Map(conjuntos.map((j) => [j.id, iscaDoNomeConjunto(j.nome)]));
  const conjuntosSemIsca = conjuntos.filter((j) => iscaDoConjunto.get(j.id) === null
    && dias.some((x) => idx.conjuntoDoAnuncio(x.anuncioId)?.id === j.id));
  const iscas = [...new Set([...iscaDoConjunto.values()].filter((x): x is string => x !== null))];
  const colunas = iscas.map((rotulo): ColunaFunil => {
    const doConjunto = conjuntos.filter((j) => iscaDoConjunto.get(j.id) === rotulo);
    const idsConjunto = new Set(doConjunto.map((j) => j.id));
    const campanhas = dentro.filter((c) => doConjunto.some((j) => j.campanhaId === c.id));
    return {
      rotulo, campanhas, conjuntos: doConjunto,
      dias: dias.filter((x) => { const j = idx.conjuntoDoAnuncio(x.anuncioId); return !!j && idsConjunto.has(j.id); }),
      // O lead de isca vem do campo isca do perfil, nunca do nome do conjunto.
      linhas: linhas.filter((l) => l.isca === rotulo && l.campanhaId !== null && idsIsca.has(l.campanhaId)),
    };
  }).filter((c) => c.dias.length > 0 || c.linhas.length > 0);
  return { colunas, fora, conjuntosSemIsca };
}
