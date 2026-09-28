// Faturamento · Caixa Hotmart em HTML estático (sem navegador): conteúdo, rótulos, aviso do marco e papéis ARIA.
// Clique, foco, teclado e geometria não se provam aqui.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { CaixaHotmart, periodoInicialCaixa, type PeriodoCaixa } from './CaixaHotmart';
import { FaturamentoDiario } from '../FaturamentoDiario';
import type { CacheCaixaHotmart, CaixaHotmartCarregado } from '../../application/carregar-caixa-hotmart';
import { derivarCaixa, normalizarLinhaCaixa, normalizarTotaisCaixa } from '../../domain/caixa-hotmart';
import type { FinanceiroRepository } from '../../application/ports';

const linhas = [
  // antes do marco: sem antecipação, tudo retido
  normalizarLinhaCaixa({ dia: '2026-05-20', liquido: 1000, retido: 1000, custo_antecipacao: 0, entra_rapido: 0,
    entra_em: '2026-05-22', retido_a_liberar: 0, libera_em: '2026-06-19', situacao_d2: 'recebido', situacao_retido: 'liberado', n_vendas: 2 }),
  normalizarLinhaCaixa({ dia: '2026-09-01', liquido: 93.7, retido: 9.37, custo_antecipacao: 3.28, entra_rapido: 81.05,
    entra_em: '2026-09-03', retido_a_liberar: 9.37, libera_em: '2026-10-01', situacao_d2: 'recebido', situacao_retido: 'em_garantia', n_vendas: 1 }),
  normalizarLinhaCaixa({ dia: '2026-09-28', liquido: 200, retido: 20, custo_antecipacao: 7, entra_rapido: 173,
    entra_em: '2026-09-30', retido_a_liberar: 20, libera_em: '2026-10-28', situacao_d2: 'a_receber', situacao_retido: 'em_garantia', n_vendas: 3 }),
];
const totais = normalizarTotaisCaixa({ liquido: 1293.7, retido: 1029.37, custo_antecipacao: 10.28, entra_rapido: 254.05,
  retido_a_liberar: 29.37, liquido_total: 1283.42, n_vendas: 6 });
const carregado: CaixaHotmartCarregado = { de: '2026-05-01', ate: '2026-09-28', linhas, totais, derivado: derivarCaixa(linhas, totais) };

const cacheCom = (d: CaixaHotmartCarregado | undefined): CacheCaixaHotmart => ({
  lido: () => d, obter: vi.fn(() => new Promise<CaixaHotmartCarregado>(() => {})),
});
const render = (periodo: PeriodoCaixa, cache = cacheCom(carregado)) =>
  renderToStaticMarkup(createElement(CaixaHotmart, { cache, periodo, onPeriodo: () => {}, hojeISO: '2026-09-28' }));

describe('CaixaHotmart', () => {
  const html = render({ de: '2026-05-01', ate: '2026-09-28', preset: null });

  it('faixa de totais: Líquido · Já caiu em D+2 · Custo da antecipação · Retido a liberar · Líquido total', () => {
    const ordem = ['Líquido', 'Já caiu em D+2', 'Custo da antecipação', 'Retido a liberar', 'Líquido total']
      .map((r) => html.indexOf(`>${r}</dt>`));
    expect(ordem.every((i) => i >= 0)).toBe(true);
    expect([...ordem].sort((a, b) => a - b)).toEqual(ordem);
    expect(html).toContain('aria-label="Totais do período"');
    expect(html).toContain('6 vendas');
  });
  it('já caiu = só o D+2 recebido; o resto aparece como "a cair"; já liberado sob o retido', () => {
    expect(html).toMatch(/Já caiu em D\+2<\/dt><dd[^>]*>R\$\s81<\/dd>/);
    expect(html).toMatch(/mais R\$\s173 a cair/);
    expect(html).toMatch(/R\$\s1\.000 já liberado/);
  });
  it('tabela por dia, mais recente primeiro, com situação em texto (nunca só cor)', () => {
    expect(html).toContain('<caption class="sr-only">Caixa Hotmart por dia de aprovação</caption>');
    expect(html.indexOf('28/09/2026')).toBeLessThan(html.indexOf('01/09/2026'));
    expect(html).toContain('>A receber<');
    expect(html).toContain('>Recebido<');
    expect(html).toContain('>A liberar<');
    expect(html).toContain('>Liberado<');
  });
  it('dia antes do marco: "sem antecipação" no D+2, e o aviso do marco aparece', () => {
    expect(html).toContain('sem antecipação');
    expect(html).toContain('role="note"');
    expect(html).toContain('Antes de 01/06/2026 não havia antecipação');
  });
  it('período desde 01/06/2026: sem aviso do marco', () => {
    const h = render(periodoInicialCaixa('2026-09-28'));
    expect(h).not.toContain('não havia antecipação');
    expect(h).toContain('aria-pressed="true"');
    expect(h).toContain('Desde 01/06/2026');
  });
  it('período acima de 400 dias: mensagem e nenhuma consulta', () => {
    const cache = cacheCom(undefined);
    const h = render({ de: '2025-01-01', ate: '2026-09-28', preset: null }, cache);
    expect(h).toContain('role="alert"');
    expect(h).toContain('até 400 dias');
    expect(h).not.toContain('Carregando o caixa');
    expect(cache.obter).not.toHaveBeenCalled();
  });
  it('sem dado ainda: carregando (nunca tabela vazia)', () => {
    const h = render({ de: '2026-06-01', ate: '2026-09-28', preset: 'marco' }, cacheCom(undefined));
    expect(h).toContain('Carregando o caixa da Hotmart');
    expect(h).not.toContain('Nenhuma venda paga');
  });
  it('datas com rótulo acessível', () => {
    expect(html).toContain('aria-label="Data inicial"');
    expect(html).toContain('aria-label="Data final"');
  });
});

describe('FaturamentoDiario — sub-abas', () => {
  const repo = { loadHotmartSync: () => new Promise(() => {}) } as unknown as FinanceiroRepository;
  const base = { repo, onSubChange: () => {}, cacheCaixa: cacheCom(carregado),
    periodoCaixa: { de: '2026-05-01', ate: '2026-09-28', preset: null } as PeriodoCaixa, onPeriodoCaixa: () => {} };
  it('tablist com Por período e Caixa Hotmart; o painel aponta para a aba ativa', () => {
    const h = renderToStaticMarkup(createElement(FaturamentoDiario, { ...base, sub: 'caixa' }));
    expect(h).toContain('role="tablist"');
    expect(h).toContain('>Por período<');
    expect(h).toMatch(/id="faturamento-tab-caixa"[^>]*aria-selected="true"/);
    expect(h).toContain('role="tabpanel" id="faturamento-painel-caixa" aria-labelledby="faturamento-tab-caixa"');
    expect(h).toContain('Já caiu em D+2');
    expect(h).not.toContain('Holding Masters'); // seletor de família é só de Por período
  });
  it('Por período: seletor de família, sem os totais do caixa', () => {
    const h = renderToStaticMarkup(createElement(FaturamentoDiario, { ...base, sub: 'periodo' }));
    expect(h).toMatch(/id="faturamento-tab-periodo"[^>]*aria-selected="true"/);
    expect(h).not.toContain('Já caiu em D+2');
  });
});
