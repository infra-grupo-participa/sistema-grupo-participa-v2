import { describe, expect, it } from 'vitest';
import { chipsDeDimensao, filtrarPorDimensao } from './linha-do-tempo';

const itens = [
  { id: '1', dimensao: 'compras' },
  { id: '2', dimensao: 'eventos' },
  { id: '3', dimensao: 'compras' },
  { id: '4' },
];
const dims = [{ chave: 'compras', rotulo: 'Compras' }, { chave: 'eventos', rotulo: 'Eventos' }, { chave: 'grupos', rotulo: 'Grupos' }];

describe('chipsDeDimensao', () => {
  it('"Todas" primeiro com o total, depois cada dimensão na ordem dada, zero incluído', () => {
    expect(chipsDeDimensao(itens, dims)).toEqual([
      { chave: null, rotulo: 'Todas', total: 4 },
      { chave: 'compras', rotulo: 'Compras', total: 2 },
      { chave: 'eventos', rotulo: 'Eventos', total: 1 },
      { chave: 'grupos', rotulo: 'Grupos', total: 0 },
    ]);
  });
});

describe('filtrarPorDimensao', () => {
  it('null devolve tudo, na mesma ordem', () => {
    expect(filtrarPorDimensao(itens, null).map((i) => i.id)).toEqual(['1', '2', '3', '4']);
  });
  it('filtra pela dimensão e preserva a ordem', () => {
    expect(filtrarPorDimensao(itens, 'compras').map((i) => i.id)).toEqual(['1', '3']);
  });
  it('dimensão sem itens devolve vazio', () => {
    expect(filtrarPorDimensao(itens, 'grupos')).toEqual([]);
  });
});
