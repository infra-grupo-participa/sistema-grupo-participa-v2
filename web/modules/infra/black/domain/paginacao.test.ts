import { describe, expect, it } from 'vitest';
import { paginar, paginasVisiveis } from './paginacao';

const lista = Array.from({ length: 23 }, (_, i) => i + 1);

describe('paginação dos cartões', () => {
  it('10 por página: 23 itens viram 3 páginas e a última tem 3', () => {
    expect(paginar(lista, 1)).toMatchObject({ pagina: 1, paginas: 3, total: 23, itens: lista.slice(0, 10) });
    expect(paginar(lista, 3).itens).toEqual([21, 22, 23]);
  });
  it('página fora do intervalo cai na mais próxima válida, nunca vazia', () => {
    expect(paginar(lista, 9).pagina).toBe(3);
    expect(paginar(lista, 0).pagina).toBe(1);
    expect(paginar(lista, Number.NaN).pagina).toBe(1);
  });
  it('lista vazia = 1 página sem itens', () => {
    expect(paginar([], 1)).toEqual({ itens: [], pagina: 1, paginas: 1, total: 0 });
  });
  it('régua estilo Google: janela de 5 com a atual no meio quando dá', () => {
    expect(paginasVisiveis(1, 3)).toEqual([1, 2, 3]);
    expect(paginasVisiveis(1, 12)).toEqual([1, 2, 3, 4, 5]);
    expect(paginasVisiveis(6, 12)).toEqual([4, 5, 6, 7, 8]);
    expect(paginasVisiveis(12, 12)).toEqual([8, 9, 10, 11, 12]);
  });
});
