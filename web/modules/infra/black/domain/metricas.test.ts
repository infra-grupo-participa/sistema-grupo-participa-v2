import { describe, expect, it } from 'vitest';
import {
  agregar, connectRate, cpc, cpm, conversaoPagina, cplDo, cplPlacar, cplPorEtapa, cplRemarketing, ctr, dividir, farolCpl, filtrarDias,
  filtrarLinhas, indexar, ingressoGrupo, pessoasUnicas, somar,
} from './metricas';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, LinhaPerfil } from './tipos';

const campanhas: Campanha[] = [
  { id: 'k1', nome: 'C1', canal: 'meta', funil: 'c1', fase: 'distribuicao' },
  { id: 'k2', nome: 'ISCAS', canal: 'meta', funil: 'iscas', fase: 'captacao' },
  { id: 'k3', nome: 'G', canal: 'google', funil: 'c3', fase: 'captacao' },
  { id: 'k4', nome: 'RMK', canal: 'meta', funil: 'c3', fase: 'remarketing' },
];
const conjuntos: Conjunto[] = [
  { id: 'j1', campanhaId: 'k1', nome: 'J1', isca: null, conjuntoC3: null },
  { id: 'j2', campanhaId: 'k2', nome: 'J2 FLUXO', isca: 'Fluxograma', conjuntoC3: null },
  { id: 'j3', campanhaId: 'k3', nome: 'J3 GOOGLE', isca: null, conjuntoC3: 'aberto' },
  { id: 'j4', campanhaId: 'k4', nome: 'J4 RMK', isca: null, conjuntoC3: null },
];
const ad = (id: string, conjuntoId: string): Anuncio => ({
  id, conjuntoId, nome: id, formato: 'video', paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null,
});
const anuncios = [ad('a1', 'j1'), ad('a2', 'j2'), ad('a3', 'j3'), ad('a4', 'j4')];
const idx = indexar({ campanhas, conjuntos, anuncios });
const dia = (anuncioId: string, gasto: number, impressoes: number, cliques: number | null, lpv: number | null): DesempenhoDia => ({
  anuncioId, dia: '2026-10-12', gasto, impressoes, cliquesLink: cliques, landingPageViews: lpv, alcance: null, frequencia: null,
  videoP50: null, videoP75: null, thruplay: null,
});
const dias = [dia('a1', 100, 10000, null, null), dia('a2', 200, 5000, 100, 70), dia('a3', 50, 1000, 40, null), dia('a4', 30, 900, 10, 8)];
const linha = (p: Partial<LinhaPerfil>): LinhaPerfil => ({
  leadId: 'l', pessoaId: 'p', criadoEm: '2026-10-12T10:00:00-03:00', primeiraPorta: true, porta: null, funil: null, isca: null,
  conjuntoC3: null, campanhaId: null, conjuntoId: null, anuncioId: null, paginaId: null, origem: 'pago', canal: 'meta',
  utmSource: null, utmMedium: null, utmCampaign: null, utmContent: null, utmTerm: null, profissao: null, profissaoBruta: null,
  uf: null, ufOrigem: null, listaOrigem: null, temperaturaBase: null, jaNaBase: null, entrouGrupoEm: null, teste: false, ...p,
});
const leads = [
  linha({ leadId: 'l1', pessoaId: 'p1', funil: 'iscas', isca: 'Fluxograma', campanhaId: 'k2', conjuntoId: 'j2', anuncioId: 'a2' }),
  linha({ leadId: 'l2', pessoaId: 'p2', funil: 'iscas', isca: 'Fluxograma', campanhaId: 'k2', conjuntoId: 'j2', anuncioId: 'a2' }),
  linha({ leadId: 'l3', pessoaId: 'p3', funil: 'c3', campanhaId: 'k3', conjuntoId: 'j3', anuncioId: 'a3', canal: 'google' }),
  linha({ leadId: 'l4', pessoaId: 'p4', funil: 'c3', campanhaId: 'k4', conjuntoId: 'j4', anuncioId: 'a4' }),
  linha({ leadId: 'l5', pessoaId: 'p1', funil: 'c3', origem: 'organico', canal: null }),
];

describe('dividir e somar', () => {
  it('sem dado nunca vira zero', () => {
    expect(dividir(null, 10)).toBeNull();
    expect(dividir(10, 0)).toBeNull();
    expect(dividir(0, 10)).toBe(0);
    expect(somar([null, null]).valor).toBeNull();
    expect(somar([null, 2, 3])).toEqual({ valor: 5, conhecidos: 2, total: 3 });
  });
});

describe('agregados', () => {
  it('CTR usa só as impressões das linhas com clique conhecido', () => {
    const t = ctr(agregar(dias));
    expect(t.num).toBe(150);
    expect(t.den).toBe(6900);
  });
  it('connect rate exclui o C1 e as linhas sem LPV (Google), com nota', () => {
    const t = connectRate(dias, idx);
    expect(t.num).toBe(78);
    expect(t.den).toBe(110);
    expect(t.nota).toMatch(/1 linha/);
  });
  it('connect rate só do C1 é sem dado', () => {
    expect(connectRate([dias[0]], idx).valor).toBeNull();
  });
  it('conversão da página = inscrições pagas dos anúncios com LPV ÷ Σ LPV', () => {
    const t = conversaoPagina(dias, leads, idx);
    expect(t.num).toBe(3);
    expect(t.den).toBe(78);
  });
});

describe('CPL', () => {
  it('soma sobre soma e só leads pagos', () => {
    expect(cplDo(dias, leads)).toEqual({ gasto: 380, leadsPagos: 4, valor: 95 });
    expect(cplDo([], []).valor).toBeNull();
  });
  it('placar = gasto de captação + remarketing ÷ leads pagos', () => {
    expect(cplPlacar(dias, leads, idx)).toEqual({ gasto: 280, leadsPagos: 4, valor: 70 });
  });
  it('por etapa: iscas, por isca, C3 sem o remarketing, conjunto com o nome da fonte', () => {
    const por = Object.fromEntries(cplPorEtapa(dias, leads, idx).map((x) => [x.chave, x]));
    expect(por.iscas.cpl).toEqual({ gasto: 200, leadsPagos: 2, valor: 100 });
    expect(por['isca:Fluxograma'].cpl.valor).toBe(100);
    expect(por.c3.cpl).toEqual({ gasto: 50, leadsPagos: 1, valor: 50 });
    expect(por['conjunto:j3'].rotulo).toBe('J3 GOOGLE');
    expect(por.consultoria.cpl.valor).toBeNull();
    expect(cplRemarketing(dias, leads, idx)).toEqual({ gasto: 30, leadsPagos: 1, valor: 30 });
  });
  it('farol pela régua 15/20', () => {
    const r = { meta: 15, teto: 20 };
    expect(farolCpl(15, r)).toBe('verde');
    expect(farolCpl(20, r)).toBe('amarelo');
    expect(farolCpl(20.01, r)).toBe('vermelho');
    expect(farolCpl(null, r)).toBe('sem');
  });
});

describe('filtros', () => {
  it('funil e canal pela campanha do anúncio', () => {
    expect(filtrarDias(dias, idx, { funil: 'c3', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a3', 'a4']);
    expect(filtrarDias(dias, idx, { funil: 'todos', canal: 'google' }).map((d) => d.anuncioId)).toEqual(['a3']);
    expect(filtrarLinhas(leads, { funil: 'todos', canal: 'meta' })).toHaveLength(3);
  });
});

describe('grupo e pessoas', () => {
  it('pessoas únicas contam uma vez', () => {
    expect(pessoasUnicas(leads)).toBe(4);
  });
  it('ingresso no grupo: só janelas fechadas, pelo primeiro cadastro da pessoa', () => {
    const ls = [
      linha({ pessoaId: 'a', criadoEm: '2026-10-12T10:00:00-03:00', entrouGrupoEm: '2026-10-12T11:00:00-03:00' }),
      linha({ pessoaId: 'b', criadoEm: '2026-10-12T10:00:00-03:00', entrouGrupoEm: '2026-10-12T15:00:00-03:00' }),
      linha({ pessoaId: 'c', criadoEm: '2026-10-12T10:00:00-03:00' }),
      linha({ pessoaId: 'd', criadoEm: '2026-10-12T11:30:00-03:00', entrouGrupoEm: '2026-10-12T11:40:00-03:00' }),
    ];
    const t = ingressoGrupo(ls, 2, new Date('2026-10-12T12:30:00-03:00'));
    expect(t.num).toBe(1);
    expect(t.den).toBe(3);
  });
});

describe('CPM e CPC', () => {
  it('CPM = gasto ÷ impressões × 1000; CPC só nas linhas com clique conhecido', () => {
    const a = agregar(dias);
    expect(cpm(a)).toBeCloseTo((380 * 1000) / 16900, 6);
    // a1 (sem clique) fica fora do CPC: (200 + 50 + 30) ÷ (100 + 40 + 10)
    expect(cpc(a)).toBeCloseTo(280 / 150, 6);
    expect(cpc(agregar([dia('a1', 100, 10000, null, null)]))).toBeNull();
  });
});
