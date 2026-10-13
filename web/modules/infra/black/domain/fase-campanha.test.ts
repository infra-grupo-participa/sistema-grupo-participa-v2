import { describe, expect, it } from 'vitest';
import { faseDoNome } from './fase-campanha';

describe('faseDoNome', () => {
  it('antecipação pelo bloco do nome, com acento', () => {
    expect(faseDoNome('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY')).toBe('antecipacao');
  });
  it('aquecimento', () => {
    expect(faseDoNome('CF | BF26 | AQUECIMENTO | MANIFESTO | META | PQ | ABO | THRUPLAY')).toBe('aquecimento');
  });
  it('LEAD e LEADS são captação', () => {
    expect(faseDoNome('BF26 | CPF01 | META | IG | MORNO | ABO | LEAD')).toBe('captacao');
    expect(faseDoNome('X | C3 | LEADS | META')).toBe('captacao');
  });
  it('ignora caixa e espaço', () => {
    expect(faseDoNome('bf26|antecipacao |teaser')).toBe('antecipacao');
  });
  it('sem bloco de fase fica sem fase', () => {
    expect(faseDoNome('BF26 | CPF01 | META')).toBeNull();
    expect(faseDoNome(null)).toBeNull();
    expect(faseDoNome('')).toBeNull();
  });
  it('não casa pedaço de palavra', () => {
    expect(faseDoNome('BF26 | LEADERSHIP | META')).toBeNull();
  });
  it('fases diferentes no mesmo nome: sem fase', () => {
    expect(faseDoNome('BF26 | ANTECIPAÇÃO | LEAD')).toBeNull();
  });
});
