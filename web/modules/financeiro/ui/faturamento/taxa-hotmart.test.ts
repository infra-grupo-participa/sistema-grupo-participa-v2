// Faturamento · Taxa Hotmart em HTML estático (sem navegador): conteúdo, rótulos, resumo nos dois casos e papéis ARIA.
// Clique, foco, teclado, download do CSV e geometria não se provam aqui.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { TaxaHotmart, periodoInicialTaxa, type PeriodoTaxa } from './TaxaHotmart';
import { FaturamentoDiario } from '../FaturamentoDiario';
import type { CacheTaxaHotmart, TaxaHotmartCarregada } from '../../application/carregar-taxa-hotmart';
import { montarAuditoriaTaxa, normalizarDivergencia } from '../../domain/taxa-hotmart';
import type { CacheCaixaHotmart } from '../../application/carregar-caixa-hotmart';
import type { FinanceiroRepository } from '../../application/ports';

const hm = { tipo: 'a_vista', produto_id: 'hm', produto_nome: 'Holding Masters', grupo_acordo: '4% + R$ 1,00',
  sem_acordo_especifico: false, n_vendas: 1200, n_sem_taxa: 0, valor_oferta: '9000000', taxa_real_rs: '362430',
  taxa_esperada_rs: '361200', taxa_real_pct: '4.027', taxa_esperada_pct: '4.013', n_divergentes: 0,
  impacto_rs: '0', impacto_divergentes_rs: '0' };
const imersao = { ...hm, produto_id: 'im', produto_nome: 'Imersão Holding sem Improviso', grupo_acordo: '5,3% + R$ 1,00',
  sem_acordo_especifico: true, n_vendas: 40, n_sem_taxa: 2, valor_oferta: '80000', taxa_real_pct: '5.400',
  taxa_esperada_pct: '5.350' };
const parcelas = Array.from({ length: 12 }, (_, i) => ({ tipo: 'parcelado', parcelas: i + 1, n_vendas: i === 11 ? 0 : 10,
  n_sem_taxa: 0, valor_oferta: i === 11 ? '0' : '10000', taxa_cliente_pct: i === 11 ? null : String(5.1 + i * 1.8) }));

const carregado = (divergente: boolean): TaxaHotmartCarregada => {
  const auditoria = montarAuditoriaTaxa([
    divergente ? { ...hm, n_divergentes: 3, impacto_divergentes_rs: '48.50' } : hm, imersao, ...parcelas,
  ]);
  return {
    de: '2026-01-01', ate: '2026-09-28', auditoria,
    divergencias: divergente ? [normalizarDivergencia({ transacao: 'HP0123456789', dia: '2026-03-02', produto_id: 'hm',
      produto_nome: 'Holding Masters', valor_oferta: '1000', taxa_real: '70', taxa_esperada: '41', diferenca: '29' })] : [],
  };
};
const cacheCom = (d: TaxaHotmartCarregada | undefined): CacheTaxaHotmart => ({
  lido: () => d, obter: vi.fn(() => new Promise<TaxaHotmartCarregada>(() => {})),
});
const render = (periodo: PeriodoTaxa, cache: CacheTaxaHotmart) =>
  renderToStaticMarkup(createElement(TaxaHotmart, { cache, periodo, onPeriodo: () => {}, hojeISO: '2026-09-28' }));
const padrao = periodoInicialTaxa('2026-09-28');

describe('TaxaHotmart', () => {
  it('período padrão = ano corrente, preset marcado', () => {
    expect(padrao).toEqual({ de: '2026-01-01', ate: '2026-09-28', preset: 'ano' });
    const h = render(padrao, cacheCom(carregado(false)));
    expect(h).toMatch(/aria-pressed="true"[^>]*>Ano de 2026</);
    expect(h).toContain('A Hotmart está cobrando o que combinou?');
  });
  it('0 divergente: frase do combinado, sem lista e sem botão de exportar', () => {
    const h = render(padrao, cacheCom(carregado(false)));
    expect(h).toContain('1.240 vendas à vista');
    expect(h).toContain('A Hotmart cobrou o combinado em todas as vendas do período.');
    expect(h).not.toContain('Vendas divergentes');
    expect(h).not.toContain('Exportar CSV');
  });
  it('com divergente: N divergentes e impacto no resumo; lista com transação, diferença e exportar', () => {
    const h = render(padrao, cacheCom(carregado(true)));
    expect(h).toMatch(/3 divergentes, impacto R\$\s48,50 cobrado a mais\./);
    expect(h).not.toContain('cobrou o combinado');
    expect(h).toContain('HP0123456789');
    expect(h).toMatch(/\+R\$\s29,00/);
    expect(h).toContain('>Exportar CSV<');
    expect(h).toContain('<caption class="sr-only">Vendas à vista com taxa diferente do acordo, maior diferença primeiro</caption>');
  });
  it('tabela por produto: acordo, real × acordo em %, "sem acordo específico" em texto, vendas sem taxa', () => {
    const h = render(padrao, cacheCom(carregado(false)));
    expect(h).toContain('<caption class="sr-only">Taxa Hotmart à vista por produto: real × acordo</caption>');
    expect(h).toContain('4% + R$ 1,00');
    expect(h).toContain('4,03%');
    expect(h).toContain('4,01%');
    expect(h).toContain('· sem acordo específico');
    expect(h).toContain('+ 2 sem taxa');
    expect(h).toContain('2 vendas vieram sem a taxa informada');
    expect(h).toContain('1 produto não tem acordo específico');
    expect(h.indexOf('Holding Masters')).toBeLessThan(h.indexOf('Imersão Holding'));
  });
  it('parcelado: 12 linhas, 1× referência, explica que o líquido da empresa não muda; parcela sem venda = —', () => {
    const h = render(padrao, cacheCom(carregado(false)));
    expect(h).toContain('Parcelado: quanto o cliente paga a mais por nº de parcelas');
    expect(h).toContain('A empresa recebe o mesmo líquido da venda à vista');
    expect(h).toContain('1× (referência)');
    expect(h).toContain('>11×<');
    expect(h).toContain('>12×<');
    expect(h).toContain('5,1%');
    expect(h).toMatch(/\+18,0 p\.p\./); // 11× − 1×
  });
  it('sem venda à vista: frase própria', () => {
    const vazio: TaxaHotmartCarregada = { de: '2026-01-01', ate: '2026-09-28', auditoria: montarAuditoriaTaxa(parcelas), divergencias: [] };
    expect(render(padrao, cacheCom(vazio))).toContain('Nenhuma venda à vista com oferta a partir de R$ 100 no período.');
  });
  it('período acima de 400 dias: mensagem e nenhuma consulta', () => {
    const cache = cacheCom(undefined);
    const h = render({ de: '2025-01-01', ate: '2026-09-28', preset: null }, cache);
    expect(h).toContain('role="alert"');
    expect(h).toContain('até 400 dias');
    expect(cache.obter).not.toHaveBeenCalled();
  });
  it('sem dado ainda: carregando (nunca resumo vazio)', () => {
    const h = render(padrao, cacheCom(undefined));
    expect(h).toContain('Carregando a auditoria da taxa Hotmart');
    expect(h).not.toContain('cobrou o combinado');
  });
  it('datas com rótulo acessível', () => {
    const h = render(padrao, cacheCom(carregado(false)));
    expect(h).toContain('aria-label="Data inicial"');
    expect(h).toContain('aria-label="Data final"');
  });
});

describe('FaturamentoDiario — sub-aba Taxa Hotmart', () => {
  const repo = { loadHotmartSync: () => new Promise(() => {}) } as unknown as FinanceiroRepository;
  const cacheCaixa: CacheCaixaHotmart = { lido: () => undefined, obter: vi.fn(() => new Promise<never>(() => {})) };
  it('3 abas; Taxa Hotmart ativa aponta o painel', () => {
    const h = renderToStaticMarkup(createElement(FaturamentoDiario, {
      repo, sub: 'taxa', onSubChange: () => {}, cacheCaixa,
      periodoCaixa: { de: '2026-06-01', ate: '2026-09-28', preset: 'marco' }, onPeriodoCaixa: () => {},
      cacheTaxa: cacheCom(carregado(false)), periodoTaxa: padrao, onPeriodoTaxa: () => {},
    }));
    expect(h).toContain('>Por período<');
    expect(h).toContain('>Caixa Hotmart<');
    expect(h).toMatch(/id="faturamento-tab-taxa"[^>]*aria-selected="true"/);
    expect(h).toContain('role="tabpanel" id="faturamento-painel-taxa" aria-labelledby="faturamento-tab-taxa"');
    expect(h).toContain('cobrou o combinado');
    expect(cacheCaixa.obter).not.toHaveBeenCalled();
  });
});
