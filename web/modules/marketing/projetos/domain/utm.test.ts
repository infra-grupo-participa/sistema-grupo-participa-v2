import { describe, expect, it } from 'vitest';
import { origemIds, rotuloUtm, separarUtm } from './utm';
import { traduzirCampanha } from './campanha';

// Os mesmos casos do passo 6b do ensaio da 20261006f (mkt.utm_separar e mkt_web.origem_ids).
describe('separarUtm: padrão do gp-operacoes (nome|id, id depois da última "|")', () => {
  it('campanha nome|id com " | " dentro do nome', () => {
    expect(separarUtm('RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|120211234')).toEqual({
      nome: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', id: '120211234',
    });
  });
  it('anúncio nome|id com espaços em volta', () => {
    expect(separarUtm('  CRIATIVO 01 | 120200000000009 ')).toEqual({ nome: 'CRIATIVO 01', id: '120200000000009' });
  });
  it('só id (formato antigo e Google)', () => {
    expect(separarUtm('120200000000001')).toEqual({ nome: null, id: '120200000000001' });
  });
  it('só nome com " | " (último campo não é número): tudo é nome', () => {
    expect(separarUtm('RS | PB26 | LEADS | TESTE | AK1')).toEqual({ nome: 'RS | PB26 | LEADS | TESTE | AK1', id: null });
  });
  it('só nome sem "|"', () => {
    expect(separarUtm('aula ao vivo')).toEqual({ nome: 'aula ao vivo', id: null });
  });
  it('vazio e nulo', () => {
    expect(separarUtm('   ')).toEqual({ nome: null, id: null });
    expect(separarUtm(null)).toEqual({ nome: null, id: null });
    expect(separarUtm(undefined)).toEqual({ nome: null, id: null });
  });
  it('a tradução lê o NOME: separado antes ou com o id no fim (descartado pela própria tradução desde a auditoria de 06/10)', () => {
    const listas = { gestores: ['RS'], objetivos: ['LEADS'], projetos: ['PB26'] };
    const bruto = 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|120211234';
    expect(traduzirCampanha(bruto, listas).pagina).toBe('ak1');
    const t = traduzirCampanha(separarUtm(bruto).nome, listas);
    expect(t.padrao).toBe(true);
    expect(t.pagina).toBe('ak1');
  });
});

describe('origemIds: ids da visita (igual mkt_web.origem_ids)', () => {
  it('Meta nome|id: campanha, conjunto (utm_medium) e anúncio', () => {
    expect(origemIds({ utm_source: 'metaads', utm_medium: 'CONJ|120300000000001', utm_campaign: 'C|120100000000001', utm_content: 'A|120200000000001' }))
      .toEqual({ campanha_id: '120100000000001', campanha_nome: 'C', conjunto_id: '120300000000001', anuncio_id: '120200000000001', anuncio_nome: 'A' });
  });
  it('utm_medium fora do Meta não vira conjunto', () => {
    expect(origemIds({ utm_source: 'ig', utm_medium: 'paid|123', utm_campaign: 'C|1', utm_content: 'A|2' }).conjunto_id).toBeNull();
  });
  it('parâmetro explícito da URL vale primeiro', () => {
    const r = origemIds({ utm_source: 'metaads', utm_campaign: 'C|1', utm_content: 'A|2', campaign_id: '999', adset_id: '888', ad_id: '777' });
    expect([r.campanha_id, r.conjunto_id, r.anuncio_id]).toEqual(['999', '888', '777']);
  });
  it('Google só id', () => {
    expect(origemIds({ utm_source: 'google', utm_medium: 'cpc', utm_campaign: '22000000001', utm_content: '700000000001' }))
      .toEqual({ campanha_id: '22000000001', campanha_nome: null, conjunto_id: null, anuncio_id: '700000000001', anuncio_nome: null });
  });
});

describe('rotuloUtm', () => {
  it('nome, id ou os dois', () => {
    expect(rotuloUtm('CRIATIVO 01', '1202')).toBe('CRIATIVO 01 · 1202');
    expect(rotuloUtm(null, '1202')).toBe('1202');
    expect(rotuloUtm('CRIATIVO 01', null)).toBe('CRIATIVO 01');
    expect(rotuloUtm(null, null)).toBe('–');
  });
});
