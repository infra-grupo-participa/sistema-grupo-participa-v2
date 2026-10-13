// Casa o lead (ids do Meta, vindos da utm) com o tráfego (ids internos de mkt_trafego). Só o anúncio tem os dois
// ids (anuncios.anuncio_externa); campanha e conjunto internos saem da hierarquia do anúncio casado. Lead cujo anúncio
// do Meta não está no tráfego fica sem campanha, conjunto e anúncio internos (não se deduz pela campanha do Meta:
// dados_black_trafego não expõe o id externo da campanha nem do conjunto).
import type { LinhaPerfil, TrafegoBlack } from './tipos';

export function alinharIds(linhas: LinhaPerfil[], trafego: TrafegoBlack): LinhaPerfil[] {
  const porExterno = new Map<string, { anuncioId: string; conjuntoId: string }>();
  for (const a of trafego.anuncios) if (a.idExterno) porExterno.set(a.idExterno, { anuncioId: a.id, conjuntoId: a.conjuntoId });
  if (porExterno.size === 0) return linhas;
  const campanhaDoConjunto = new Map(trafego.conjuntos.map((j) => [j.id, j.campanhaId]));
  return linhas.map((l) => {
    if (l.anuncioId || !l.anuncioMeta) return l;
    const a = porExterno.get(l.anuncioMeta);
    if (!a) return l;
    return { ...l, anuncioId: a.anuncioId, conjuntoId: a.conjuntoId, campanhaId: campanhaDoConjunto.get(a.conjuntoId) ?? null };
  });
}
