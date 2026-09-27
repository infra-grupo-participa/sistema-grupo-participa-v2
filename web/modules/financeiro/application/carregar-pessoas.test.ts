import { describe, expect, it, vi } from 'vitest';
import { carregarPessoasHotmart } from './carregar-pessoas';

describe('carregarPessoasHotmart', () => {
  it('reaproveita a consulta por família dentro da validade e refaz depois', async () => {
    const repo = { loadHotmartPessoas: vi.fn().mockResolvedValue([]) };
    await carregarPessoasHotmart(repo, 'HM', 0);
    await carregarPessoasHotmart(repo, 'HM', 60_000);
    expect(repo.loadHotmartPessoas).toHaveBeenCalledTimes(1);
    await carregarPessoasHotmart(repo, 'AURUM', 60_000);
    expect(repo.loadHotmartPessoas).toHaveBeenCalledTimes(2);
    await carregarPessoasHotmart(repo, 'HM', 11 * 60_000);
    expect(repo.loadHotmartPessoas).toHaveBeenCalledTimes(3);
  });
  it('falha não fica em cache', async () => {
    const repo = { loadHotmartPessoas: vi.fn().mockRejectedValueOnce(new Error('x')).mockResolvedValue([]) };
    await expect(carregarPessoasHotmart(repo, 'HM', 0)).rejects.toThrow('x');
    await carregarPessoasHotmart(repo, 'HM', 1);
    expect(repo.loadHotmartPessoas).toHaveBeenCalledTimes(2);
  });
});
