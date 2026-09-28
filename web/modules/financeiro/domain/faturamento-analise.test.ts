import { describe, expect, it } from 'vitest';
import { alinharAnterior, intervaloAnterior, mediaMovel, projetarPeriodoAtual } from './faturamento-analise';
import type { PeriodoFaturamento } from './hotmart';

const per = (bruto: number) => ({ bruto } as PeriodoFaturamento);

describe('mediaMovel', () => {
  it('média de 3 com início parcial', () => {
    expect(mediaMovel([3, 6, 9, 12], 3)).toEqual([3, 4.5, 6, 9]);
  });
});

describe('projetarPeriodoAtual', () => {
  const dias = [{ dia: '2026-09-01', bruto: 100 }, { dia: '2026-09-10', bruto: 200 }, { dia: '2026-08-31', bruto: 999 }];
  it('mês corrente pelo ritmo: 300 em 10 de 30 dias → 900', () => {
    const p = projetarPeriodoAtual(dias, 'dia', '2026-09-10', '2026-09-10')!;
    expect(p.alvo).toBe('mes'); expect(p.parcial).toBe(300); expect(p.projetado).toBeCloseTo(900);
  });
  it('não projeta se o intervalo não termina hoje, nem com menos de 3 dias', () => {
    expect(projetarPeriodoAtual(dias, 'dia', '2026-09-10', '2026-09-09')).toBeNull();
    expect(projetarPeriodoAtual(dias, 'mes', '2026-09-02', '2026-09-02')).toBeNull();
  });
  it('ano corrente', () => {
    const p = projetarPeriodoAtual([{ dia: '2026-01-05', bruto: 365 }], 'ano', '2026-12-31', '2026-12-31')!;
    expect(p.alvo).toBe('ano'); expect(p.projetado).toBeCloseTo(365);
  });
});

describe('período anterior', () => {
  it('mesmo número de dias, imediatamente antes', () => {
    expect(intervaloAnterior('2026-09-01', '2026-09-30')).toEqual({ de: '2026-08-02', ate: '2026-08-31' });
  });
  it('alinha pela posição a partir do fim', () => {
    expect(alinharAnterior([per(1), per(2)], [per(9), per(5), per(6)])).toEqual([5, 6]);
    expect(alinharAnterior([per(1), per(2), per(3)], [per(5), per(6)])).toEqual([null, 5, 6]);
  });
});
