import { describe, expect, it, vi } from 'vitest';
import { carregarContasReceber, hojeSaoPaulo } from './carregar-contas-receber';
import type { LinhaReceber } from '../domain/contas-receber';

const linha: LinhaReceber = {
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: 865.01,
  situacao: 'a_receber', origem_dia: '2026-09-25', ref: null, rotulo: null, produto: null, k: null, detalhe: [], pagas: [], valor_bruto: 865.01, fator: 1, certeza: 'certo', centro_custo: null, tratamento: null, cenario: 'base',
};

describe('carregarContasReceber', () => {
  it('1 RPC; grade e recorrências montadas da mesma resposta', async () => {
    const repo = { loadContasReceber: vi.fn().mockResolvedValue([linha]) };
    const r = await carregarContasReceber(repo, 'base', '2026-09-28');
    expect(repo.loadContasReceber).toHaveBeenCalledTimes(1);
    expect(r.grade.semanas[0].inicio).toBe('2026-09-28');
    expect(r.grade.total).toBe(865.01);
    expect(r.recorrencias).toEqual([]);
  });
  it('erro do repositório sobe (não vira grade vazia)', async () => {
    const repo = { loadContasReceber: vi.fn().mockRejectedValue(new Error('Não foi possível carregar as contas a receber.')) };
    await expect(carregarContasReceber(repo, 'base', '2026-09-28')).rejects.toThrow('contas a receber');
  });
  it('hoje em São Paulo, não em UTC', () => {
    expect(hojeSaoPaulo(new Date('2026-09-29T01:30:00Z'))).toBe('2026-09-28');
  });
});
