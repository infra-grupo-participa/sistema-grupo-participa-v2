import { describe, expect, it } from 'vitest';
import { placaCicloLabel, placaLembreteLabel, placaParadoInfo } from './placa-funil';

describe('placaParadoInfo', () => {
  it('null/inválido não renderiza', () => {
    expect(placaParadoInfo(null)).toBeNull();
    expect(placaParadoInfo(undefined)).toBeNull();
    expect(placaParadoInfo(-1)).toBeNull();
    expect(placaParadoInfo(NaN)).toBeNull();
  });
  it('alerta só a partir de 3 dias', () => {
    expect(placaParadoInfo(0)).toEqual({ label: 'Parado desde hoje', alerta: false });
    expect(placaParadoInfo(1)).toEqual({ label: 'Parado há 1 dia', alerta: false });
    expect(placaParadoInfo(2)?.alerta).toBe(false);
    expect(placaParadoInfo(3)).toEqual({ label: 'Parado há 3 dias', alerta: true });
  });
});

describe('placaCicloLabel', () => {
  it('só ciclo > 1', () => {
    expect(placaCicloLabel(null)).toBeNull();
    expect(placaCicloLabel(1)).toBeNull();
    expect(placaCicloLabel(2)).toBe('Ciclo 2');
  });
});

describe('placaLembreteLabel', () => {
  it('formata dd/mm hh:mm e rejeita inválido', () => {
    expect(placaLembreteLabel(null)).toBeNull();
    expect(placaLembreteLabel('lixo')).toBeNull();
    expect(placaLembreteLabel('2026-10-05T15:30:00')).toBe('05/10 15:30');
  });
});
