import { describe, expect, it, vi } from 'vitest';
import { criarCacheEscritorioFunil, totalizarFunilEscritorio } from './carregar-escritorio-funil';
import type { LinhaFunilEscritorio, PessoaFunilEscritorio } from '../domain/escritorio-funil';

const linha = (p: Partial<LinhaFunilEscritorio>): LinhaFunilEscritorio => ({
  evento_id: 1, tipo: 'evento', nome: 'e', categoria: null, inicio: null, fim: null,
  sessoes_vendas: 0, sessoes_pessoas: 0, sessoes_valor: 0, sessoes_estornos: 0, sessoes_estornos_valor: 0,
  pessoas: 0, croqui_pessoas: 0, croqui_pct: null, croqui_valor: 0, hf_pessoas: 0, hf_pct: null, hf_valor: 0,
  mediana_dias_sessao_croqui: null, mediana_dias_croqui_hf: null, escritorio_visivel: true, ...p,
});

describe('totalizarFunilEscritorio', () => {
  it('soma eventos + baldes; % sobre as somas, 1 casa', () => {
    const t = totalizarFunilEscritorio([
      linha({ sessoes_vendas: 101, pessoas: 100, croqui_pessoas: 30, hf_pessoas: 2 }),
      linha({ evento_id: -3, tipo: 'perene', sessoes_vendas: 110, pessoas: 110, croqui_pessoas: 36, hf_pessoas: 3 }),
      linha({ evento_id: -2, tipo: 'croqui', pessoas: 29, croqui_pessoas: 0, hf_pessoas: 2 }),
    ]);
    expect(t).toEqual({ sessoes_vendas: 211, pessoas: 239, croqui_pessoas: 66, croqui_pct: 27.6, hf_pessoas: 7, hf_pct: 2.9 });
  });
  it('sem pessoas: % nula, nunca divisão por zero', () => {
    expect(totalizarFunilEscritorio([linha({})]).croqui_pct).toBeNull();
    expect(totalizarFunilEscritorio([]).hf_pct).toBeNull();
  });
});

describe('criarCacheEscritorioFunil', () => {
  it('1 RPC do funil e 1 por linha, mesmo com pedidos repetidos e simultâneos', async () => {
    const repo = {
      loadEscritorioFunil: vi.fn(async () => [linha({})]),
      loadEscritorioFunilPessoas: vi.fn<(id: number) => Promise<PessoaFunilEscritorio[]>>(async () => []),
    };
    const c = criarCacheEscritorioFunil(repo);
    expect(c.funilLido()).toBeUndefined();
    await Promise.all([c.funil(), c.funil()]);
    await c.funil();
    expect(repo.loadEscritorioFunil).toHaveBeenCalledTimes(1);
    expect(c.funilLido()).toHaveLength(1);
    await Promise.all([c.pessoas(15), c.pessoas(15), c.pessoas(-3)]);
    await c.pessoas(15);
    expect(repo.loadEscritorioFunilPessoas).toHaveBeenCalledTimes(2);
    expect(repo.loadEscritorioFunilPessoas.mock.calls.map((a) => a[0])).toEqual([15, -3]);
  });
  it('falha não fica guardada: a próxima tentativa consulta de novo', async () => {
    let n = 0;
    const repo = {
      loadEscritorioFunil: vi.fn(async () => { n += 1; if (n === 1) throw new Error('x'); return [linha({})]; }),
      loadEscritorioFunilPessoas: vi.fn(async () => []),
    };
    const c = criarCacheEscritorioFunil(repo);
    await expect(c.funil()).rejects.toThrow('x');
    expect(c.funilLido()).toBeUndefined();
    await expect(c.funil()).resolves.toHaveLength(1);
    expect(repo.loadEscritorioFunil).toHaveBeenCalledTimes(2);
  });
});
