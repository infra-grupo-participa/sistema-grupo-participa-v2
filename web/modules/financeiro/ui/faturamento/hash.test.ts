import { describe, expect, it } from 'vitest';
import { hashDaSubAbaFaturamento, subAbaFaturamentoDoHash } from './hash';

describe('sub-abas do Faturamento no hash', () => {
  it('sem query ou valor desconhecido: Por período', () => {
    expect(subAbaFaturamentoDoHash(undefined)).toBe('periodo');
    expect(subAbaFaturamentoDoHash('')).toBe('periodo');
    expect(subAbaFaturamentoDoHash('ver=taxa')).toBe('periodo');
    expect(subAbaFaturamentoDoHash('produto=HM')).toBe('periodo');
  });
  it('ver=caixa: Caixa Hotmart', () => {
    expect(subAbaFaturamentoDoHash('ver=caixa')).toBe('caixa');
  });
  it('Por período usa o hash limpo do menu; ida e volta', () => {
    expect(hashDaSubAbaFaturamento('periodo')).toBe('#faturamento');
    expect(hashDaSubAbaFaturamento('caixa')).toBe('#faturamento?ver=caixa');
    for (const s of ['periodo', 'caixa'] as const) {
      expect(subAbaFaturamentoDoHash(hashDaSubAbaFaturamento(s).split('?')[1])).toBe(s);
    }
  });
});
