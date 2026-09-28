import { describe, expect, it } from 'vitest';
import { REPORTS } from '../nav/config';
import { chaveHashPadrao, hashBase, itemHashAtivo } from './item-ativo';

const financeiro = REPORTS.find((g) => g.key === 'financeiro')!;
const ativos = (hash: string) =>
  financeiro.children.filter((c) => itemHashAtivo(c, hash, true, chaveHashPadrao(financeiro.defaultHref, financeiro.children)))
    .map((c) => c.key);

describe('sidebar — item hash-nav ativo', () => {
  it('sem hash, o ativo é o do defaultHref do grupo (#board), não o 1º filho com hash (#receber)', () => {
    expect(financeiro.children[0].hash).toBe('#receber'); // pré-condição: é exatamente o caso que errava
    expect(chaveHashPadrao(financeiro.defaultHref, financeiro.children)).toBe('board');
    expect(ativos('')).toEqual(['board']);
  });
  it('hash com ? (sub-aba ou filtro) acende o item da base, e só ele', () => {
    expect(ativos('#receber?ver=premissas')).toEqual(['receber']);
    expect(ativos('#board?produto=HM&canal=x')).toEqual(['board']);
    expect(ativos('#faturamento')).toEqual(['faturamento']);
  });
  it('fora da rota do filho: nunca ativo', () => {
    expect(itemHashAtivo({ key: 'board', hash: '#board' }, '#board', false, 'board')).toBe(false);
  });
  it('defaultHref sem hash: cai no 1º filho com hash (comportamento de antes)', () => {
    expect(chaveHashPadrao('/relatorios/x', [{ key: 'a' }, { key: 'b', hash: '#b' }, { key: 'c', hash: '#c' }])).toBe('b');
  });
  it('hashBase', () => {
    expect(hashBase('#receber?ver=premissas')).toBe('#receber');
    expect(hashBase('')).toBe('');
  });
});
