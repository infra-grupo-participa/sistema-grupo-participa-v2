import { describe, expect, it } from 'vitest';
import { cplDoRecorte, investimentoDeCaptacao, investimentoDoRecorte, leadsDoTrafego } from './numeros';
import { cplPlacar, cplPorEtapa, filtrarDias, filtrarLinhas, indexar, linhasCaptacao } from './metricas';
import { campanhaNoFunil, linhaNoFunil } from './linha-black';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, LinhaPerfil, TrafegoBlack } from './tipos';

// Auditoria pós-deploy (16/10/2026): o CPL de cada linha do modal dividia o gasto de captação do período INTEIRO pelos leads
// só do recorte (Iscas mostrava 1.893,90 ÷ 29 = 65,31 em vez de 409,87 ÷ 29 = 14,13). Valores abaixo seguem o caso real de
// 04/10 a 15/10 (iscas 409,87 com 29 pessoas; C3 1.397,54 com 42), com consultoria e remarketing para fechar a soma das partes.
const ETQ = 'black-friday-2026-10';
const periodo = { de: '2026-10-04', ate: '2026-10-15' };
const campanhas: Campanha[] = [
  { id: 'k-c1', nome: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`, canal: 'meta', funil: 'c1', fase: 'antecipacao', linha: 'c1' },
  { id: 'k-c2', nome: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'iscas', fase: 'captacao', linha: 'c2' },
  { id: 'k-c3', nome: `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'google', funil: 'c3', fase: 'captacao', linha: 'c3' },
  { id: 'k-rmk', nome: `CF | BF26 | CAPTAÇÃO | REMARKETING | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: null, fase: 'captacao', linha: 'remarketing_pagina' },
  { id: 'k-live', nome: `CF | BF26 | REMARKETING | LIVE | FB | PQ | ABO | ${ETQ}`, canal: 'meta', funil: null, fase: 'remarketing', linha: 'remarketing_live' },
];
const conjuntos: Conjunto[] = [
  { id: 'j-c1', campanhaId: 'k-c1', nome: 'C1 | TEASER', isca: null, conjuntoC3: null, linha: 'c1', no: 'teaser' },
  { id: 'j-iscas', campanhaId: 'k-c2', nome: 'VV C1 | FLUXOGRAMA', isca: 'Fluxograma', iscaBanco: 'FLUXOGRAMA', conjuntoC3: null, linha: 'iscas', no: 'iscas' },
  { id: 'j-cons', campanhaId: 'k-c2', nome: 'VV C1 | CONSULTORIA', isca: null, iscaBanco: 'CONSULTORIA', conjuntoC3: null, linha: 'consultoria', no: 'consultoria' },
  { id: 'j-c3', campanhaId: 'k-c3', nome: 'C3 | MIX PQ | CONVITE--DIRETO_01', isca: null, conjuntoC3: 'aberto', linha: 'c3', no: 'c3' },
  { id: 'j-rmk', campanhaId: 'k-rmk', nome: 'RMK | VISITOU SEM LEAD 7D', isca: null, conjuntoC3: null, linha: 'remarketing_pagina', no: 'remarketing_pagina' },
  { id: 'j-live', campanhaId: 'k-live', nome: 'LIVE 03/11', isca: null, conjuntoC3: null, linha: 'remarketing_live', no: 'remarketing_live' },
];
const ad = (id: string, conjuntoId: string): Anuncio => ({
  id, conjuntoId, nome: id, formato: 'video', paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null,
});
const anuncios = [ad('a-c1', 'j-c1'), ad('a-iscas', 'j-iscas'), ad('a-cons', 'j-cons'), ad('a-c3', 'j-c3'), ad('a-rmk', 'j-rmk'), ad('a-live', 'j-live')];
const dia = (anuncioId: string, dia: string, gasto: number): DesempenhoDia => ({
  anuncioId, dia, gasto, impressoes: 1000, cliquesLink: 10, landingPageViews: 5, alcance: null, frequencia: null,
  videoP50: null, videoP75: null, thruplay: null,
});
// Dois dias por anúncio: o gasto do dia 14 e o do dia 15 somam o gasto do período.
const dias: DesempenhoDia[] = [
  dia('a-c1', '2026-10-14', 3000), dia('a-c1', '2026-10-15', 2000),
  dia('a-iscas', '2026-10-14', 209.87), dia('a-iscas', '2026-10-15', 200),
  dia('a-cons', '2026-10-14', 60), dia('a-cons', '2026-10-15', 40),
  dia('a-c3', '2026-10-14', 1000), dia('a-c3', '2026-10-15', 397.54),
  dia('a-rmk', '2026-10-14', 50), dia('a-rmk', '2026-10-15', 36.49),
  dia('a-live', '2026-10-14', 700), dia('a-live', '2026-10-15', 300),
];
const trafego: TrafegoBlack = {
  campanhas, conjuntos, anuncios, paginas: [], dias, totais: [], coletadoEm: null,
  gastoCampanhas: [
    { campanhaId: 'k-c1', gasto: 5000 }, { campanhaId: 'k-c2', gasto: 509.87 }, { campanhaId: 'k-c3', gasto: 1397.54 },
    { campanhaId: 'k-rmk', gasto: 86.49 }, { campanhaId: 'k-live', gasto: 1000 },
  ],
};
const idx = indexar(trafego);

const lead = (n: number, p: Partial<LinhaPerfil>): LinhaPerfil => ({
  leadId: `l-${n}`, pessoaId: `p-${n}`, criadoEm: '2026-10-14T10:00:00-03:00', primeiraPorta: true, porta: null, funil: null, isca: null,
  conjuntoC3: null, campanhaId: null, conjuntoId: null, anuncioId: null, paginaId: null, origem: 'pago', canal: 'meta',
  utmSource: null, utmMedium: null, utmCampaign: null, utmContent: null, utmTerm: null, profissao: null, profissaoBruta: null,
  uf: null, ufOrigem: null, listaOrigem: null, temperaturaBase: null, jaNaBase: null, entrouGrupoEm: null, teste: false, ...p,
});
const gerar = (de: number, quantos: number, p: Partial<LinhaPerfil>): LinhaPerfil[] =>
  Array.from({ length: quantos }, (_, i) => lead(de + i, p));
const iscasLeads = gerar(0, 29, { funil: 'iscas', isca: 'Fluxograma', campanhaId: 'k-c2', conjuntoId: 'j-iscas', anuncioId: 'a-iscas' });
const consLeads = gerar(100, 5, { funil: 'consultoria', campanhaId: 'k-c2', conjuntoId: 'j-cons', anuncioId: 'a-cons' });
const c3Leads = gerar(200, 42, { funil: 'c3', campanhaId: 'k-c3', conjuntoId: 'j-c3', anuncioId: 'a-c3', canal: 'google' });
const rmkLeads = gerar(300, 10, { funil: 'c3', campanhaId: 'k-rmk', conjuntoId: 'j-rmk', anuncioId: 'a-rmk' });
const linhas = [...iscasLeads, ...consLeads, ...c3Leads, ...rmkLeads];

const cpl = (rec?: Parameters<typeof cplDoRecorte>[5], d = dias, l = linhas) => cplDoRecorte(trafego, periodo, d, l, idx, rec).valor;
// O que o ModalCard monta para cada linha: dias e cadastros do recorte + o próprio recorte.
const linhaFunil = (funil: Parameters<typeof filtrarDias>[2]['funil'], canal: 'todos' | 'meta' | 'google' = 'todos') =>
  cpl({ funil, canal }, filtrarDias(dias, idx, { funil, canal }), filtrarLinhas(linhas, { funil, canal }, idx));

describe('CPL de cada linha do modal: gasto e leads do mesmo recorte', () => {
  it('Iscas = gasto das iscas ÷ pessoas das iscas, não o total de captação ÷ pessoas das iscas', () => {
    expect(linhaFunil('iscas')).toBeCloseTo(409.87 / 29, 6);
    expect(linhaFunil('iscas')).toBeCloseTo(14.13, 2);
    // O bug: 1.993,90 (captação inteira) ÷ 29.
    expect(linhaFunil('iscas')).not.toBeCloseTo(1993.9 / 29, 2);
  });
  it('Consultoria separa do mesmo conjunto: 100 ÷ 5', () => {
    expect(linhaFunil('consultoria')).toBeCloseTo(100 / 5, 6);
  });
  it('C3 = 1.397,54 ÷ 42', () => {
    expect(linhaFunil('c3')).toBeCloseTo(1397.54 / 42, 6);
    expect(linhaFunil('c3')).toBeCloseTo(33.27, 2);
  });
  it('C2 = consultoria + iscas: a campanha mista inteira, com as 34 pessoas', () => {
    expect(linhaFunil('c2')).toBeCloseTo(509.87 / 34, 6);
  });
  it('C1 não é captação: sem dado, nunca zero', () => {
    expect(linhaFunil('c1')).toBeNull();
  });
  it('Todos (o card principal): captação inteira ÷ pessoas pagas de captação, igual ao cálculo da tela', () => {
    const recorte = { funil: 'todos', canal: 'todos' } as const;
    const daTela = investimentoDeCaptacao(trafego, periodo, recorte).total! / leadsDoTrafego(linhas, idx, recorte).valor!;
    expect(daTela).toBeCloseTo(1993.9 / 86, 6);
    expect(cpl(recorte, filtrarDias(dias, idx, recorte), filtrarLinhas(linhas, recorte, idx))).toBe(daTela);
  });
  it('aba Canal: cada canal com o gasto das próprias campanhas (Meta sem a campanha do Google)', () => {
    // Meta: iscas + consultoria (509,87) + remarketing (86,49) ÷ 29 + 5 + 10 pessoas.
    expect(linhaFunil('todos', 'meta')).toBeCloseTo((509.87 + 86.49) / 44, 6);
    expect(linhaFunil('todos', 'google')).toBeCloseTo(1397.54 / 42, 6);
    expect(linhaFunil('iscas', 'google')).toBeNull();
  });
  it('aba Fase: só as campanhas da fase entram no gasto (fase captação) e a de remarketing da live não é captação', () => {
    const fase = (chave: string) => (c: Campanha) => c.fase === chave;
    const lf = (chave: string) => linhas.filter((l) => l.campanhaId && fase(chave)(idx.campanha.get(l.campanhaId)!));
    expect(cpl({ funil: 'todos', canal: 'todos', campanha: fase('captacao') }, dias, lf('captacao'))).toBeCloseTo(1993.9 / 86, 6);
    expect(cpl({ funil: 'todos', canal: 'todos', campanha: fase('remarketing') }, dias, lf('remarketing'))).toBeNull();
    expect(cpl({ funil: 'todos', canal: 'todos', campanha: fase('antecipacao') }, dias, [])).toBeNull();
  });
  it('linha Remarketing da página: 86,49 ÷ 10', () => {
    const rec = { funil: 'todos', canal: 'todos', campanha: (c: Campanha) => c.linha === 'remarketing_pagina' } as const;
    expect(cpl(rec, dias.filter((x) => idx.linhaDoAnuncio(x.anuncioId) === 'remarketing_pagina'), rmkLeads)).toBeCloseTo(86.49 / 10, 6);
  });
  it('aba Dia e Criativo (sem recorte de campanha): gasto dos anúncios de captação dos próprios dias recebidos', () => {
    const doDia = (d: string) => dias.filter((x) => x.dia === d);
    // Dia 15: iscas 200 + consultoria 40 + C3 397,54 + remarketing 36,49, com as pessoas do dia 15.
    const l15 = linhas.slice(0, 20).map((l) => ({ ...l, criadoEm: '2026-10-15T10:00:00-03:00' }));
    const esperado = (200 + 40 + 397.54 + 36.49) / leadsDoTrafego(l15, idx).valor!;
    expect(cpl(undefined, doDia('2026-10-15'), l15)).toBeCloseTo(esperado, 6);
    // Um criativo só (anúncio das iscas): 409,87 ÷ 29, e não o total do período.
    expect(cpl(undefined, dias.filter((x) => x.anuncioId === 'a-iscas'), iscasLeads)).toBeCloseTo(409.87 / 29, 6);
    // Criativo de distribuição (C1): sem dia de captação = sem dado.
    expect(cpl(undefined, dias.filter((x) => x.anuncioId === 'a-c1'), [])).toBeNull();
  });
  it('recorte sem campanha de captação não vira zero', () => {
    expect(cplDoRecorte(trafego, periodo, [], [], idx, { funil: 'todos', canal: 'todos', campanha: () => false }).valor).toBeNull();
  });
  it('soma sobre soma: o CPL das partes não é a média dos CPLs; os gastos das partes fecham com o total', () => {
    const gasto = (funil: 'iscas' | 'consultoria' | 'c3') => investimentoDoRecorte(trafego, periodo, { funil, canal: 'todos' }).total!;
    const rmk = investimentoDoRecorte(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.linha === 'remarketing_pagina' }).total!;
    const todos = investimentoDeCaptacao(trafego, periodo, { funil: 'todos', canal: 'todos' }).total!;
    expect(gasto('iscas') + gasto('consultoria') + gasto('c3') + rmk).toBeCloseTo(todos, 6);
  });
});

describe('remarketing da página no filtro de funil (decisão do Victor, 16/10)', () => {
  const rmkCampanha = campanhas[3];
  it('não tem funil próprio: aparece em Todos e fica fora de C1, C2, Consultoria, Iscas e C3', () => {
    expect(campanhaNoFunil('todos', rmkCampanha)).toBe('sim');
    for (const f of ['c1', 'c2', 'consultoria', 'iscas', 'c3'] as const) expect(campanhaNoFunil(f, rmkCampanha)).toBe('nao');
    expect(linhaNoFunil('todos', 'remarketing_pagina')).toBe(true);
    expect(linhaNoFunil('c3', 'remarketing_pagina')).toBe(false);
  });
  it('em Todos, o investimento e o CPL de captação já o incluem; pré-captação continua fora', () => {
    const inv = investimentoDeCaptacao(trafego, periodo, { funil: 'todos', canal: 'todos' });
    expect(inv.campanhasRemarketing).toEqual([rmkCampanha.nome]);
    expect(inv.total).toBeCloseTo(1993.9, 6);
    expect(cplPlacar(dias, linhas, idx, trafego.gastoCampanhas)).toMatchObject({ gasto: expect.closeTo(1993.9, 6), leadsPagos: 86 });
    expect(linhasCaptacao(linhas, idx).some((l) => l.campanhaId === 'k-rmk')).toBe(true);
    expect(linhasCaptacao(linhas, idx, { funil: 'c3', canal: 'todos' }).some((l) => l.campanhaId === 'k-rmk')).toBe(false);
  });
  it('soma das partes = total: Todos = C2 + C3 + remarketing da página (C1 e o resto não são captação)', () => {
    const parte = (funil: 'c2' | 'c3') => investimentoDeCaptacao(trafego, periodo, { funil, canal: 'todos' }).total!;
    const rmk = investimentoDoRecorte(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.linha === 'remarketing_pagina' }).total!;
    expect(parte('c2') + parte('c3') + rmk).toBeCloseTo(investimentoDeCaptacao(trafego, periodo, { funil: 'todos', canal: 'todos' }).total!, 6);
  });
});

describe('CPL por etapa com canal escolhido', () => {
  it('o gasto da etapa segue o canal dos leads (Meta não leva a campanha do Google)', () => {
    const diasMeta = filtrarDias(dias, idx, { funil: 'todos', canal: 'meta' });
    const linhasMeta = filtrarLinhas(linhas, { funil: 'todos', canal: 'meta' }, idx);
    const por = Object.fromEntries(cplPorEtapa(diasMeta, linhasMeta, idx, trafego.gastoCampanhas, 'meta').map((x) => [x.chave, x]));
    expect(por.c3.cpl.gasto).toBeNull();
    expect(por.iscas.cpl.valor).toBeCloseTo(409.87 / 29, 6);
    expect(por.remarketing_pagina.cpl.valor).toBeCloseTo(86.49 / 10, 6);
    const todos = Object.fromEntries(cplPorEtapa(dias, linhas, idx, trafego.gastoCampanhas).map((x) => [x.chave, x]));
    expect(todos.c3.cpl.valor).toBeCloseTo(1397.54 / 42, 6);
    // Antes da correção, com canal Meta o gasto do C3 (Google) continuava na etapa.
    const googleSo = Object.fromEntries(cplPorEtapa(filtrarDias(dias, idx, { funil: 'todos', canal: 'google' }),
      filtrarLinhas(linhas, { funil: 'todos', canal: 'google' }, idx), idx, trafego.gastoCampanhas, 'google').map((x) => [x.chave, x]));
    expect(googleSo.iscas.cpl.gasto).toBeNull();
    expect(googleSo.c3.cpl.valor).toBeCloseTo(1397.54 / 42, 6);
  });
});
