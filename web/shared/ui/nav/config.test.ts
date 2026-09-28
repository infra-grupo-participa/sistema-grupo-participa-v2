import { describe, expect, it } from 'vitest';
import { REPORTS } from './config';

describe('REPORTS — secao (título opcional acima do item na sidebar)', () => {
  it('grupo Financeiro: só o item "Previsão de caixa" (#receber) declara secao', () => {
    const financeiro = REPORTS.find((g) => g.key === 'financeiro');
    expect(financeiro).toBeTruthy();
    const comSecao = financeiro!.children.filter((c) => c.secao);
    expect(comSecao).toHaveLength(1);
    expect(comSecao[0].key).toBe('receber');
    expect(comSecao[0].secao).toBe('Contas a Receber');
    expect(comSecao[0].label).toBe('Previsão de caixa');
    expect(comSecao[0].hash).toBe('#receber'); // renomeou o rótulo, o hash não muda
  });

  it('defaultHref do Financeiro continua #board', () => {
    const financeiro = REPORTS.find((g) => g.key === 'financeiro');
    expect(financeiro!.defaultHref).toBe('/relatorios/financeiro#board');
  });

  it('outros grupos: nenhum item usa secao (layout deles não muda)', () => {
    for (const g of REPORTS) {
      if (g.key === 'financeiro') continue;
      for (const c of g.children) expect(c.secao).toBeUndefined();
    }
  });
});
