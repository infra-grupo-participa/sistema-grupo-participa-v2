import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { HistoricoAtmView } from './HistoricoAtm';
import type { EdicaoHistorico } from '../domain/historico';

const edicoes: EdicaoHistorico[] = [
  {
    chave: 'atm-jul', familia: 'seminario-atm', rotulo: 'ATM JUL/26', ordem: 1, dataInicio: null, dataFim: null,
    leads: 424, investTrafego: 0, investDisparo: 2039.93, grupo: 345, picoD1: 74, picoD2: 21, picoD3: null,
    vendas: 7, receitaLiquida: 9919.07, preCheckout: 26,
    fontes: { leads: 'fixture teste', vendas: 'fixture teste' }, provisorio: [],
  },
  {
    chave: 'atm-set', familia: 'seminario-atm', rotulo: 'ATM SET/26', ordem: 2, dataInicio: '2026-09-01', dataFim: '2026-09-03',
    leads: 911, investTrafego: 0, investDisparo: 2119.48, grupo: 743, picoD1: 127, picoD2: 62, picoD3: 40,
    vendas: 9, receitaLiquida: 12752.91, preCheckout: 33,
    fontes: { pico_d1: 'fixture teste', vendas: 'fixture teste' }, provisorio: ['vendas'],
  },
];

function render(edicoesDaTela = edicoes) {
  return renderToStaticMarkup(createElement(HistoricoAtmView, {
    edicoes: edicoesDaTela, carregando: false, erro: null, lidoEm: new Date('2026-10-09T15:00:00-03:00'), onRecarregar: () => {},
  }));
}

describe('visual do comparativo do histórico ATM', () => {
  it('mostra os dez cards, destaca a edição mais recente e inclui o funil', () => {
    const html = render();
    for (const rotulo of ['Leads', 'Ingressos no grupo', 'Taxa de ingresso no grupo', 'Pico ao vivo dia 1', 'Pré-checkout', 'Vendas', 'Receita líquida', 'CAC', 'ROAS', 'CPL']) {
      expect(html).toContain(rotulo);
    }
    expect(html).toContain('ATM SET/26 · mais recente');
    expect(html).toContain('Funil comparativo');
    expect(html).toContain('Tabela completa do comparativo');
    expect(html).toContain('(provisório)');
  });

  it('mantém a ausência como travessão no funil e não como zero', () => {
    const semPico = [{ ...edicoes[1], picoD1: null }];
    const html = render(semPico);
    expect(html).toContain('—');
    expect(html).not.toContain('Pico na live (dia 1)</span><span class="shrink-0 font-semibold tabular text-[var(--fg)]">0');
  });
});
