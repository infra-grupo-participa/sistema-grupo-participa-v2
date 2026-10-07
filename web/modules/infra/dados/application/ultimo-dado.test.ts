import { describe, expect, it } from 'vitest';
import { manterUltimoDado } from './ultimo-dado';

describe('manterUltimoDado', () => {
  it('preserva o último resultado em falha de leitura', () => {
    expect(manterUltimoDado({ data: { vendas: 3 }, erro: null }, { data: null, erro: 'Sem acesso' }))
      .toEqual({ data: { vendas: 3 }, erro: 'Sem acesso' });
  });

  it('aceita uma lista vazia válida e não a troca pelo resultado anterior', () => {
    expect(manterUltimoDado({ data: [1], erro: null }, { data: [], erro: null }))
      .toEqual({ data: [], erro: null });
  });

  it('mantém ausência de dado como ausência, sem fabricar zero', () => {
    expect(manterUltimoDado(null, { data: null, erro: 'Falha' }))
      .toEqual({ data: null, erro: 'Falha' });
  });
});
