// Adapter das Ofertas a confirmar (z82): argumentos exatos e tradução dos erros. Rede mockada — prova o que o front
// ENVIA e como traduz a resposta, não que a RPC viva responde.
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

const { SupabaseFinanceiroRepository } = await import('./supabase-financeiro.repository');
const repo = new SupabaseFinanceiroRepository();

beforeEach(() => rpc.mockReset());

describe('Ofertas a confirmar — RPCs', () => {
  it('fila: fn_fin_fila_ofertas sem argumentos, normalizada', async () => {
    rpc.mockResolvedValue({ data: [{ oferta_codigo: 'a', n_vendas: 3, sugestao_evento_id: '9', sugestao_evento: 'Ev' }], error: null });
    const [o] = await repo.carregarFilaOfertas();
    expect(rpc).toHaveBeenCalledWith('fn_fin_fila_ofertas');
    expect(o).toMatchObject({ oferta_codigo: 'a', n_vendas: 3, sugestao_evento_id: 9, sugestao_evento: 'Ev' });
  });

  it('fila: data null = lista vazia; 42501 = sem permissão; outro = rede', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: null });
    await expect(repo.carregarFilaOfertas()).resolves.toEqual([]);
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.carregarFilaOfertas()).rejects.toThrow('Sem permissão para ver o financeiro.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '08006', message: 'x' } });
    await expect(repo.carregarFilaOfertas()).rejects.toThrow('erro de rede');
  });

  it('decidir: argumentos exatos por ação', async () => {
    rpc.mockResolvedValue({ data: { status: 'confirmada', evento_id: 7, evento_criado: false }, error: null });
    await expect(repo.decidirOferta('a', { tipo: 'confirmar', eventoId: 7 })).resolves.toEqual({ ok: true, msg: 'Vendas ligadas ao evento.' });
    expect(rpc).toHaveBeenLastCalledWith('fn_fin_decidir_oferta', { p_oferta: 'a', p_evento_id: 7 });

    rpc.mockResolvedValue({ data: { status: 'rejeitada' }, error: null });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' })).resolves.toMatchObject({ ok: true });
    expect(rpc).toHaveBeenLastCalledWith('fn_fin_decidir_oferta', { p_oferta: 'a', p_rejeitar: true });

    rpc.mockResolvedValue({ data: { status: 'confirmada', evento_criado: true }, error: null });
    await expect(repo.decidirOferta('a', { tipo: 'criar', evento: { nome: 'N', categoria: 'clinica', inicio: '2026-10-01' } }))
      .resolves.toEqual({ ok: true, msg: 'Evento criado e vendas ligadas a ele.' });
    expect(rpc).toHaveBeenLastCalledWith('fn_fin_decidir_oferta',
      { p_oferta: 'a', p_criar: { nome: 'N', categoria: 'clinica', inicio: '2026-10-01' } });
  });

  it('decidir: erros viram texto simples; já decidida/ligada/fora da fila pede recarga', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '55000', message: 'A oferta a já foi decidida (confirmada).' } });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' }))
      .resolves.toEqual({ ok: false, msg: 'Outra pessoa já decidiu esta oferta. A lista foi atualizada.', recarregar: true });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '23505', message: 'Já existe evento clinica começando em 2026-10-01: escolha-o na lista.' } });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' }))
      .resolves.toEqual({ ok: false, msg: 'Já existe evento clinica começando em 2026-10-01: escolha-o na lista.', recarregar: true });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '22023', message: 'Datas do evento inválidas.' } });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' })).resolves.toEqual({ ok: false, msg: 'Datas do evento inválidas.', recarregar: false });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' }))
      .resolves.toMatchObject({ ok: false, msg: 'Sem permissão para decidir as ofertas do financeiro.' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '08006', message: 'x' } });
    await expect(repo.decidirOferta('a', { tipo: 'rejeitar' })).resolves.toMatchObject({ ok: false, recarregar: false });
  });
});
