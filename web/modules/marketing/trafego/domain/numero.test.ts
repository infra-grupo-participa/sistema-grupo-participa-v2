import { describe, expect, it } from 'vitest';
import { lerNumeroBR, numeroParaBanco, numeroParaCampo } from './numero';

describe('lerNumeroBR', () => {
  it('lê milhar e decimal no jeito brasileiro', () => {
    expect(lerNumeroBR('10.000')).toBe(10000);
    expect(lerNumeroBR('10.000,50')).toBe(10000.5);
    expect(lerNumeroBR('1.234.567')).toBe(1234567);
    expect(lerNumeroBR('1500,5')).toBe(1500.5);
    expect(lerNumeroBR('12,5%')).toBe(12.5);
    expect(lerNumeroBR('R$ 1.200')).toBe(1200);
  });
  it('ponto que não é milhar é decimal', () => {
    expect(lerNumeroBR('12.5')).toBe(12.5);
    expect(lerNumeroBR('1500.75')).toBe(1500.75);
  });
  it('negativo, vazio e pela metade', () => {
    expect(lerNumeroBR('-7')).toBe(-7);
    expect(lerNumeroBR('')).toBeNull();
    expect(lerNumeroBR('  ')).toBeNull();
    expect(lerNumeroBR('-')).toBeUndefined();
    expect(lerNumeroBR('12,')).toBeUndefined();
    expect(lerNumeroBR('abc')).toBeUndefined();
    expect(lerNumeroBR('1,2,3')).toBeUndefined();
  });
});

describe('numeroParaBanco e numeroParaCampo', () => {
  it('converte para o banco e de volta para o campo', () => {
    expect(numeroParaBanco('10.000')).toBe('10000');
    expect(numeroParaBanco('')).toBe('');
    expect(numeroParaBanco('dez')).toBeNull();
    expect(numeroParaCampo(12.5)).toBe('12,5');
    expect(numeroParaCampo(null)).toBe('');
  });
});
