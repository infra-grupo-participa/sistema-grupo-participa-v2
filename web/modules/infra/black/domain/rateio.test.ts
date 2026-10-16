import { describe, expect, it } from 'vitest';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { RELOGIO_PADRAO } from '../infrastructure/fixtures/gerador';
import { calcularJornada } from './jornada';
import { cplPorEtapa, filtrarDias, indexar } from './metricas';
import { cplDoRecorte, investimentoDeCaptacao, investimentoDoRecorte, investimentoDoRecorteValor, investimentoTrafego } from './numeros';
import { gastoDaParte, ratear, semDetalheDoFunil, semDetalheMista, somaSemDetalhe } from './rateio';
import { FUNIS } from './tipos';
import { linhaNoFunil } from './linha-black';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, TrafegoBlack } from './tipos';

// Auditoria pós-deploy (16/10/2026), reauditoria: a CAMPANHA é o dinheiro (igual ao gerenciador) e o anúncio só DIVIDE.
// Caso real da C2 (campanha mista Consultoria + Iscas): 517,79 por campanha e 520,21 por anúncio (87,10 + 433,11), porque
// as duas tabelas são gravadas com cerca de 20 s de diferença no dia em curso. A C3 fecha igual nas duas fontes (1.404,71).
const ETQ = 'black-friday-2026-10';
const periodo = { de: '2026-10-13', ate: '2026-10-15' };
const campanhas: Campanha[] = [
  { id: 'k-c2', nome: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'iscas', fase: 'captacao', linha: 'c2' },
  { id: 'k-c3', nome: `CF | BF26 | CAPTAÇÃO | BASE | GOOGLE | PQ | LEAD | ${ETQ}`, canal: 'google', funil: 'c3', fase: 'captacao', linha: 'c3' },
  { id: 'k-c1', nome: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`, canal: 'meta', funil: 'c1', fase: 'antecipacao', linha: 'c1' },
];
const conjuntos: Conjunto[] = [
  { id: 'j-iscas', campanhaId: 'k-c2', nome: 'VV C1 | FLUXOGRAMA', isca: 'Fluxograma', iscaBanco: 'FLUXOGRAMA', conjuntoC3: null, linha: 'iscas', no: 'iscas' },
  { id: 'j-cons', campanhaId: 'k-c2', nome: 'VV C1 | CONSULTORIA', isca: null, iscaBanco: 'CONSULTORIA', conjuntoC3: null, linha: 'consultoria', no: 'consultoria' },
  { id: 'j-c3', campanhaId: 'k-c3', nome: 'C3 | MIX PQ | CONVITE--DIRETO_01', isca: null, conjuntoC3: 'aberto', linha: 'c3', no: 'c3' },
  { id: 'j-c1', campanhaId: 'k-c1', nome: 'C1 | TEASER', isca: null, conjuntoC3: null, linha: 'c1', no: 'teaser' },
];
const ad = (id: string, conjuntoId: string): Anuncio => ({
  id, conjuntoId, nome: id, formato: 'video', paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null,
});
const anuncios = [ad('a-iscas', 'j-iscas'), ad('a-cons', 'j-cons'), ad('a-c3', 'j-c3'), ad('a-c1', 'j-c1')];
const dia = (anuncioId: string, d: string, gasto: number): DesempenhoDia => ({
  anuncioId, dia: d, gasto, impressoes: 1000, cliquesLink: 10, landingPageViews: 5, alcance: null, frequencia: null,
  videoP50: null, videoP75: null, thruplay: null,
});
const noCentavo = (reais: number | null | undefined) => Math.round((reais ?? NaN) * 100);

const dias: DesempenhoDia[] = [
  dia('a-cons', '2026-10-15', 87.1), dia('a-iscas', '2026-10-15', 433.11), dia('a-c3', '2026-10-15', 1404.71), dia('a-c1', '2026-10-15', 300),
];
const trafego: TrafegoBlack = {
  campanhas, conjuntos, anuncios, paginas: [], dias, totais: [], coletadoEm: null,
  gastoCampanhas: [{ campanhaId: 'k-c2', gasto: 517.79 }, { campanhaId: 'k-c3', gasto: 1404.71 }, { campanhaId: 'k-c1', gasto: 300 }],
};
const idx = indexar(trafego);
const consultoria = (l: Parameters<typeof linhaNoFunil>[1]) => linhaNoFunil('consultoria', l);
const iscas = (l: Parameters<typeof linhaNoFunil>[1]) => linhaNoFunil('iscas', l);

describe('rateio: campanha é o dinheiro, anúncio só divide', () => {
  it('Consultoria + Iscas fecha em 517,79 exato (não 520,21)', () => {
    const r = ratear(dias, trafego, idx);
    const cons = gastoDaParte(r, idx, 'k-c2', consultoria);
    const isc = gastoDaParte(r, idx, 'k-c2', iscas);
    expect(noCentavo(cons) + noCentavo(isc)).toBe(51779);
    // proporção do anúncio: 87,10 / 520,21 = 16,74% (86,69) e 433,11 / 520,21 = 83,26% (431,10).
    expect(Math.abs(noCentavo(cons) - 8669)).toBeLessThanOrEqual(1);
    expect(Math.abs(noCentavo(isc) - 43110)).toBeLessThanOrEqual(1);
    expect(r.semDetalhe.size).toBe(0);
  });

  it('CPL por etapa: partes da C2 somam a campanha e o total de captação fecha com o card (1.922,50)', () => {
    const etapas = cplPorEtapa(dias, [], idx, trafego.gastoCampanhas, 'todos', trafego.gastoCampanhasDiario);
    const g = (chave: string) => etapas.find((e) => e.chave === chave)!.cpl.gasto;
    expect(noCentavo(g('consultoria')) + noCentavo(g('iscas'))).toBe(51779);
    expect(noCentavo(g('c3'))).toBe(140471);
    expect(etapas.some((e) => e.nivel === 'sem_detalhe')).toBe(false);
    const card = investimentoDeCaptacao(trafego, periodo, { funil: 'todos', canal: 'todos' }).total;
    expect(noCentavo(card)).toBe(192250);
    expect(noCentavo(g('consultoria')) + noCentavo(g('iscas')) + noCentavo(g('c3'))).toBe(noCentavo(card));
  });

  it('modal por funil: investimentoTrafego e investimentoDoRecorte de Consultoria e Iscas fecham com a campanha', () => {
    const t = (funil: 'consultoria' | 'iscas') => investimentoTrafego(trafego, { funil, canal: 'todos' }).valor;
    expect(noCentavo(t('consultoria')) + noCentavo(t('iscas'))).toBe(51779);
    const r = (funil: 'consultoria' | 'iscas') => investimentoDoRecorte(trafego, periodo, { funil, canal: 'todos' }).total;
    expect(noCentavo(r('consultoria')) + noCentavo(r('iscas'))).toBe(51779);
    const c2 = investimentoDoRecorte(trafego, periodo, { funil: 'c2', canal: 'todos' }).total;
    expect(noCentavo(c2)).toBe(51779);
  });

  it('o rateio fecha ao centavo por campanha qualquer que seja o número de linhas (resto na maior parte)', () => {
    const muitos: DesempenhoDia[] = [];
    for (let i = 1; i <= 7; i += 1) {
      const d = `2026-10-${String(i).padStart(2, '0')}`;
      muitos.push(dia('a-cons', d, 3.33 + i / 7), dia('a-iscas', d, 11.11 + i / 3));
    }
    const t = { ...trafego, dias: muitos, gastoCampanhas: [{ campanhaId: 'k-c2', gasto: 333.33 }] };
    const r = ratear(muitos, t, indexar(t));
    expect(r.dias.reduce((s, x) => s + noCentavo(x.gasto), 0)).toBe(33333);
  });

  it('dia sem linha de anúncio não infla as partes: o resto vira Sem detalhe por anúncio e a soma fecha', () => {
    const diario = [{ campanhaId: 'k-c2', dia: '2026-10-14', gasto: 100 }, { campanhaId: 'k-c2', dia: '2026-10-15', gasto: 417.79 },
      { campanhaId: 'k-c3', dia: '2026-10-15', gasto: 1404.71 }, { campanhaId: 'k-c1', dia: '2026-10-15', gasto: 300 }];
    const t: TrafegoBlack = { ...trafego, gastoCampanhasDiario: diario };
    const ix = indexar(t);
    const r = ratear(dias, t, ix);
    expect(r.semDetalhe.get('k-c2')).toBe(100);
    const cons = gastoDaParte(r, ix, 'k-c2', consultoria);
    const isc = gastoDaParte(r, ix, 'k-c2', iscas);
    expect(noCentavo(cons) + noCentavo(isc)).toBe(41779);
    const etapas = cplPorEtapa(dias, [], ix, t.gastoCampanhas, 'todos', diario);
    const sem = etapas.find((e) => e.nivel === 'sem_detalhe')!;
    expect(sem.rotulo).toBe('Sem detalhe por anúncio');
    expect(sem.cpl.gasto).toBe(100);
    expect(sem.cpl.valor).toBeNull();
    const g = (chave: string) => etapas.find((e) => e.chave === chave)!.cpl.gasto;
    expect(noCentavo(g('consultoria')) + noCentavo(g('iscas')) + noCentavo(sem.cpl.gasto)).toBe(51779);
    expect(somaSemDetalhe(r, ix, (c) => c.linha === 'c2')).toBe(100);
    expect(somaSemDetalhe(r, ix, (c) => c.canal === 'google')).toBe(0);
  });

  it('campanha única sem linha de anúncio no recorte: a parte é null (sem dado) e o gasto fica em Sem detalhe', () => {
    const so: DesempenhoDia[] = [dia('a-c1', '2026-10-15', 300)];
    const r = ratear(so, trafego, idx);
    expect(gastoDaParte(r, idx, 'k-c3')).toBeNull();
    expect(r.semDetalhe.get('k-c3')).toBe(1404.71);
    expect(r.semDetalhe.get('k-c2')).toBe(517.79);
  });

  it('sem gasto por campanha na fonte: gasto cru por anúncio, como antes (não inventa total)', () => {
    const r = ratear(dias, { gastoCampanhas: undefined }, idx);
    expect(r.dias.map((x) => x.gasto)).toEqual(dias.map((x) => x.gasto));
    expect(r.semDetalhe.size).toBe(0);
  });

  it('Jornada: os nós de Consultoria e Iscas somam a campanha; nó de campanha única recebe o Sem detalhe', () => {
    const r = ratear(dias, trafego, idx);
    const mapa = calcularJornada({ dias: r.dias, linhas: [], linhasDoFunil: [], idx, config: CONFIG_BLACK, agora: new Date(RELOGIO_PADRAO), mensageria: null });
    const invest = (no: string) => mapa[no].find((x) => x.rotulo === 'Investimento')?.valor ?? null;
    expect(noCentavo(invest('aplicacao-consultoria')) + noCentavo(invest('pagina-isca'))).toBe(51779);
    expect(noCentavo(invest('captacao-direta'))).toBe(140471);
    // C3 sem nenhuma linha de anúncio no recorte: o gasto da campanha vai inteiro para o nó da C3.
    const semC3 = ratear(dias.filter((x) => x.anuncioId !== 'a-c3'), trafego, idx);
    const m2 = calcularJornada({
      dias: semC3.dias, linhas: [], linhasDoFunil: [], idx, config: CONFIG_BLACK, agora: new Date(RELOGIO_PADRAO), mensageria: null,
      semDetalhe: { c3: somaSemDetalhe(semC3, idx, (c) => c.linha === 'c3') },
    });
    expect(noCentavo(m2['captacao-direta'].find((x) => x.rotulo === 'Investimento')?.valor)).toBe(140471);
  });

  it('Dia e Criativo continuam por anúncio: filtrarDias devolve o gasto cru, sem rateio', () => {
    const cru = filtrarDias(dias, idx, { funil: 'consultoria', canal: 'todos' });
    expect(cru.reduce((s, x) => s + noCentavo(x.gasto), 0)).toBe(8710);
  });
});

describe('borda: investimento em captação de um recorte sem campanha de captação é "sem dado", nunca R$ 0,00', () => {
  it('canal Google sem campanha do Google, fases sem campanha de captação e funil C1 devolvem null', () => {
    const soMeta: TrafegoBlack = { ...trafego, campanhas: campanhas.filter((c) => c.canal === 'meta') };
    expect(investimentoDoRecorteValor(soMeta, periodo, { funil: 'todos', canal: 'google' })).toBeNull();
    expect(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.fase === 'antecipacao' })).toBeNull();
    expect(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.fase === 'remarketing' })).toBeNull();
    expect(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.linha === 'remarketing_pagina' })).toBeNull();
    expect(investimentoDoRecorteValor(trafego, periodo, { funil: 'c1', canal: 'todos' })).toBeNull();
    // o mesmo recorte no CPL já era null: card e CPL concordam.
    expect(cplDoRecorte(trafego, periodo, [], [], idx, { funil: 'todos', canal: 'todos', campanha: (c) => c.fase === 'antecipacao' }).valor).toBeNull();
  });

  it('recorte com campanha de captação continua devolvendo o número da campanha', () => {
    expect(noCentavo(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'todos' }))).toBe(192250);
    expect(noCentavo(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'google' }))).toBe(140471);
    expect(noCentavo(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'meta' }))).toBe(51779);
    expect(noCentavo(investimentoDoRecorteValor(trafego, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.fase === 'captacao' }))).toBe(192250);
  });
});

// Coleta de anúncios atrasada (já aconteceu, sem_tempo): a campanha tem gasto e nenhum, ou só alguns, anúncios no recorte.
describe('coleta de anúncios atrasada: o gasto sem anúncio aparece no funil, na Jornada e na ColunaC1 e a soma das partes fecha com o card', () => {
  const card = (t: TrafegoBlack) => noCentavo(investimentoDeCaptacao(t, periodo, { funil: 'todos', canal: 'todos' }).total);
  // A soma que o "Por funil" do modal mostra: uma linha por funil + a linha "Sem detalhe por anúncio" (a mesma conta do ModalCard).
  const somaPorFunil = (t: TrafegoBlack) => {
    const ix = indexar(t);
    const linhas = FUNIS.map((f) => investimentoDoRecorteValor(t, periodo, { funil: f, canal: 'todos' }));
    const rmk = investimentoDoRecorteValor(t, periodo, { funil: 'todos', canal: 'todos', campanha: (c) => c.linha === 'remarketing_pagina' });
    const sem = semDetalheMista(ratear(t.dias, t, ix), ix, 'todos');
    return [...linhas, rmk].reduce<number>((s, v) => s + noCentavo(v ?? 0), 0) + noCentavo(sem);
  };

  it('c2 sem nenhum anúncio: Por funil + Sem detalhe = card, e a Jornada tem o valor para a nota', () => {
    const semC2 = dias.filter((x) => x.anuncioId !== 'a-cons' && x.anuncioId !== 'a-iscas');
    const t: TrafegoBlack = { ...trafego, dias: semC2 };
    const ix = indexar(t);
    expect(card(t)).toBe(192250);
    // Sem a linha extra, as linhas do funil dariam só a C3: 1.404,71 contra o card de 1.922,50 (o defeito reproduzido).
    expect(somaPorFunil(t) - noCentavo(semDetalheMista(ratear(semC2, t, ix), ix, 'todos'))).toBe(140471);
    expect(somaPorFunil(t)).toBe(192250);
    const r = ratear(semC2, t, ix);
    expect(semDetalheMista(r, ix, 'todos')).toBe(517.79);
    expect(semDetalheMista(r, ix, 'meta')).toBe(517.79);
    expect(semDetalheMista(r, ix, 'google')).toBe(0);
    // Consultoria e Iscas ficam sem dado (não inventa a divisão).
    expect(gastoDaParte(r, ix, 'k-c2', consultoria)).toBeNull();
    expect(gastoDaParte(r, ix, 'k-c2', iscas)).toBeNull();
    // CPL por etapa: a mesma linha, só gasto.
    const etapas = cplPorEtapa(semC2, [], ix, t.gastoCampanhas, 'todos', t.gastoCampanhasDiario);
    const sem = etapas.find((e) => e.nivel === 'sem_detalhe')!;
    expect(sem.cpl.gasto).toBe(517.79);
    expect(sem.cpl.valor).toBeNull();
  });

  it('c2 com anúncio em parte dos dias: Por funil + Sem detalhe = card', () => {
    const diario = [{ campanhaId: 'k-c2', dia: '2026-10-14', gasto: 100 }, { campanhaId: 'k-c2', dia: '2026-10-15', gasto: 417.79 },
      { campanhaId: 'k-c3', dia: '2026-10-15', gasto: 1404.71 }, { campanhaId: 'k-c1', dia: '2026-10-15', gasto: 300 }];
    const t: TrafegoBlack = { ...trafego, gastoCampanhasDiario: diario };
    expect(somaPorFunil(t)).toBe(card(t));
  });

  it('com todos os anúncios não aparece linha de sem detalhe (nada some nem duplica)', () => {
    const ix = indexar(trafego);
    expect(semDetalheMista(ratear(dias, trafego, ix), ix, 'todos')).toBe(0);
    expect(somaPorFunil(trafego)).toBe(card(trafego));
  });

  it('ColunaC1: campanha C1 com gasto e nenhum anúncio entra pelo valor da campanha', () => {
    const semC1 = dias.filter((x) => x.anuncioId !== 'a-c1');
    const ix = indexar(trafego);
    const r = ratear(semC1, trafego, ix);
    // A tela filtra `dias` por funil C1 antes de chamar; com a coleta atrasada ele chega vazio.
    const diasC1: DesempenhoDia[] = [];
    const gastoColuna = noCentavo(ratear(diasC1, trafego, ix).dias.reduce((s, x) => s + x.gasto, 0)) + noCentavo(semDetalheDoFunil(ratear(diasC1, trafego, ix), ix, 'c1', 'todos'));
    expect(gastoColuna).toBe(30000);
    // O mesmo número da linha "C1 · Distribuição" do CPL por etapa.
    expect(noCentavo(investimentoTrafego(trafego, { funil: 'c1', canal: 'todos' }).valor)).toBe(gastoColuna);
    // Canal sem a campanha, e outros funis, não entram.
    expect(semDetalheDoFunil(r, ix, 'c1', 'google')).toBe(0);
    expect(semDetalheDoFunil(r, ix, 'c3', 'todos')).toBe(0);
  });

  it('ColunaC1: com anúncio, o gasto dos anúncios rateado + o resto = o valor da campanha', () => {
    const diario = [{ campanhaId: 'k-c1', dia: '2026-10-14', gasto: 100 }, { campanhaId: 'k-c1', dia: '2026-10-15', gasto: 200 }];
    const t: TrafegoBlack = { ...trafego, gastoCampanhasDiario: diario };
    const ix = indexar(t);
    const diasC1 = dias.filter((x) => x.anuncioId === 'a-c1');
    const r = ratear(diasC1, t, ix);
    const gasto = noCentavo(r.dias.reduce((s, x) => s + x.gasto, 0)) + noCentavo(semDetalheDoFunil(r, ix, 'c1', 'todos'));
    expect(gasto).toBe(30000);
    expect(semDetalheDoFunil(r, ix, 'c1', 'todos')).toBe(100);
  });
});
