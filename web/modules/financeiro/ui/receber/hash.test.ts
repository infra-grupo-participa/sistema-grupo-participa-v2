import { describe, expect, it } from 'vitest';
import { hashDaSubAbaReceber, subAbaReceberDoHash } from './hash';

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
  });
  it('ida e volta: parse(escrever(x)) === x', () => {
    for (const s of ['semana', 'recorrencias', 'informados', 'eventos', 'premissas'] as const) {
      const h = hashDaSubAbaReceber(s);
      const [, query] = h.split('?');
      expect(subAbaReceberDoHash(query)).toBe(s);
    }
  });
});
