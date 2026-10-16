import { describe, expect, it } from 'vitest';
import { funisDaEtapa, motivoFora } from './funis-etapa';
import { indexar } from './metricas';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, LinhaPerfil, TrafegoBlack } from './tipos';

// Nomes REAIS do guia do Caio (15/10/2026). `linha`, `no` e `iscaBanco` são o que a RPC dados_black_trafego devolve.
const ETQ = 'black-friday-2026-10';
const camp = (id: string, nome: string, linha: Campanha['linha'], extra: Partial<Campanha> = {}): Campanha =>
  ({ id, nome, canal: 'meta', funil: null, fase: null, linha, ...extra });
const conj = (id: string, campanhaId: string, nome: string, extra: Partial<Conjunto> = {}): Conjunto => ({ id, campanhaId, nome, isca: null, conjuntoC3: null, ...extra });
const anu = (id: string, conjuntoId: string, nome: string): Anuncio => ({ id, conjuntoId, nome, formato: 'video', paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null });
const dia = (anuncioId: string, gasto: number): DesempenhoDia => ({ anuncioId, dia: '2026-10-14', gasto, impressoes: 1000, cliquesLink: 10, landingPageViews: 8, alcance: null, frequencia: null, videoP50: null, videoP75: null, thruplay: null });
const lead = (leadId: string, campanhaId: string, conjuntoId: string | null, isca: LinhaPerfil['isca'] = null): LinhaPerfil => ({ leadId, pessoaId: leadId, campanhaId, conjuntoId, isca } as unknown as LinhaPerfil);

const NOME = {
  teaser: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`,
  distribuicao: `CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | ${ETQ}`,
  manifesto: `CF | BF26 | AQUECIMENTO | FB | PQ | ABO | ${ETQ}`,
  iscas: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`,
  base: `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`,
  entresafra: `CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | ${ETQ}`,
};

const trafego: TrafegoBlack = {
  campanhas: [
    camp('t', NOME.teaser, 'c1'),
    camp('d', NOME.distribuicao, 'distribuicao'),
    camp('m', NOME.manifesto, 'c1'),
    camp('sem', 'Campanha antiga', null),
    camp('ent', NOME.entresafra, 'pre_captacao'),
    camp('isca', NOME.iscas, 'c2'),
    camp('base', NOME.base, 'c3'),
  ],
  conjuntos: [
    conj('jt', 't', 'C1 | TEASER | LEADS HT', { linha: 'c1', no: 'teaser' }),
    conj('jt0', 't', 'PQ | 00 | LEADS HT', { linha: 'c1', no: 'teaser' }), // nome antigo, ainda válido
    conj('jd', 'd', 'C1 | REELS | ADV+', { linha: 'distribuicao', no: 'reels_pago' }),
    conj('jm', 'm', 'MANIFESTO EP02 | MQL CNHF  2.0', { linha: 'c1', no: 'manifesto' }),
    conj('js', 'sem', 'PQ | X', { linha: null, no: null }),
    conj('je', 'ent', 'PQ | X', { linha: 'pre_captacao', no: 'pre_captacao' }),
    conj('jcons', 'isca', 'VV C1 | CONSULTORIA', { linha: 'consultoria', no: 'consultoria', iscaBanco: 'CONSULTORIA' }),
    conj('jflux', 'isca', 'VV C1 | FLUXOGRAMA', { linha: 'iscas', no: 'iscas', iscaBanco: 'FLUXOGRAMA', isca: 'Fluxograma' }),
    conj('jchk', 'isca', 'VV C1 | CHECKUP', { linha: 'iscas', no: 'iscas', iscaBanco: 'CHECKUP', isca: 'Checkup' }),
    conj('joutra', 'isca', 'MIX PQ', { linha: 'iscas', no: 'iscas', iscaBanco: null, isca: null }),
    conj('jbase', 'base', 'C3 | MIX PQ | CONVITE--DIRETO_01', { linha: 'c3', no: 'c3' }),
  ],
  anuncios: [
    anu('at', 'jt', 'a'), anu('at0', 'jt0', 'a'), anu('ad', 'jd', 'a'), anu('am', 'jm', 'a'), anu('as', 'js', 'a'), anu('ae', 'je', 'a'),
    anu('acons', 'jcons', 'a'), anu('aflux', 'jflux', 'a'), anu('achk', 'jchk', 'a'), anu('aoutra', 'joutra', 'a'), anu('abase', 'jbase', 'a'),
  ],
  paginas: [], dias: [], totais: [], coletadoEm: null,
  gastoCampanhas: [
    { campanhaId: 't', gasto: 111 }, { campanhaId: 'd', gasto: 40 }, { campanhaId: 'm', gasto: 50 }, { campanhaId: 'isca', gasto: 100 }, { campanhaId: 'base', gasto: 60 },
  ],
};
const idx = indexar(trafego);
const dias = [dia('at', 100), dia('at0', 11), dia('ad', 40), dia('am', 50), dia('as', 7), dia('ae', 500),
  dia('acons', 10), dia('aflux', 20), dia('achk', 30), dia('aoutra', 40), dia('abase', 60)];
const soma = (ds: DesempenhoDia[]) => ds.reduce((s, x) => s + x.gasto, 0);

describe('funis da etapa lado a lado', () => {
  it('C1: uma coluna por peça do banco (conjunto); a distribuição (PF) tem coluna própria', () => {
    const r = funisDaEtapa('c1', trafego, dias, [], idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual(['Teaser', 'Distribuição', 'Manifesto']);
    // O teaser junta o conjunto novo (C1 | TEASER) e o antigo (PQ | 00): mesma campanha, gasto da campanha inteira.
    expect(soma(r.colunas[0].dias)).toBe(111);
    expect(r.colunas[0].conjuntos.map((j) => j.nome)).toEqual(['C1 | TEASER | LEADS HT', 'PQ | 00 | LEADS HT']);
    expect(r.colunas[0].gasto).toBe(111);
    expect(r.colunas[2].campanhas.map((c) => c.nome)).toEqual([NOME.manifesto]);
  });

  it('sem classificação fica fora, com o nome exato; pré-captação não conta em lugar nenhum', () => {
    for (const funil of ['c1', 'consultoria', 'iscas', 'c3'] as const) {
      const r = funisDaEtapa(funil, trafego, dias, [], idx);
      expect(r.fora.map((x) => [x.campanha.nome, x.motivo])).toEqual([['Campanha antiga', 'sem classificação']]);
      expect(r.colunas.flatMap((c) => c.campanhas).some((c) => c.id === 'ent' || c.id === 'sem')).toBe(false);
    }
  });

  it('campanha sem dado no recorte não entra nem como fora', () => {
    const r = funisDaEtapa('c1', trafego, dias.filter((x) => x.anuncioId !== 'as'), [], idx);
    expect(r.fora).toEqual([]);
  });

  it('Consultoria: só o conjunto VV C1 | CONSULTORIA, com o gasto dos anúncios dele (a campanha é mista)', () => {
    const r = funisDaEtapa('consultoria', trafego, dias, [lead('1', 'isca', 'jcons'), lead('2', 'isca', 'jflux', 'Fluxograma')], idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual(['Consultoria']);
    expect(r.colunas[0].conjuntos.map((j) => j.nome)).toEqual(['VV C1 | CONSULTORIA']);
    expect(r.colunas[0].gasto).toBe(10);
    expect(r.colunas[0].linhas.map((l) => l.leadId)).toEqual(['1']);
  });

  it('Iscas: uma coluna por isca do banco, sem a consultoria; conjunto sem isca reconhecida é avisado', () => {
    const leads = [lead('1', 'isca', 'jchk', 'Checkup'), lead('2', 'isca', 'jchk', 'Checkup'), lead('3', 'isca', 'jflux', 'Fluxograma'), lead('4', 'isca', 'jcons')];
    const r = funisDaEtapa('iscas', trafego, dias, leads, idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual(['Fluxograma', 'Checkup']);
    expect(r.colunas.find((c) => c.rotulo === 'Checkup')?.linhas.map((l) => l.leadId)).toEqual(['1', '2']);
    expect(soma(r.colunas.find((c) => c.rotulo === 'Fluxograma')?.dias ?? [])).toBe(20);
    expect(r.colunas.flatMap((c) => c.linhas).map((l) => l.leadId)).not.toContain('4');
    expect(r.conjuntosSemIsca.map((j) => j.nome)).toEqual(['MIX PQ']);
  });

  it('Consultoria + Iscas somam o gasto dos anúncios da campanha mista (nada some nem conta duas vezes)', () => {
    const cons = funisDaEtapa('consultoria', trafego, dias, [], idx).colunas;
    const rIscas = funisDaEtapa('iscas', trafego, dias, [], idx);
    const gastoAnuncios = soma(dias.filter((d) => ['acons', 'aflux', 'achk', 'aoutra'].includes(d.anuncioId)));
    // O conjunto sem isca reconhecida (MIX PQ, 40) não vira coluna: aparece no aviso `conjuntosSemIsca`, e o gasto dele fecha a conta.
    const gastoSemIsca = soma(dias.filter((d) => rIscas.conjuntosSemIsca.some((j) => idx.conjuntoDoAnuncio(d.anuncioId)?.id === j.id)));
    expect(gastoSemIsca).toBe(40);
    expect(soma([...cons, ...rIscas.colunas].flatMap((c) => c.dias)) + gastoSemIsca).toBe(gastoAnuncios);
  });

  it('C3: coluna pelo nome exato da campanha, com o gasto dela', () => {
    const r = funisDaEtapa('c3', trafego, dias, [], idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual([NOME.base]);
    expect(r.colunas[0].gasto).toBe(60);
  });

  it('motivoFora: só a campanha que o banco não classificou é fora', () => {
    expect(motivoFora(trafego.campanhas[0])).toBeNull();
    expect(motivoFora(trafego.campanhas[4])).toBeNull(); // pré-captação é classificada: não é "fora"
    expect(motivoFora(trafego.campanhas[3])).toBe('sem classificação');
  });
});
