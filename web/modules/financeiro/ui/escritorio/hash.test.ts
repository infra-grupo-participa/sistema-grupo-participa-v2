import { describe, expect, it } from 'vitest';
import { hashDaSubAbaEscritorio, subAbaEscritorioDoHash } from './hash';

describe('sub-abas do Escritório no hash', () => {
  it('sem query ou valor desconhecido: Funil', () => {
    expect(subAbaEscritorioDoHash(undefined)).toBe('funil');
    expect(subAbaEscritorioDoHash('')).toBe('funil');
    expect(subAbaEscritorioDoHash('ver=outra')).toBe('funil');
  });
  it('Contratos ainda não ativa: o link cai no Funil, nunca numa sub-aba vazia', () => {
    expect(subAbaEscritorioDoHash('ver=contratos')).toBe('funil');
  });
  it('Funil usa o hash limpo do menu; ida e volta', () => {
    expect(hashDaSubAbaEscritorio('funil')).toBe('#escritorio');
    expect(hashDaSubAbaEscritorio('contratos')).toBe('#escritorio?ver=contratos');
    expect(subAbaEscritorioDoHash(hashDaSubAbaEscritorio('funil').split('?')[1])).toBe('funil');
  });
});
