import { describe, expect, it } from 'vitest';
import { textoPrazo, vigenciaPrograma } from './vigencia-programa';

describe('vigenciaPrograma', () => {
  it('sem vencimento não há barra', () => {
    expect(vigenciaPrograma('2026-01-01', null, '2026-09-30')).toBeNull();
    expect(vigenciaPrograma('2026-01-01', 'lixo', '2026-09-30')).toBeNull();
  });

  it('percentual decorrido entre início e vencimento', () => {
    const v = vigenciaPrograma('2026-01-01', '2026-01-11', '2026-01-06');
    expect(v).toEqual({ diasRestantes: 5, tom: 'warning', pct: 50 });
  });

  it('tom segue a janela de 30 dias da situação de acesso', () => {
    expect(vigenciaPrograma(null, '2026-10-30', '2026-09-30')?.tom).toBe('warning');
    expect(vigenciaPrograma(null, '2026-10-31', '2026-09-30')?.tom).toBe('success');
    expect(vigenciaPrograma(null, '2026-09-30', '2026-09-30')?.tom).toBe('warning');
    expect(vigenciaPrograma(null, '2026-09-29', '2026-09-30')?.tom).toBe('danger');
  });

  it('aceita timestamp ISO e trava o percentual em 0–100', () => {
    expect(vigenciaPrograma('2026-01-01T03:00:00Z', '2026-02-01', '2025-12-01')?.pct).toBe(0);
    expect(vigenciaPrograma('2026-01-01', '2026-02-01T00:00:00+00:00', '2026-03-01')?.pct).toBe(100);
  });

  it('início ausente ou depois do vencimento: sem percentual, mas com prazo', () => {
    expect(vigenciaPrograma(null, '2026-12-01', '2026-09-30')?.pct).toBeNull();
    expect(vigenciaPrograma('2027-01-01', '2026-12-01', '2026-09-30')).toEqual({ diasRestantes: 62, tom: 'success', pct: null });
  });
});

describe('textoPrazo', () => {
  it('singular, plural, hoje e vencido', () => {
    expect(textoPrazo(0)).toBe('vence hoje');
    expect(textoPrazo(1)).toBe('vence em 1 dia');
    expect(textoPrazo(12)).toBe('vence em 12 dias');
    expect(textoPrazo(-3)).toBe('vencido há 3 dias');
  });
});
