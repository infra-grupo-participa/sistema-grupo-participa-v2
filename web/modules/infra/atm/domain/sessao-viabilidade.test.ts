import { describe, expect, it } from 'vitest';
import { conversaoSessaoViabilidade } from './sessao-viabilidade';

describe('conversaoSessaoViabilidade', () => {
  it('calcula vendas divididas por pré-checkouts únicos', () => {
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, 12)).toEqual({ valor: 25, semDado: false });
  });

  it('mantém sem dado quando vendas ou pré-checkouts não foram carregados', () => {
    expect(conversaoSessaoViabilidade({ valor: 0, semDado: true }, 12)).toEqual({ valor: 0, semDado: true });
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, null)).toEqual({ valor: 0, semDado: true });
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, 0)).toEqual({ valor: 0, semDado: true });
  });
});
