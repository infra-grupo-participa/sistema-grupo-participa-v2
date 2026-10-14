import type { LinhaPerfil, Pagina, TrafegoBlack } from './tipos';

/**
 * Atribui página ao anúncio somente quando leads pagos daquele anúncio apontam para uma única página exata.
 * Não inventa URL nem distribui gasto/LPV entre páginas que a fonte não relacionou.
 */
export function mapearPaginasPorLeadsPagos(trafego: TrafegoBlack, linhas: readonly LinhaPerfil[]): TrafegoBlack {
  const paginasPorAnuncio = new Map<string, Set<string>>();
  const linhasPorPagina = new Map<string, LinhaPerfil[]>();
  for (const linha of linhas) {
    if (linha.origem !== 'pago' || !linha.anuncioId || !linha.pagina?.trim()) continue;
    const paginas = paginasPorAnuncio.get(linha.anuncioId) ?? new Set<string>();
    paginas.add(linha.pagina.trim());
    paginasPorAnuncio.set(linha.anuncioId, paginas);
    const associadas = linhasPorPagina.get(linha.pagina.trim()) ?? [];
    associadas.push(linha);
    linhasPorPagina.set(linha.pagina.trim(), associadas);
  }

  const idPorNome = new Map<string, string>();
  const paginas: Pagina[] = [];
  const anuncios = trafego.anuncios.map((anuncio) => {
    const nomes = paginasPorAnuncio.get(anuncio.id);
    if (!nomes || nomes.size !== 1) return { ...anuncio, paginaId: null };
    const [rotulo] = nomes;
    let id = idPorNome.get(rotulo);
    if (!id) {
      id = `lead-page:${encodeURIComponent(rotulo)}`;
      idPorNome.set(rotulo, id);
      const associadas = linhasPorPagina.get(rotulo) ?? [];
      const portas = new Set(associadas.map((linha) => linha.porta).filter((porta) => porta !== null));
      const iscas = new Set(associadas.map((linha) => linha.isca).filter((isca) => isca !== null));
      paginas.push({ id, url: '', rotulo, porta: portas.size === 1 ? [...portas][0] : null, isca: iscas.size === 1 ? [...iscas][0] : null });
    }
    return { ...anuncio, paginaId: id };
  });

  return { ...trafego, anuncios, paginas };
}
