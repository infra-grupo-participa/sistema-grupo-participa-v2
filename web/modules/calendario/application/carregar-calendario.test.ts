import { describe, expect, it } from 'vitest';
import { carregarCalendario } from './carregar-calendario';
import type { CalendarioRepository } from './ports';

describe('carregarCalendario', () => {
  it('pede ao repositório a janela do mês anterior a +3 meses', async () => {
    const pedidos: [string, string][] = [];
    const repo: CalendarioRepository = {
      async listarEventos(de, ate) {
        pedidos.push([de, ate]);
        return [];
      },
    };
    const r = await carregarCalendario(repo, 2026, 10);
    expect(pedidos).toEqual([['2026-09-01', '2027-01-31']]);
    expect(r).toEqual({ janela: { de: '2026-09-01', ate: '2027-01-31' }, eventos: [] });
  });
  it('propaga o erro do banco (não vira lista vazia)', async () => {
    const repo: CalendarioRepository = { listarEventos: async () => { throw new Error('42501'); } };
    await expect(carregarCalendario(repo, 2026, 10)).rejects.toThrow('42501');
  });
});
