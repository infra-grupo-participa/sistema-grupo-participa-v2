import { describe, expect, it } from 'vitest';
import { compararMeta } from './meta';

describe('compararMeta · direção do indicador', () => {
  it('maior é melhor: acima é verde e abaixo é amarelo ou vermelho conforme a distância', () => {
    expect(compararMeta(0.9, 0.8).estado).toBe('bom');
    expect(compararMeta(0.9, 0.8).distancia).toBe('13% acima da meta');
    expect(compararMeta(0.76, 0.8).estado).toBe('atencao');
    expect(compararMeta(0.76, 0.8).distancia).toBe('5% abaixo da meta');
    expect(compararMeta(0.7, 0.8).estado).toBe('ruim');
    expect(compararMeta(0.7, 0.8).distancia).toBe('13% abaixo da meta');
  });

  it('menor é melhor: abaixo é verde e acima é amarelo ou vermelho conforme a distância', () => {
    expect(compararMeta(90, 100, true).estado).toBe('bom');
    expect(compararMeta(90, 100, true).distancia).toBe('10% abaixo da meta');
    expect(compararMeta(105, 100, true).estado).toBe('atencao');
    expect(compararMeta(105, 100, true).distancia).toBe('5% acima da meta');
    expect(compararMeta(120, 100, true).estado).toBe('ruim');
    expect(compararMeta(120, 100, true).distancia).toBe('20% acima da meta');
  });

  it('usa uma casa decimal abaixo de 1% e rotula igualdade como na meta', () => {
    expect(compararMeta(99.2, 100).distancia).toBe('0,8% abaixo da meta');
    expect(compararMeta(100.4, 100).distancia).toBe('0,4% acima da meta');
    expect(compararMeta(100, 100).distancia).toBe('na meta');
  });

  it('mantém a régua especial do CPL: ideal verde, faixa até o limite amarela', () => {
    expect(compararMeta(14, 16.7, true, 15).estado).toBe('bom');
    expect(compararMeta(15.5, 16.7, true, 15).estado).toBe('atencao');
    expect(compararMeta(18, 16.7, true, 15).estado).toBe('ruim');
    expect(compararMeta(18, 16.7, true, 15).distancia).toBe('8% acima da meta');
    expect(compararMeta(16.7, 15, true, 16).estado).toBe('sem');
  });

  it('zero também é valor mensurável; sem valor ou meta não inventa comparação', () => {
    expect(compararMeta(0, 0.2).estado).toBe('ruim');
    expect(compararMeta(0, 0.2).distancia).toBe('100% abaixo da meta');
    expect(compararMeta(null, 0.2)).toEqual({ estado: 'sem', pctDaMeta: null, distancia: null });
    expect(compararMeta(0.2, null)).toEqual({ estado: 'sem', pctDaMeta: null, distancia: null });
    expect(compararMeta(0.2, 0)).toEqual({ estado: 'sem', pctDaMeta: null, distancia: null });
    expect(compararMeta(Number.NaN, 1)).toEqual({ estado: 'sem', pctDaMeta: null, distancia: null });
  });
});
