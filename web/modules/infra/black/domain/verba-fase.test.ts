import { describe, expect, it } from 'vitest';
import { FOLGA_DA_TRILHA, verbaDaFase } from './verba-fase';

describe('verbaDaFase', () => {
  it('gastou R$ 1.000 com limite de R$ 50.000: 2% do limite e faltam R$ 49.000', () => {
    const v = verbaDaFase(1000, 50000);
    expect(v.situacao).toBe('dentro');
    expect(v.pctDoLimite).toBeCloseTo(0.02, 10);
    expect(v.saldo).toBe(49000);
    expect(v.marcador).toBeCloseTo(1 / FOLGA_DA_TRILHA, 10);
    expect(v.preenchimento).toBeCloseTo(1000 / (50000 * FOLGA_DA_TRILHA), 10);
  });

  it('a trilha sempre cabe o limite e o gasto (marco e preenchimento entre 0 e 1)', () => {
    for (const [g, l] of [[0, 100], [99, 100], [100, 100], [250, 100], [1, 1e6], [15110.2, 17591]] as const) {
      const v = verbaDaFase(g, l);
      expect(v.marcador).toBeGreaterThan(0);
      expect(v.marcador).toBeLessThanOrEqual(1);
      expect(v.preenchimento).toBeGreaterThanOrEqual(0);
      expect(v.preenchimento).toBeLessThanOrEqual(1);
    }
  });

  it('passou do limite: saldo negativo, pct acima de 100% e o marco recua para a esquerda do fim da barra', () => {
    const v = verbaDaFase(60000, 50000);
    expect(v.situacao).toBe('estourou');
    expect(v.saldo).toBe(-10000);
    expect(v.pctDoLimite).toBeCloseTo(1.2, 10);
    expect(v.marcador as number).toBeLessThan(v.preenchimento);
    expect(v.preenchimento).toBeCloseTo(1 / FOLGA_DA_TRILHA, 10);
  });

  it('gasto igual ao limite (até o centavo) é "no limite", não estouro nem sobra', () => {
    expect(verbaDaFase(50000, 50000).situacao).toBe('no_limite');
    expect(verbaDaFase(50000.001, 50000).situacao).toBe('no_limite');
  });

  it('gasto nulo é "sem dado": mantém o marco, não inventa gasto zero nem percentual', () => {
    const v = verbaDaFase(null, 30000);
    expect(v.situacao).toBe('sem_dado');
    expect(v.gasto).toBeNull();
    expect(v.pctDoLimite).toBeNull();
    expect(v.saldo).toBeNull();
    expect(v.preenchimento).toBe(0);
    expect(v.marcador).toBeCloseTo(1 / FOLGA_DA_TRILHA, 10);
  });

  it('gasto zero medido é zero de verdade: 0% e saldo cheio', () => {
    const v = verbaDaFase(0, 30000);
    expect(v.situacao).toBe('dentro');
    expect(v.pctDoLimite).toBe(0);
    expect(v.saldo).toBe(30000);
  });

  it('sem limite cadastrado (null, undefined, zero, NaN): nenhuma conta contra o limite', () => {
    for (const lim of [null, undefined, 0, Number.NaN]) {
      const v = verbaDaFase(1234, lim);
      expect(v.situacao).toBe('sem_limite');
      expect(v.limite).toBeNull();
      expect(v.pctDoLimite).toBeNull();
      expect(v.saldo).toBeNull();
      expect(v.marcador).toBeNull();
      expect(v.gasto).toBe(1234);
    }
  });

  it('gasto negativo ou não finito não vira número: sem dado', () => {
    expect(verbaDaFase(-5, 100).situacao).toBe('sem_dado');
    expect(verbaDaFase(Number.POSITIVE_INFINITY, 100).situacao).toBe('sem_dado');
  });
});
