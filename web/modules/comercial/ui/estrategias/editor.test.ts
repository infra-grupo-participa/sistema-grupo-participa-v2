import { describe, expect, it } from 'vitest';
import { comRegra, contarFiltros, textoDeTrechos, trechosDeTexto } from './editor';

describe('editor de público', () => {
  it('trechos: vírgula ou ponto e vírgula, sem vazio e sem repetido (ignora caixa)', () => {
    expect(trechosDeTexto(' fazer a minha, Própria holding;  ; própria HOLDING ')).toEqual(['fazer a minha', 'Própria holding']);
    expect(textoDeTrechos(['a', 'b'])).toBe('a, b');
  });
  it('regras: acrescenta, troca e remove sem mexer no resto', () => {
    const r = { perguntas: ['P'], contem: ['abc'] };
    const f1 = comRegra({ base: 'alunos' }, 0, r);
    expect(f1).toEqual({ base: 'alunos', respondi: { regras: [r] } });
    const f2 = comRegra(f1, 0, { ...r, contem: ['xyz'] });
    expect(f2.respondi?.regras[0].contem).toEqual(['xyz']);
    expect(comRegra(f2, 0, null).respondi?.regras).toEqual([]);
  });
  it('conta cada filtro ativo uma vez e cada regra de pesquisa', () => {
    expect(contarFiltros({})).toBe(0);
    expect(contarFiltros({ alunos: { niveis: ['ouro'], tiposTurma: ['thb'] }, comprou: { linhas: ['hm'], produtos: ['1'] },
      respondi: { regras: [{ perguntas: ['p'], contem: ['abc'] }, { perguntas: ['q'], contem: ['def'] }] } })).toBe(5);
  });
});
