import { describe, expect, it } from 'vitest';
import { funisDaEtapa, motivoFora } from './funis-etapa';
import { indexar } from './metricas';
import type { Anuncio, Campanha, Conjunto, DesempenhoDia, LinhaPerfil, TrafegoBlack } from './tipos';

const camp = (id: string, nome: string, extra: Partial<Campanha>): Campanha => ({ id, nome, canal: 'meta', funil: null, fase: null, ...extra });
const conj = (id: string, campanhaId: string, nome: string): Conjunto => ({ id, campanhaId, nome, isca: null, conjuntoC3: null });
const anu = (id: string, conjuntoId: string, nome: string): Anuncio => ({ id, conjuntoId, nome, formato: 'video', paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null });
const dia = (anuncioId: string, gasto: number): DesempenhoDia => ({ anuncioId, dia: '2026-10-14', gasto, impressoes: 1000, cliquesLink: 10, landingPageViews: 8, alcance: null, frequencia: null, videoP50: null, videoP75: null, thruplay: null });
const lead = (leadId: string, campanhaId: string, isca: LinhaPerfil['isca']): LinhaPerfil => ({ leadId, pessoaId: leadId, campanhaId, isca } as unknown as LinhaPerfil);

const trafego: TrafegoBlack = {
  campanhas: [
    camp('t', 'CF | BF26 | LEADS | TEASER | x', { etapa: 'C1', subtipo: 'TEASER', funil: 'c1' }),
    camp('m', 'CF | BF26 | LEADS | MANIFESTO | x', { etapa: 'C1', subtipo: 'MANIFESTO', funil: 'c1' }),
    camp('m2', 'CF | BF26 | LEADS | MANIFESTO 2 | x', { etapa: 'C1', subtipo: 'MANIFESTO', funil: 'c1' }),
    camp('sem', 'MANIFESTO ANTIGO', { etapa: null, subtipo: null, funil: 'c1' }),
    camp('conf', 'CF | BF26 | LEADS | TEASER MANIFESTO | x', { etapa: 'C1', subtipo: null, conflito: true, funil: null }),
    camp('ent', 'ENTRESAFRA BF26', { etapa: 'C1', subtipo: 'ENTRESAFRA', funil: null }),
    camp('isca', 'CF | BF26 | LEADS | ISCAS | x', { etapa: 'C2', subtipo: 'ISCA', funil: 'iscas' }),
  ],
  conjuntos: [
    conj('jt', 't', 'PQ | TEASER'), conj('jm', 'm', 'PQ | MANIFESTO'), conj('jm2', 'm2', 'PQ | MANIFESTO'),
    conj('js', 'sem', 'PQ | X'), conj('jc', 'conf', 'PQ | X'), conj('je', 'ent', 'PQ | X'),
    conj('ji1', 'isca', 'PQ | CHECKUP'), conj('ji2', 'isca', 'PQ | FUTUROMETRO'), conj('ji3', 'isca', 'PQ | OUTRA'),
  ],
  anuncios: [
    anu('at', 'jt', 'a'), anu('am', 'jm', 'a'), anu('am2', 'jm2', 'a'), anu('as', 'js', 'a'), anu('ac', 'jc', 'a'), anu('ae', 'je', 'a'),
    anu('ai1', 'ji1', 'a'), anu('ai2', 'ji2', 'a'), anu('ai3', 'ji3', 'a'),
  ],
  paginas: [], dias: [], totais: [], coletadoEm: null,
};
const idx = indexar(trafego);
const dias = [dia('at', 100), dia('am', 50), dia('am2', 25), dia('as', 7), dia('ac', 9), dia('ae', 500), dia('ai1', 10), dia('ai2', 20), dia('ai3', 30)];

describe('funis da etapa lado a lado', () => {
  it('C1: uma coluna por subtipo do banco; campanhas do mesmo subtipo ficam juntas', () => {
    const r = funisDaEtapa('c1', trafego, dias, [], idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual(['TEASER', 'MANIFESTO']);
    expect(r.colunas[1].campanhas.map((c) => c.id)).toEqual(['m', 'm2']);
    expect(r.colunas[1].dias.reduce((s, x) => s + x.gasto, 0)).toBe(75);
  });

  it('sem etapa e com conflito ficam fora, com o motivo; Entresafra não conta em lugar nenhum', () => {
    const r = funisDaEtapa('c1', trafego, dias, [], idx);
    expect(r.fora.map((x) => [x.campanha.id, x.motivo])).toEqual([['sem', 'sem etapa'], ['conf', 'conflito de subtipo']]);
    expect(r.colunas.flatMap((c) => c.campanhas).some((c) => c.id === 'ent' || c.id === 'sem' || c.id === 'conf')).toBe(false);
  });

  it('campanha sem dado no recorte não entra nem como fora', () => {
    const r = funisDaEtapa('c1', trafego, dias.filter((x) => x.anuncioId !== 'as' && x.anuncioId !== 'ac'), [], idx);
    expect(r.fora).toEqual([]);
  });

  it('Iscas: uma coluna por isca do último bloco do conjunto; conjunto sem isca reconhecida é avisado', () => {
    const r = funisDaEtapa('iscas', trafego, dias, [lead('1', 'isca', 'Checkup'), lead('2', 'isca', 'Checkup'), lead('3', 'isca', 'Futurômetro'), lead('4', 'm', 'Checkup')], idx);
    expect(r.colunas.map((c) => c.rotulo)).toEqual(['Checkup', 'Futurômetro']);
    expect(r.colunas[0].linhas.map((l) => l.leadId)).toEqual(['1', '2']);
    expect(r.colunas[1].dias.reduce((s, x) => s + x.gasto, 0)).toBe(20);
    expect(r.conjuntosSemIsca.map((j) => j.nome)).toEqual(['PQ | OUTRA']);
  });

  it('motivoFora: campanha completa não é fora', () => {
    expect(motivoFora(trafego.campanhas[0])).toBeNull();
    expect(motivoFora(trafego.campanhas[3])).toBe('sem etapa');
  });
});
