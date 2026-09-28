import { describe, expect, it } from 'vitest';
import { filtroReceberDoHash, hashDaSubAbaReceber, hashReceberFiltrado, subAbaReceberDoHash } from './hash';

describe('subAbaReceberDoHash', () => {
  it('sem query: grade (Semana a semana)', () => {
    expect(subAbaReceberDoHash(undefined)).toBe('semana');
    expect(subAbaReceberDoHash(null)).toBe('semana');
    expect(subAbaReceberDoHash('')).toBe('semana');
  });
  it('ver=recorrencias e ver=informados: reconhecidos', () => {
    expect(subAbaReceberDoHash('ver=recorrencias')).toBe('recorrencias');
    expect(subAbaReceberDoHash('ver=informados')).toBe('informados');
    expect(subAbaReceberDoHash('ver=premissas')).toBe('premissas');
    expect(subAbaReceberDoHash('ver=eventos')).toBe('eventos');
    expect(subAbaReceberDoHash('ver=base')).toBe('base');
  });
  it('valor desconhecido ou outro parâmetro: cai na grade, não quebra', () => {
    expect(subAbaReceberDoHash('ver=carteira')).toBe('semana');
    expect(subAbaReceberDoHash('produto=HM')).toBe('semana');
  });
});

describe('hashDaSubAbaReceber', () => {
  it('semana: hash limpo, igual ao link do menu', () => {
    expect(hashDaSubAbaReceber('semana')).toBe('#receber');
  });
  it('recorrencias e informados: com ?ver=', () => {
    expect(hashDaSubAbaReceber('recorrencias')).toBe('#receber?ver=recorrencias');
    expect(hashDaSubAbaReceber('informados')).toBe('#receber?ver=informados');
    expect(hashDaSubAbaReceber('premissas')).toBe('#receber?ver=premissas');
    expect(hashDaSubAbaReceber('eventos')).toBe('#receber?ver=eventos');
    expect(hashDaSubAbaReceber('base')).toBe('#receber?ver=base');
  });
  it('ida e volta: parse(escrever(x)) === x', () => {
    for (const s of ['semana', 'recorrencias', 'informados', 'eventos', 'premissas', 'base'] as const) {
      const h = hashDaSubAbaReceber(s);
      const [, query] = h.split('?');
      expect(subAbaReceberDoHash(query)).toBe(s);
    }
  });
});

describe('filtro de situação pelo hash (links da Visão geral)', () => {
  it('ida e volta: o link filtrado é lido de volta como a mesma sub-aba e o mesmo filtro', () => {
    for (const [sub, sit] of [['recorrencias', 'em_atraso_fora'], ['informados', 'em_atraso_cobrar'], ['eventos', 'encerrado']] as const) {
      const h = hashReceberFiltrado(sub, sit);
      const query = h.split('?')[1];
      expect(subAbaReceberDoHash(query)).toBe(sub);
      expect(filtroReceberDoHash(query)).toBe(sit);
    }
    expect(hashReceberFiltrado('recorrencias', 'em_atraso_fora')).toBe('#receber?ver=recorrencias&situacao=em_atraso_fora');
  });
  it('filtro que a sub-aba não aceita: ignorado (sem filtro), nos dois sentidos', () => {
    expect(filtroReceberDoHash('ver=recorrencias&situacao=encerrado')).toBeNull();
    expect(filtroReceberDoHash('ver=premissas&situacao=em_atraso_fora')).toBeNull();
    expect(filtroReceberDoHash('situacao=em_atraso_fora')).toBeNull(); // sem ver: grade, que não filtra
    expect(filtroReceberDoHash(undefined)).toBeNull();
    expect(hashReceberFiltrado('premissas', 'x')).toBe('#receber?ver=premissas');
    expect(hashReceberFiltrado('eventos', null)).toBe('#receber?ver=eventos');
  });
});
