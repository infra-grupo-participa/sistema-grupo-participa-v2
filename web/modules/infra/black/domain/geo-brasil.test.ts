import { describe, expect, it } from 'vitest';
import { CONTORNO_BRASIL, UFS, VIEWBOX_BRASIL } from './geo-brasil';

describe('geo-brasil (malha do IBGE)', () => {
  it('27 UFs, siglas únicas, 5 regiões', () => {
    expect(UFS).toHaveLength(27);
    expect(new Set(UFS.map((u) => u.sigla)).size).toBe(27);
    expect(new Set(UFS.map((u) => u.regiao))).toEqual(new Set(['Norte', 'Nordeste', 'Centro-Oeste', 'Sudeste', 'Sul']));
  });
  it('centroides dentro do viewBox e contornos em path SVG', () => {
    for (const u of UFS) {
      expect(u.x).toBeGreaterThan(0); expect(u.x).toBeLessThan(VIEWBOX_BRASIL.largura);
      expect(u.y).toBeGreaterThan(0); expect(u.y).toBeLessThan(VIEWBOX_BRASIL.altura);
      expect(u.contorno).toMatch(/^M[\d.,L-]+Z/);
    }
    expect(CONTORNO_BRASIL).toMatch(/^M[\d.,L-]+Z/);
  });
  it('sanidade da projeção: norte em cima, leste à direita', () => {
    const p = (s: string) => UFS.find((u) => u.sigla === s)!;
    expect(p('RR').y).toBeLessThan(p('RS').y);
    expect(p('AC').x).toBeLessThan(p('PE').x);
    expect(p('RJ').x).toBeGreaterThan(p('SP').x);
  });
});
