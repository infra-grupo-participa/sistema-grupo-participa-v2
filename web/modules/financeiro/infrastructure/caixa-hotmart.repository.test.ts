// Adapter do Caixa Hotmart (z68): argumentos exatos e tradução dos erros. Rede mockada — prova o que o front ENVIA e
// como traduz a resposta, não que a RPC viva responde.
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

const { SupabaseFinanceiroRepository } = await import('./supabase-financeiro.repository');
const repo = new SupabaseFinanceiroRepository();

beforeEach(() => rpc.mockReset());

describe('Caixa Hotmart — RPCs', () => {
  it('linhas: fn_fin_caixa_hotmart(p_inicio, p_fim), normalizadas', async () => {
    rpc.mockResolvedValue({ data: [{ dia: '2026-09-01', liquido: '93.70', entra_rapido: '81.05', entra_em: '2026-09-03',
      libera_em: '2026-10-01', situacao_d2: 'recebido', situacao_retido: 'em_garantia', n_vendas: 1 }], error: null });
    const [l] = await repo.loadCaixaHotmart('2026-06-01', '2026-09-28');
    expect(rpc).toHaveBeenCalledWith('fn_fin_caixa_hotmart', { p_inicio: '2026-06-01', p_fim: '2026-09-28' });
    expect(l.entraRapido).toBe(81.05);
  });
  it('totais: fn_fin_caixa_hotmart_totais, 1ª linha', async () => {
    rpc.mockResolvedValue({ data: [{ liquido: '10', liquido_total: '9.5', n_vendas: 2 }], error: null });
    const t = await repo.loadCaixaHotmartTotais('2026-06-01', '2026-09-28');
    expect(rpc).toHaveBeenCalledWith('fn_fin_caixa_hotmart_totais', { p_inicio: '2026-06-01', p_fim: '2026-09-28' });
    expect(t).toMatchObject({ liquido: 10, liquidoTotal: 9.5, nVendas: 2 });
  });
  it('42501 → sem permissão; 22023 → mensagem do banco; outro → rede (nunca tabela vazia)', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.loadCaixaHotmart('2026-06-01', '2026-09-28')).rejects.toThrow('Sem permissão para ver o financeiro.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '22023', message: 'Janela máxima de 400 dias.' } });
    await expect(repo.loadCaixaHotmartTotais('2025-01-01', '2026-09-28')).rejects.toThrow('Janela máxima de 400 dias.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '08006', message: 'x' } });
    await expect(repo.loadCaixaHotmart('2026-06-01', '2026-09-28')).rejects.toThrow('erro de rede');
  });
});
