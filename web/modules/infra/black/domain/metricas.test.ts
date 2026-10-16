import { describe, expect, it } from 'vitest';
import {
  agregar, connectRate, cpc, cpm, conversaoPagina, cplDo, cplPlacar, cplPorEtapa, ctr, dividir, farolCpl, filtrarDias,
  filtrarLinhas, indexar, ingressoGrupo, linhasCaptacao, mqlDoRecorte, pessoasUnicas, somar,
} from './metricas';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, LinhaPerfil } from './tipos';

// Nomes REAIS do guia do Caio (15/10/2026). `linha`, `no` e `iscaBanco` são o que a RPC dados_black_trafego devolve.
// A campanha de remarketing da página sobe em 16/10: o nome do k4 segue o padrão do guia (CAPTAÇÃO | REMARKETING). O canal do k3 é google só para o teste ter as duas plataformas.
const ETQ = 'black-friday-2026-10';
const campanhas: Campanha[] = [
  { id: 'k1', nome: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`, canal: 'meta', funil: 'c1', fase: 'antecipacao', linha: 'c1' },
  { id: 'k2', nome: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'iscas', fase: 'captacao', linha: 'c2' },
  { id: 'k3', nome: `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'google', funil: 'c3', fase: 'captacao', linha: 'c3' },
  { id: 'k4', nome: `CF | BF26 | CAPTAÇÃO | REMARKETING | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: null, fase: 'captacao', linha: 'remarketing_pagina' },
];
const conjuntos: Conjunto[] = [
  { id: 'j1', campanhaId: 'k1', nome: 'C1 | TEASER | LEADS HT', isca: null, conjuntoC3: null, linha: 'c1', no: 'teaser' },
  { id: 'j2', campanhaId: 'k2', nome: 'VV C1 | FLUXOGRAMA', isca: 'Fluxograma', iscaBanco: 'FLUXOGRAMA', conjuntoC3: null, linha: 'iscas', no: 'iscas' },
  { id: 'j3', campanhaId: 'k3', nome: 'C3 | MIX PQ | CONVITE--DIRETO_01', isca: null, conjuntoC3: 'aberto', linha: 'c3', no: 'c3' },
  { id: 'j4', campanhaId: 'k4', nome: 'RMK | VISITOU SEM LEAD 7D', isca: null, conjuntoC3: null, linha: 'remarketing_pagina', no: 'remarketing_pagina' },
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
  it('conversão da página = pessoas pagas únicas dos anúncios com LPV ÷ Σ LPV', () => {
    const t = conversaoPagina(dias, leads, idx);
    expect(t.num).toBe(3);
    expect(conversaoPagina(dias, [...leads, linha({ leadId: 'l-extra', pessoaId: 'p2', campanhaId: 'k2', anuncioId: 'a2' })], idx).num).toBe(3);
    expect(t.den).toBe(78);
  });
});

describe('CPL', () => {
  it('soma sobre soma e só leads pagos', () => {
    expect(cplDo(dias, leads)).toEqual({ gasto: 380, leadsPagos: 4, valor: 95 });
    expect(cplDo([], []).valor).toBeNull();
    expect(cplDo([], [...leads, linha({ leadId: 'l7', pessoaId: 'p2', origem: 'pago' })]).leadsPagos).toBe(4);
  });
  it('CPL geral: iscas, C3 e remarketing da página (decisão do Victor, 16/10); o C1 fica fora', () => {
    // Gasto 200 (iscas) + 50 (C3) + 30 (remarketing) = 280; pessoas pagas p1, p2, p3 e p4 = 4.
    expect(cplPlacar(dias, leads, idx)).toEqual({ gasto: 280, leadsPagos: 4, valor: 70 });
  });
  it('CPL conta pessoas pagas únicas e exclui a porta consultoria_respondi', () => {
    const duplicada = linha({ leadId: 'l-extra', pessoaId: 'p2', campanhaId: 'k2', origem: 'pago', funil: 'iscas' });
    const respondi = linha({ leadId: 'l-respondi', pessoaId: 'p-novo', campanhaId: 'k2', origem: 'pago', pagina: 'consultoria_respondi' });
    expect(cplPlacar(dias, [...leads, duplicada, respondi], idx)).toEqual({ gasto: 280, leadsPagos: 4, valor: 70 });
  });
  it('consultoria e iscas dentro da campanha CAPTAÇÃO | ISCAS: o conjunto separa, o gasto sai dos anúncios do conjunto', () => {
    const cons: Conjunto = { id: 'j5', campanhaId: 'k2', nome: 'VV C1 | CONSULTORIA', isca: null, iscaBanco: 'CONSULTORIA', conjuntoC3: null, linha: 'consultoria', no: 'consultoria' };
    const ix = indexar({ campanhas, conjuntos: [...conjuntos, cons], anuncios: [...anuncios, ad('a5', 'j5')] });
    const diasC = [...dias, dia('a5', 40, 400, 20, 10)];
    const l = linha({ leadId: 'l6', pessoaId: 'p6', campanhaId: 'k2', conjuntoId: 'j5', anuncioId: 'a5', funil: 'consultoria' });
    const gastoCampanhas = [{ campanhaId: 'k2', gasto: 240 }];
    const por = Object.fromEntries(cplPorEtapa(diasC, [...leads, l], ix, gastoCampanhas).map((x) => [x.chave, x]));
    expect(por.consultoria.cpl).toEqual({ gasto: 40, leadsPagos: 1, valor: 40 });
    expect(por.iscas.cpl).toEqual({ gasto: 200, leadsPagos: 2, valor: 100 });
    // O CPL de captação (todas as linhas) usa o gasto inteiro da campanha mista: 240 + 50 (C3) + 30 (remarketing) = 320, com 5 pessoas.
    expect(cplPlacar(diasC, [...leads, l], ix, [...gastoCampanhas, { campanhaId: 'k3', gasto: 50 }, { campanhaId: 'k4', gasto: 30 }]))
      .toEqual({ gasto: 320, leadsPagos: 5, valor: 64 });
  });
  it('pré-captação (ENTRESAFRA do guia) fica fora do CPL e de todas as métricas de tráfego', () => {
    const entresafra: Campanha = { id: 'k5', nome: `CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'c3', fase: null, etapa: 'C3', linha: 'pre_captacao' };
    const conjuntoEntresafra: Conjunto = { id: 'j5', campanhaId: 'k5', nome: 'Entresafra', isca: null, conjuntoC3: null, linha: 'pre_captacao', no: 'pre_captacao' };
    const ix = indexar({ campanhas: [...campanhas, entresafra], conjuntos: [...conjuntos, conjuntoEntresafra], anuncios: [...anuncios, ad('a5', 'j5')] });
    const gastoCampanhas = [{ campanhaId: 'k3', gasto: 50 }, { campanhaId: 'k4', gasto: 30 }, { campanhaId: 'k5', gasto: 600 }];
    const linhas = [...leads, linha({ leadId: 'l6', pessoaId: 'p6', campanhaId: 'k5', conjuntoId: 'j5', anuncioId: 'a5', origem: 'pago' })];
    const diaEntresafra = dia('a5', 600, 4000, 75, 50);
    expect(cplPlacar([...dias, diaEntresafra], linhas, ix, gastoCampanhas)).toMatchObject({ gasto: 80, leadsPagos: 4, valor: 20 });
    for (const f of ['todos', 'c1', 'c2', 'c3'] as const) {
      expect(filtrarDias([...dias, diaEntresafra], ix, { funil: f, canal: 'todos' })).not.toContain(diaEntresafra);
      // 'todos' sem canal devolve todos os cadastros do período (é o total de pessoas); a captação é que exclui a pré-captação.
      if (f !== 'todos') expect(filtrarLinhas(linhas, { funil: f, canal: 'todos' }, ix).map((x) => x.leadId)).not.toContain('l6');
    }
    expect(linhasCaptacao(linhas, ix).map((x) => x.leadId)).not.toContain('l6');
  });
  it('por etapa: Iscas, Remarketing da página e C3 separados, conjunto mantém o nome exato da fonte', () => {
    const por = Object.fromEntries(cplPorEtapa(dias, leads, idx).map((x) => [x.chave, x]));
    expect(por.iscas.rotulo).toBe('Iscas');
    expect(por.iscas.cpl).toEqual({ gasto: 200, leadsPagos: 2, valor: 100 });
    expect(por['isca:Fluxograma'].cpl).toEqual({ gasto: 200, leadsPagos: 2, valor: 100 });
    expect(por.c3.cpl).toEqual({ gasto: 50, leadsPagos: 1, valor: 50 });
    expect(por['conjunto:j3'].rotulo).toBe('C3 | MIX PQ | CONVITE--DIRETO_01');
    expect(por.consultoria.cpl.valor).toBeNull();
    expect(por.remarketing_pagina.rotulo).toBe('Remarketing da página');
    expect(por.remarketing_pagina.cpl).toEqual({ gasto: 30, leadsPagos: 1, valor: 30 });
  });
  it('Iscas: a isca vem do banco (VV C1 | CHECKUP), sem dupla contagem com o C3', () => {
    const conjCheckup: Conjunto = { id: 'j5', campanhaId: 'k2', nome: 'VV C1 | CHECKUP', isca: 'Checkup', iscaBanco: 'CHECKUP', conjuntoC3: null, linha: 'iscas', no: 'iscas' };
    const ix = indexar({ campanhas, conjuntos: [...conjuntos, conjCheckup], anuncios: [...anuncios, ad('a5', 'j5')] });
    const leadCheckup = linha({ leadId: 'l6', pessoaId: 'p6', funil: 'iscas', campanhaId: 'k2', conjuntoId: 'j5', anuncioId: 'a5', isca: 'Checkup' });
    const por = Object.fromEntries(cplPorEtapa([dia('a2', 200, 5000, 100, 70), dia('a5', 20, 100, 10, 5)], [...leads.slice(0, 2), leadCheckup], ix).map((x) => [x.chave, x]));
    expect(por.iscas.cpl).toEqual({ gasto: 220, leadsPagos: 3, valor: 220 / 3 });
    expect(por['isca:Checkup'].cpl).toEqual({ gasto: 20, leadsPagos: 1, valor: 20 });
    expect(por['isca:Fluxograma'].cpl).toEqual({ gasto: 200, leadsPagos: 2, valor: 100 });
    expect(por.c3.cpl.valor).toBeNull();
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
  it('funil e canal pela linha do conjunto do anúncio (o remarketing da página não é C3)', () => {
    expect(filtrarDias(dias, idx, { funil: 'c3', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a3']);
    expect(filtrarDias(dias, idx, { funil: 'todos', canal: 'google' }).map((d) => d.anuncioId)).toEqual(['a3']);
    expect(filtrarLinhas(leads, { funil: 'todos', canal: 'meta' }, idx)).toHaveLength(3);
  });
  it('C2 = consultoria + iscas, pelo conjunto, sem incluir C1, C3 nem remarketing', () => {
    const cons: Conjunto = { id: 'j5', campanhaId: 'k2', nome: 'VV C1 | CONSULTORIA', isca: null, iscaBanco: 'CONSULTORIA', conjuntoC3: null, linha: 'consultoria', no: 'consultoria' };
    const idxC2 = indexar({ campanhas, conjuntos: [...conjuntos, cons], anuncios: [...anuncios, ad('a5', 'j5')] });
    const dadosC2 = [...dias, dia('a5', 40, 400, 20, 10)];
    const linhasC2 = [...leads, linha({ leadId: 'l6', funil: 'consultoria', campanhaId: 'k2', conjuntoId: 'j5', anuncioId: 'a5' })];
    expect(filtrarDias(dadosC2, idxC2, { funil: 'c2', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a2', 'a5']);
    expect(filtrarLinhas(linhasC2, { funil: 'c2', canal: 'todos' }, idxC2).map((l) => l.leadId)).toEqual(['l1', 'l2', 'l6']);
    // A consultoria e as iscas são separáveis dentro da mesma campanha.
    expect(filtrarDias(dadosC2, idxC2, { funil: 'consultoria', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a5']);
    expect(filtrarDias(dadosC2, idxC2, { funil: 'iscas', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a2']);
  });
  it('sem `linha` no banco (RPC antiga), o funil da campanha continua valendo', () => {
    const antigas: Campanha[] = [{ id: 'k1', nome: 'CF | BF26 | C3 | ENTRESAFRA', canal: 'meta', funil: 'c3', fase: 'captacao', etapa: 'C3' }, { id: 'k2', nome: 'ISCAS', canal: 'meta', funil: 'iscas', fase: 'captacao' }];
    const cjs: Conjunto[] = [{ id: 'j1', campanhaId: 'k1', nome: 'J1', isca: null, conjuntoC3: null }, { id: 'j2', campanhaId: 'k2', nome: 'J2', isca: null, conjuntoC3: null }];
    const ix = indexar({ campanhas: antigas, conjuntos: cjs, anuncios: [ad('a1', 'j1'), ad('a2', 'j2')] });
    expect(filtrarDias([dia('a1', 10, 100, 1, 1), dia('a2', 20, 100, 1, 1)], ix, { funil: 'todos', canal: 'todos' }).map((d) => d.anuncioId)).toEqual(['a2']);
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
  it('MQL usa a profissão do envio mais recente, não o booleano mql de envios antigos', () => {
    const ls = [
      linha({ pessoaId: 'a', criadoEm: '2026-10-12T10:00:00-03:00', profissao: 'advogado', mql: true }),
      linha({ pessoaId: 'a', criadoEm: '2026-10-12T11:00:00-03:00', profissao: 'outros', mql: true }),
      linha({ pessoaId: 'b', criadoEm: '2026-10-12T10:30:00-03:00', profissao: 'contador', mql: false }),
      linha({ pessoaId: 'c', criadoEm: '2026-10-12T09:00:00-03:00', profissao: null, mql: true }),
    ];
    expect(mqlDoRecorte(ls)).toMatchObject({ num: 1, den: 3, valor: 1 / 3, nota: 'Regra B: profissão do envio mais recente ÷ pessoas únicas do recorte.' });
  });
  it('ignora envios sem profissão ao escolher o envio mais recente, como o servidor', () => {
    const ls = [
      linha({ pessoaId: 'a', criadoEm: '2026-10-12T10:00:00-03:00', profissao: 'advogado' }),
      linha({ pessoaId: 'a', criadoEm: '2026-10-12T11:00:00-03:00', profissao: null }),
      linha({ pessoaId: 'b', criadoEm: '2026-10-12T10:30:00-03:00', profissao: 'outros' }),
    ];
    expect(mqlDoRecorte(ls)).toMatchObject({ num: 1, den: 2, valor: 0.5 });
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
