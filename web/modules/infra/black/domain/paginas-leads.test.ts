import { describe, expect, it } from 'vitest';
import { mapearPaginasPorLeadsPagos } from './paginas-leads';
import type { TrafegoBlack } from './tipos';

const trafego: TrafegoBlack = {
  campanhas: [], conjuntos: [], paginas: [],
  anuncios: [
    { id: 'anuncio-a', conjuntoId: 'cj-a', nome: 'A', formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null },
    { id: 'anuncio-b', conjuntoId: 'cj-b', nome: 'B', formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null },
  ],
  dias: [], totais: [], coletadoEm: null,
};
const linha = (anuncioId: string, pagina: string | null, origem: 'pago' | 'organico' = 'pago') => ({
  leadId: `${anuncioId}-${pagina}`, pessoaId: `${anuncioId}-${pagina}`, criadoEm: '2026-10-13T12:00:00-03:00', primeiraPorta: true,
  porta: null, funil: null, isca: null, conjuntoC3: null, campanhaId: null, conjuntoId: null, anuncioId, paginaId: null,
  origem, canal: null, utmSource: null, utmMedium: null, utmCampaign: null, utmContent: null, utmTerm: null,
  profissao: null, profissaoBruta: null, uf: null, ufOrigem: null, listaOrigem: null, temperaturaBase: null, jaNaBase: null,
  entrouGrupoEm: null, teste: false, pagina,
});

describe('mapearPaginasPorLeadsPagos', () => {
  it('mapeia só a página exata ligada a lead pago do anúncio e não inventa URL', () => {
    const r = mapearPaginasPorLeadsPagos(trafego, [linha('anuncio-a', 'captacao'), linha('anuncio-b', 'consultoria', 'organico')]);
    expect(r.anuncios.map((a) => a.paginaId)).toEqual(['lead-page:captacao', null]);
    expect(r.paginas).toEqual([{ id: 'lead-page:captacao', url: '', rotulo: 'captacao', porta: null, isca: null }]);
  });
  it('não atribui uma página quando leads pagos do mesmo anúncio apontam a origens diferentes', () => {
    const r = mapearPaginasPorLeadsPagos(trafego, [linha('anuncio-a', 'captacao'), linha('anuncio-a', 'consultoria')]);
    expect(r.anuncios[0].paginaId).toBeNull();
    expect(r.paginas).toEqual([]);
  });
});
