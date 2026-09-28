import { describe, expect, it } from 'vitest';
import { REPORTS } from './config';

describe('REPORTS — secao (título opcional acima do item na sidebar)', () => {
  it('grupo Financeiro: "Visão geral" (#visao) abre a seção Contas a Receber; "Previsão de caixa" (#receber) está nela', () => {
    const financeiro = REPORTS.find((g) => g.key === 'financeiro');
    expect(financeiro).toBeTruthy();
    expect(financeiro!.children[0]).toMatchObject({ key: 'visao', label: 'Visão geral', hash: '#visao', secao: 'Contas a Receber' });
    const comSecao = financeiro!.children.filter((c) => c.secao);
    expect(comSecao.map((c) => c.key)).toEqual(['visao', 'receber']);
    expect(new Set(comSecao.map((c) => c.secao))).toEqual(new Set(['Contas a Receber'])); // mesma seção: 1 título só
    const receber = comSecao[1];
    expect(receber.label).toBe('Previsão de caixa');
    expect(receber.hash).toBe('#receber'); // renomeou o rótulo, o hash não muda
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
