import { describe, expect, it, vi } from 'vitest';
import { carregarTaxaHotmart, criarCacheTaxaHotmart } from './carregar-taxa-hotmart';
import type { DivergenciaTaxa } from '../domain/taxa-hotmart';

const linha = (div: number) => ({ tipo: 'a_vista', produto_id: 'p', produto_nome: 'HM', n_vendas: 3, n_divergentes: div,
  impacto_divergentes_rs: div ? '20' : '0' });
const repo = (div: number) => ({
  loadTaxaAuditoria: vi.fn(async (): Promise<Record<string, unknown>[]> => [linha(div)]),
  loadTaxaDivergencias: vi.fn(async (): Promise<DivergenciaTaxa[]> => [{ transacao: 'HP1', dia: '2026-01-02',
    produtoId: 'p', produtoNome: 'HM', valorOferta: 1000, taxaReal: 70, taxaEsperada: 54, diferenca: 16 }]),
});

describe('carregarTaxaHotmart', () => {
  it('0 divergente: 1 chamada só (a lista nem é pedida)', async () => {
    const r = repo(0);
    const d = await carregarTaxaHotmart(r, '2026-01-01', '2026-09-28');
    expect(r.loadTaxaAuditoria).toHaveBeenCalledWith('2026-01-01', '2026-09-28');
    expect(r.loadTaxaDivergencias).not.toHaveBeenCalled();
    expect(d.divergencias).toEqual([]);
  });
  it('com divergente: 2 chamadas', async () => {
    const r = repo(1);
    const d = await carregarTaxaHotmart(r, '2026-01-01', '2026-09-28');
    expect(r.loadTaxaDivergencias).toHaveBeenCalledWith('2026-01-01', '2026-09-28');
    expect(d.divergencias).toHaveLength(1);
  });
});

describe('criarCacheTaxaHotmart', () => {
  it('mesmo período: 0 chamada na 2ª vez; simultâneos dividem a promessa; outro período consulta', async () => {
    const r = repo(1);
    const c = criarCacheTaxaHotmart(r);
    expect(c.lido('2026-01-01', '2026-09-28')).toBeUndefined();
    await Promise.all([c.obter('2026-01-01', '2026-09-28'), c.obter('2026-01-01', '2026-09-28')]);
    await c.obter('2026-01-01', '2026-09-28');
    expect(r.loadTaxaAuditoria).toHaveBeenCalledTimes(1);
    expect(r.loadTaxaDivergencias).toHaveBeenCalledTimes(1);
    expect(c.lido('2026-01-01', '2026-09-28')?.divergencias).toHaveLength(1);
    await c.obter('2025-09-29', '2026-09-28');
    expect(r.loadTaxaAuditoria).toHaveBeenCalledTimes(2);
  });
  it('falha não fica guardada', async () => {
    const r = repo(0);
    r.loadTaxaAuditoria.mockRejectedValueOnce(new Error('rede'));
    const c = criarCacheTaxaHotmart(r);
    await expect(c.obter('2026-01-01', '2026-09-28')).rejects.toThrow('rede');
    expect(c.lido('2026-01-01', '2026-09-28')).toBeUndefined();
    await c.obter('2026-01-01', '2026-09-28');
    expect(r.loadTaxaAuditoria).toHaveBeenCalledTimes(2);
  });
});
