import { describe, it, expect, vi } from 'vitest';
import { carregarProrataHM } from './carregar-prorata';

describe('carregarProrataHM', () => {
  it('1 RPC para várias fichas; recarrega depois da validade', async () => {
    const repo = { loadProrataHM: vi.fn().mockResolvedValue([]) };
    await carregarProrataHM(repo, 0);
    await carregarProrataHM(repo, 1000);
    expect(repo.loadProrataHM).toHaveBeenCalledTimes(1);
    expect(repo.loadProrataHM).toHaveBeenCalledWith(15000);
    await carregarProrataHM(repo, 11 * 60 * 1000);
    expect(repo.loadProrataHM).toHaveBeenCalledTimes(2);
  });
  it('falha não fica em cache', async () => {
    const repo = { loadProrataHM: vi.fn().mockRejectedValueOnce(new Error('x')).mockResolvedValue([]) };
    await expect(carregarProrataHM(repo, 0)).rejects.toThrow();
    await expect(carregarProrataHM(repo, 1)).resolves.toEqual([]);
    expect(repo.loadProrataHM).toHaveBeenCalledTimes(2);
  });
});
