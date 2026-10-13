import { describe, expect, it } from 'vitest';
import { avaliarFaixa, avaliarMeta, distanciaDaMeta } from './meta';

describe('distanciaDaMeta', () => {
  it('acima da meta', () => {
    expect(distanciaDaMeta(1.42)).toBe('42% acima da meta');
    expect(distanciaDaMeta(1.0776)).toBe('8% acima da meta');
  });
  it('abaixo da meta', () => {
    expect(distanciaDaMeta(0.8)).toBe('20% abaixo da meta');
    expect(distanciaDaMeta(0)).toBe('100% abaixo da meta');
  });
  it('exatamente na meta', () => {
    expect(distanciaDaMeta(1)).toBe('na meta');
  });
  it('menos de 1% usa uma casa decimal, para não dizer "0%" sem ter batido a meta', () => {
    expect(distanciaDaMeta(0.992)).toBe('0,8% abaixo da meta');
    expect(distanciaDaMeta(1.004)).toBe('0,4% acima da meta');
  });
  it('sem dado: null', () => {
    expect(distanciaDaMeta(null)).toBeNull();
    expect(distanciaDaMeta(Number.NaN)).toBeNull();
  });
});

describe('avaliarFaixa (CPL: ideal R$ 15, limite R$ 16,70)', () => {
  it('até o ideal é bom', () => {
    expect(avaliarFaixa(12, 15, 16.7).estado).toBe('bom');
    expect(avaliarFaixa(15, 15, 16.7).estado).toBe('bom');
  });
  it('entre o ideal e o limite é atenção, inclusive no limite', () => {
    expect(avaliarFaixa(15.01, 15, 16.7).estado).toBe('atencao');
    expect(avaliarFaixa(16.7, 15, 16.7).estado).toBe('atencao');
  });
  it('acima do limite é ruim; a porcentagem é sobre o limite', () => {
    const r = avaliarFaixa(20, 15, 16.7);
    expect(r.estado).toBe('ruim');
    expect(r.pctDaMeta).toBeCloseTo(1.1976, 3);
    expect(avaliarFaixa(16.71, 15, 16.7).estado).toBe('ruim');
  });
  it('sem valor, sem faixa ou limite abaixo do ideal: sem avaliação', () => {
    expect(avaliarFaixa(null, 15, 16.7).estado).toBe('sem');
    expect(avaliarFaixa(15, null, 16.7).estado).toBe('sem');
    expect(avaliarFaixa(15, 15, null).estado).toBe('sem');
    expect(avaliarFaixa(15, 15, 10).estado).toBe('sem');
  });
});

describe('avaliarMeta', () => {
  it('maior melhor: na meta ou acima é bom', () => {
    expect(avaliarMeta(0.85, 0.85, false)).toEqual({ estado: 'bom', pctDaMeta: 1 });
    const r = avaliarMeta(0.3, 0.2, false);
    expect(r.estado).toBe('bom');
    expect(r.pctDaMeta).toBeCloseTo(1.5, 9);
  });
  it('maior melhor: até 10% abaixo da meta é atenção; além disso é ruim', () => {
    expect(avaliarMeta(0.55, 0.6, false).estado).toBe('atencao'); // 91,7% da meta
    expect(avaliarMeta(0.54, 0.6, false).estado).toBe('atencao'); // 90% exato
    const r = avaliarMeta(0.5, 0.6, false); // 83,3%
    expect(r.estado).toBe('ruim');
    expect(r.pctDaMeta).toBeCloseTo(0.8333, 3);
  });
  it('menor melhor: no teto ou abaixo é bom; até 10% acima é atenção; além é ruim', () => {
    expect(avaliarMeta(16.7, 16.7, true).estado).toBe('bom');
    expect(avaliarMeta(12, 16.7, true).estado).toBe('bom');
    expect(avaliarMeta(18, 16.7, true).estado).toBe('atencao'); // 107,8%
    expect(avaliarMeta(55, 50, true).estado).toBe('atencao'); // 110% exato
    expect(avaliarMeta(60, 50, true).estado).toBe('ruim');
    expect(avaliarMeta(60, 50, true).pctDaMeta).toBeCloseTo(1.2, 5);
  });
  it('zero também é um valor (taxa zerada fica ruim, não some)', () => {
    expect(avaliarMeta(0, 0.2, false)).toEqual({ estado: 'ruim', pctDaMeta: 0 });
  });
  it('sem valor, sem meta ou meta zero: sem avaliação', () => {
    expect(avaliarMeta(null, 0.2, false)).toEqual({ estado: 'sem', pctDaMeta: null });
    expect(avaliarMeta(0.2, null, false)).toEqual({ estado: 'sem', pctDaMeta: null });
    expect(avaliarMeta(0.2, 0, false)).toEqual({ estado: 'sem', pctDaMeta: null });
    expect(avaliarMeta(Number.NaN, 1, true)).toEqual({ estado: 'sem', pctDaMeta: null });
  });
});
