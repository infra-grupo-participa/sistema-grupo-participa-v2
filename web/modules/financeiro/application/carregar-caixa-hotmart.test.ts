import { describe, expect, it, vi } from 'vitest';
import { criarCacheCaixaHotmart } from './carregar-caixa-hotmart';
import { normalizarLinhaCaixa, normalizarTotaisCaixa } from '../domain/caixa-hotmart';

const linha = normalizarLinhaCaixa({ dia: '2026-09-01', liquido: 100, entra_rapido: 86.5, entra_em: '2026-09-03',
  libera_em: '2026-10-01', situacao_d2: 'recebido', situacao_retido: 'em_garantia', retido: 10, retido_a_liberar: 10, n_vendas: 1 });
const totais = normalizarTotaisCaixa({ liquido: 100, retido: 10, retido_a_liberar: 10, n_vendas: 1 });

function repoFalso() {
  return {
    loadCaixaHotmart: vi.fn().mockResolvedValue([linha]),
    loadCaixaHotmartTotais: vi.fn().mockResolvedValue(totais),
  };
}

describe('cache do Caixa Hotmart', () => {
  it('1ª vez: 2 chamadas (linhas + totais) com o período; mesmo período de novo: 0 chamadas', async () => {
    const repo = repoFalso();
    const cache = criarCacheCaixaHotmart(repo);
    expect(cache.lido('2026-06-01', '2026-09-28')).toBeUndefined();
    const r = await cache.obter('2026-06-01', '2026-09-28');
    expect(repo.loadCaixaHotmart).toHaveBeenCalledWith('2026-06-01', '2026-09-28');
    expect(repo.loadCaixaHotmartTotais).toHaveBeenCalledWith('2026-06-01', '2026-09-28');
    expect(r.derivado.jaCaiuD2).toBe(86.5);
    await cache.obter('2026-06-01', '2026-09-28');
    expect(cache.lido('2026-06-01', '2026-09-28')).toBe(r);
    expect(repo.loadCaixaHotmart).toHaveBeenCalledTimes(1);
    expect(repo.loadCaixaHotmartTotais).toHaveBeenCalledTimes(1);
  });
  it('pedidos simultâneos do mesmo período dividem a mesma consulta (StrictMode)', async () => {
    const repo = repoFalso();
    const cache = criarCacheCaixaHotmart(repo);
    await Promise.all([cache.obter('2026-09-01', '2026-09-28'), cache.obter('2026-09-01', '2026-09-28')]);
    expect(repo.loadCaixaHotmart).toHaveBeenCalledTimes(1);
  });
  it('outro período consulta de novo', async () => {
    const repo = repoFalso();
    const cache = criarCacheCaixaHotmart(repo);
    await cache.obter('2026-09-01', '2026-09-28');
    await cache.obter('2026-08-30', '2026-09-28');
    expect(repo.loadCaixaHotmart).toHaveBeenCalledTimes(2);
  });
  it('falha não fica guardada: a próxima tentativa consulta', async () => {
    const repo = repoFalso();
    repo.loadCaixaHotmartTotais.mockRejectedValueOnce(new Error('Sem permissão para ver o financeiro.'));
    const cache = criarCacheCaixaHotmart(repo);
    await expect(cache.obter('2026-06-01', '2026-09-28')).rejects.toThrow('Sem permissão');
    expect(cache.lido('2026-06-01', '2026-09-28')).toBeUndefined();
    await cache.obter('2026-06-01', '2026-09-28');
    expect(repo.loadCaixaHotmartTotais).toHaveBeenCalledTimes(2);
  });
});
