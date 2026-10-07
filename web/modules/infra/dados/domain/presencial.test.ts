import { describe, expect, it } from 'vitest';
import { normalizarNumericos, numero } from './presencial';

describe('numeric do PostgREST', () => {
  it('converte strings e preserva nulo', () => {
    expect(normalizarNumericos({ receita_liquida: '5212.40', cac_centavos: null }, ['receita_liquida', 'cac_centavos'])).toEqual({ receita_liquida: 5212.4, cac_centavos: null });
    expect(numero(null)).toBeNull();
    expect(numero('')).toBeNull();
    expect(numero(0)).toBe(0);
  });
});
