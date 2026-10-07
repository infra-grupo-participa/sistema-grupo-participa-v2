import { describe, expect, it } from 'vitest';
import { agrupar, aplicarFiltros, alternarFiltro } from './filtro-cruzado';

const linhas = [
  { comprou: true, instrucao: 'THB', turma: 'A', utm_source: null },
  { comprou: false, instrucao: 'THB', turma: 'B', utm_source: 'API' },
  { comprou: true, instrucao: null, turma: null, utm_source: 'API' },
];
describe('filtro cruzado', () => {
  it('combina campos e alterna uma seleção', () => {
    const filtros = alternarFiltro([{ campo: 'instrucao', valor: 'THB' }], 'comprou', 'true');
    expect(aplicarFiltros(linhas, filtros)).toEqual([linhas[0]]);
    expect(alternarFiltro(filtros, 'comprou', 'true')).toEqual([{ campo: 'instrucao', valor: 'THB' }]);
  });
  it('agrupa com os outros filtros e mantém nulo distinto de zero', () => {
    expect(agrupar(linhas, 'instrucao', [{ campo: 'comprou', valor: 'true' }])).toEqual([
      { valor: '__null__', rotulo: 'Sem registro de aluno ativo', quantidade: 1 },
      { valor: 'THB', rotulo: 'THB', quantidade: 1 },
    ]);
    expect(agrupar(linhas, 'utm_source', [])[1]).toEqual({ valor: '__null__', rotulo: 'Sem informação', quantidade: 1 });
  });
});
