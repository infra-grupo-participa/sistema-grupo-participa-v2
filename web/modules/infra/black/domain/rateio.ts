// Rateio do gasto: a CAMPANHA é o dinheiro, o anúncio só DIVIDE (decisão do Victor, 16/10/2026).
//
// O gasto por campanha (dias_campanha, igual ao gerenciador) e o gasto por anúncio (dias_anuncio) vêm de coletas
// independentes, gravadas com alguns segundos de diferença; no dia em curso as duas somas não batem (c2: 517,79 por
// campanha, 520,21 por anúncio). Toda tela que divide uma campanha entre as suas partes (Consultoria x Iscas, cada isca,
// cada conjunto da C3, cada nó da Jornada) usa o gasto da campanha como total e o anúncio só como PESO:
//
//   parte = gasto da campanha x (gasto da parte por anúncio / gasto da campanha por anúncio), no mesmo recorte de dias.
//
// O arredondamento fecha ao centavo (maior resto, por linha dia x anúncio), então qualquer partição das linhas soma o
// gasto da campanha exato. Dia sem linha de anúncio (antes de `anuncioDesde`, ou recarga pendente) não entra no peso:
// o gasto da campanha desse dia fica em `semDetalhe` e nunca é espalhado sobre os dias que têm detalhe (senão a campanha
// teria as suas partes infladas).
import type { IndiceTrafego } from './metricas';
import { campanhaNoFunil, ehPreCaptacao, linhaDaCampanha } from './linha-black';
import type { Campanha, DesempenhoDia, FiltroCanal, FiltroFunil, LinhaBlack, Valor } from './tipos';

export interface FonteRateio {
  gastoCampanhas?: readonly { campanhaId: string; gasto: number }[];
  gastoCampanhasDiario?: readonly { campanhaId: string; dia: string; gasto: number }[];
}

export interface Rateio {
  /** As mesmas linhas, com o gasto já rateado. Campanha sem gasto por campanha na fonte fica como veio. */
  dias: DesempenhoDia[];
  /** Por campanha: gasto da campanha que nenhum anúncio explica (sem linha de anúncio no recorte), em reais. */
  semDetalhe: Map<string, number>;
}

const centavos = (reais: number) => Math.round(reais * 100);

/** Divide `total` (centavos) entre os pesos (centavos) pelo maior resto; a soma dos resultados é exatamente `total`. */
function dividirEmCentavos(total: number, pesos: readonly number[]): number[] {
  const soma = pesos.reduce((s, p) => s + p, 0);
  const base = pesos.map((p) => Math.floor((total * p) / soma));
  let resto = total - base.reduce((s, x) => s + x, 0);
  const ordem = pesos.map((p, i) => ({ i, frac: (total * p) / soma - base[i] })).sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; resto > 0 && k < ordem.length; k += 1, resto -= 1) base[ordem[k].i] += 1;
  return base;
}

const cache = new WeakMap<readonly DesempenhoDia[], { gc: unknown; gd: unknown; idx: IndiceTrafego; r: Rateio }[]>();

export function ratear(dias: readonly DesempenhoDia[], fonte: FonteRateio | undefined, idx: IndiceTrafego): Rateio {
  const gc = fonte?.gastoCampanhas;
  if (!gc) return { dias: [...dias], semDetalhe: new Map() };
  const gd = fonte?.gastoCampanhasDiario;
  const guardados = cache.get(dias) ?? [];
  const achado = guardados.find((x) => x.gc === gc && x.gd === gd && x.idx === idx);
  if (achado) return achado.r;

  const gastoDaCampanha = new Map(gc.map((x) => [x.campanhaId, centavos(x.gasto)]));
  const diarioPorCampanha = new Map<string, Map<string, number>>();
  for (const x of gd ?? []) {
    const m = diarioPorCampanha.get(x.campanhaId) ?? new Map<string, number>();
    m.set(x.dia, (m.get(x.dia) ?? 0) + centavos(x.gasto));
    diarioPorCampanha.set(x.campanhaId, m);
  }
  const porCampanha = new Map<string, number[]>();
  dias.forEach((d, i) => {
    const id = idx.campanhaDoAnuncio(d.anuncioId)?.id;
    if (id === undefined || !gastoDaCampanha.has(id)) return;
    const lista = porCampanha.get(id);
    if (lista) lista.push(i); else porCampanha.set(id, [i]);
  });

  const saida = [...dias];
  const semDetalhe = new Map<string, number>();
  for (const [id, total] of gastoDaCampanha) {
    const indices = porCampanha.get(id) ?? [];
    const diario = diarioPorCampanha.get(id);
    // Peso = linhas dos dias em que a campanha também tem gasto na fonte por campanha. Sem a série diária, vale o período todo.
    const noPeso = diario ? indices.filter((i) => diario.has(dias[i].dia)) : indices;
    const pesos = noPeso.map((i) => centavos(dias[i].gasto));
    const somaPesos = pesos.reduce((s, p) => s + p, 0);
    const diasComDetalhe = new Set(noPeso.map((i) => dias[i].dia));
    const alvo = somaPesos <= 0 ? 0
      : diario ? Math.min(total, [...diasComDetalhe].reduce((s, dia) => s + (diario.get(dia) ?? 0), 0)) : total;
    if (somaPesos > 0) {
      const novos = dividirEmCentavos(alvo, pesos);
      noPeso.forEach((i, k) => { saida[i] = { ...dias[i], gasto: novos[k] / 100 }; });
    }
    const resto = total - (somaPesos > 0 ? alvo : 0);
    if (resto > 0) semDetalhe.set(id, resto / 100);
  }
  const r: Rateio = { dias: saida, semDetalhe };
  guardados.push({ gc, gd, idx, r });
  cache.set(dias, guardados);
  return r;
}

/**
 * Gasto de uma parte (os anúncios da campanha cuja linha passa em `pertence`) já rateado. null = a campanha não tem linha
 * de anúncio dessa parte no recorte (sem dado, nunca zero). Soma em centavos para fechar exato.
 */
export function gastoDaParte(r: Rateio, idx: IndiceTrafego, campanhaId: string, pertence: (l: LinhaBlack | null) => boolean = () => true): Valor {
  let soma = 0; let k = 0;
  for (const d of r.dias) {
    if (idx.campanhaDoAnuncio(d.anuncioId)?.id !== campanhaId || !pertence(idx.linhaDoAnuncio(d.anuncioId))) continue;
    soma += centavos(d.gasto); k += 1;
  }
  return k === 0 ? null : soma / 100;
}

/** Soma do `semDetalhe` das campanhas que passam em `aceita`, em reais (0 quando não há). */
export function somaSemDetalhe(r: Rateio, idx: IndiceTrafego, aceita: (c: Campanha) => boolean): number {
  let s = 0;
  for (const [id, v] of r.semDetalhe) { const c = idx.campanha.get(id); if (c && aceita(c)) s += centavos(v); }
  return s / 100;
}

const noCanal = (c: Campanha, canal: FiltroCanal) => canal === 'todos' || c.canal === canal;

/**
 * `semDetalhe` das campanhas que entram INTEIRAS no funil (campanhaNoFunil = 'sim', pré-captação fora), no canal. Cobre a campanha
 * que tem gasto e nenhum anúncio no recorte (a coleta de anúncios atrasou): o gasto dela vale pelo valor da campanha.
 */
export function semDetalheDoFunil(r: Rateio, idx: IndiceTrafego, funil: FiltroFunil, canal: FiltroCanal = 'todos'): number {
  return somaSemDetalhe(r, idx, (c) => !ehPreCaptacao(c) && campanhaNoFunil(funil, c) === 'sim' && noCanal(c, canal));
}

/** `semDetalhe` da campanha MISTA (`c2`, Consultoria + Iscas): não tem como dividir sem anúncio, então não vai para nó nem etapa. */
export function semDetalheMista(r: Rateio, idx: IndiceTrafego, canal: FiltroCanal = 'todos'): number {
  return somaSemDetalhe(r, idx, (c) => linhaDaCampanha(c) === 'c2' && noCanal(c, canal));
}
