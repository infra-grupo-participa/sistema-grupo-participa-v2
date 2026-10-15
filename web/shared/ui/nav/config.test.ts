import { describe, expect, it } from 'vitest';
import { NAV_FINANCEIRO, REPORTS } from './config';

describe('NAV_FINANCEIRO — menu do departamento Financeiro (15/10/2026: saiu do Educacional)', () => {
  it('"Visão geral" (#visao) abre a seção Contas a Receber; "Previsão de caixa" (#receber) está nela', () => {
    const financeiro = NAV_FINANCEIRO;
    expect(financeiro.children[0]).toMatchObject({ key: 'visao', label: 'Visão geral', hash: '#visao', secao: 'Contas a Receber' });
    const comSecao = financeiro.children.filter((c) => c.secao);
    expect(comSecao.map((c) => c.key)).toEqual(['visao', 'receber']);
    expect(new Set(comSecao.map((c) => c.secao))).toEqual(new Set(['Contas a Receber'])); // mesma seção: 1 título só
    const receber = comSecao[1];
    expect(receber.label).toBe('Previsão de caixa');
    expect(receber.hash).toBe('#receber'); // renomeou o rótulo, o hash não muda
  });

  it('defaultHref continua #board, agora em /financeiro', () => {
    expect(NAV_FINANCEIRO.defaultHref).toBe('/financeiro#board');
  });

  it('mesmos itens, hashes e ícones de antes; tudo em /financeiro', () => {
    expect(NAV_FINANCEIRO.children.map((c) => [c.key, c.label, c.hash, c.ico])).toEqual([
      ['visao', 'Visão geral', '#visao', 'eye'],
      ['receber', 'Previsão de caixa', '#receber', 'receipt'],
      ['faturamento', 'Faturamento', '#faturamento', 'trending-up'],
      ['board', 'Board', '#board', 'dashboard'],
      ['funis', 'Funis', '#funis', 'trending-up'],
      ['escritorio', 'Escritório', '#escritorio', 'trending-up'],
      ['ofertas', 'Ofertas', '#ofertas', 'banknote'],
      ['relatorios', 'Relatórios', '#relatorios', 'file'],
    ]);
    for (const c of NAV_FINANCEIRO.children) {
      expect(c.path).toBe('/financeiro');
      expect(c.href).toBe(`/financeiro${c.hash}`);
    }
  });

  it('o menu do Educacional não tem mais o Financeiro', () => {
    expect(REPORTS.some((g) => g.key === 'financeiro' || g.setor === 'financeiro')).toBe(false);
    for (const g of REPORTS) expect(g.path.startsWith('/educacional/'), g.path).toBe(true);
  });

  it('grupos do Educacional: nenhum item usa secao (layout deles não muda)', () => {
    for (const g of REPORTS) {
      for (const c of g.children) expect(c.secao).toBeUndefined();
    }
  });
});
