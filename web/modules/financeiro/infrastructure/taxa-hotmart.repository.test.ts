// Adapter da Taxa Hotmart (z70): argumentos exatos e tradução dos erros. Rede mockada — prova o que o front ENVIA e
// como traduz a resposta, não que a RPC viva responde.
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

const { SupabaseFinanceiroRepository } = await import('./supabase-financeiro.repository');
const repo = new SupabaseFinanceiroRepository();

beforeEach(() => rpc.mockReset());

describe('Taxa Hotmart — RPCs', () => {
  it('auditoria: fn_fin_taxa_auditoria(p_inicio, p_fim), linhas cruas', async () => {
    rpc.mockResolvedValue({ data: [{ tipo: 'a_vista', produto_id: 'p' }], error: null });
    const r = await repo.loadTaxaAuditoria('2026-01-01', '2026-09-28');
    expect(rpc).toHaveBeenCalledWith('fn_fin_taxa_auditoria', { p_inicio: '2026-01-01', p_fim: '2026-09-28' });
    expect(r).toEqual([{ tipo: 'a_vista', produto_id: 'p' }]);
  });
  it('divergências: fn_fin_taxa_divergencias, normalizadas', async () => {
    rpc.mockResolvedValue({ data: [{ transacao: 'HP1', dia: '2026-02-03', produto_id: 'p', produto_nome: 'HM',
      valor_oferta: '1000', taxa_real: '70', taxa_esperada: '54', diferenca: '16' }], error: null });
    const [d] = await repo.loadTaxaDivergencias('2026-01-01', '2026-09-28');
    expect(rpc).toHaveBeenCalledWith('fn_fin_taxa_divergencias', { p_inicio: '2026-01-01', p_fim: '2026-09-28' });
    expect(d).toMatchObject({ transacao: 'HP1', diferenca: 16, taxaEsperada: 54 });
  });
  it('42501 → sem permissão; 22023 → mensagem do banco; outro → rede (nunca tabela vazia)', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.loadTaxaAuditoria('2026-01-01', '2026-09-28')).rejects.toThrow('Sem permissão para ver o financeiro.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '22023', message: 'Janela máxima de 400 dias.' } });
    await expect(repo.loadTaxaDivergencias('2025-01-01', '2026-09-28')).rejects.toThrow('Janela máxima de 400 dias.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '08006', message: 'x' } });
    await expect(repo.loadTaxaAuditoria('2026-01-01', '2026-09-28')).rejects.toThrow('erro de rede');
  });
});
