import { describe, expect, it } from 'vitest';
import { hashDaSubAbaEscritorio, subAbaEscritorioDoHash } from './hash';

describe('sub-abas do Escritório no hash', () => {
  it('sem query ou valor desconhecido: Funil', () => {
    expect(subAbaEscritorioDoHash(undefined)).toBe('funil');
    expect(subAbaEscritorioDoHash('')).toBe('funil');
    expect(subAbaEscritorioDoHash('ver=outra')).toBe('funil');
  });
  it('Contratos ativa no hash (a disponibilidade no banco é conferida no EscritorioAba)', () => {
    expect(subAbaEscritorioDoHash('ver=contratos')).toBe('contratos');
    expect(subAbaEscritorioDoHash(hashDaSubAbaEscritorio('contratos').split('?')[1])).toBe('contratos');
  });
  it('Funil usa o hash limpo do menu; ida e volta', () => {
    expect(hashDaSubAbaEscritorio('funil')).toBe('#escritorio');
    expect(hashDaSubAbaEscritorio('contratos')).toBe('#escritorio?ver=contratos');
    expect(subAbaEscritorioDoHash(hashDaSubAbaEscritorio('funil').split('?')[1])).toBe('funil');
  });
});
