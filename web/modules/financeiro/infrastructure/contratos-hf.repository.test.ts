// Adapter dos contratos HF (z93): argumentos exatos e tradução dos erros. Rede mockada — prova o que o front ENVIA e
// como traduz a resposta, não que a RPC viva responde (a z93 ainda não está aplicada).
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

const { SupabaseFinanceiroRepository } = await import('./supabase-financeiro.repository');
const { RecursoAusenteError } = await import('../application/ports');
const repo = new SupabaseFinanceiroRepository();

beforeEach(() => rpc.mockReset());

describe('contratos HF — leituras', () => {
  it('mensal: p_de/p_ate e normalização', async () => {
    rpc.mockResolvedValue({ data: [{ contrato_id: 'c1', mes: '2026-09-01', esperado: '10.50', assinado: 'sim', parcelas: [] }], error: null });
    const [l] = await repo.loadContratosHfMensal(null, null);
    expect(rpc).toHaveBeenCalledWith('fn_fin_contratos_hf_mensal', { p_de: null, p_ate: null });
    expect(l).toMatchObject({ contrato_id: 'c1', esperado: 10.5 });
  });
  it('pagamentos: p_so_fila', async () => {
    rpc.mockResolvedValue({ data: null, error: null });
    await expect(repo.loadContratosHfPagamentos(false)).resolves.toEqual([]);
    expect(rpc).toHaveBeenCalledWith('fn_fin_contratos_hf_pagamentos', { p_so_fila: false });
  });
  it('função ausente (PGRST202) → RecursoAusenteError; 42501 → sem permissão; 22023 → mensagem do banco; outro → rede', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } });
    await expect(repo.loadContratosHfPagamentos(false)).rejects.toBeInstanceOf(RecursoAusenteError);
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.loadContratosHfMensal(null, null)).rejects.toThrow('Sem permissão para ver o financeiro.');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '22023', message: 'Período inválido (início até fim, no máximo 36 meses).' } });
    await expect(repo.loadContratosHfMensal('2020-01-01', '2026-01-01')).rejects.toThrow('Período inválido');
    rpc.mockResolvedValueOnce({ data: null, error: { code: 'XX000', message: 'x' } });
    const e = await repo.loadContratosHfMensal(null, null).catch((x: unknown) => x);
    expect(e).not.toBeInstanceOf(RecursoAusenteError);
    expect((e as Error).message).toContain('erro de rede');
  });
});

describe('contratos HF — escritas', () => {
  it('salvar: manda p como veio; arquivar recusado mostra a MENSAGEM do banco (P0001)', async () => {
    rpc.mockResolvedValueOnce({ data: 'c1', error: null });
    await expect(repo.salvarContratoHf({ id: 'c1', valor_bruto: '44640.00' })).resolves.toEqual({ ok: true, msg: 'Contrato atualizado.' });
    expect(rpc).toHaveBeenCalledWith('fn_fin_contrato_hf_salvar', { p: { id: 'c1', valor_bruto: '44640.00' } });
    const msg = 'Contrato não arquivado: tem pagamento da Hotmart conciliado: desfazer a conciliação não é permitido.';
    rpc.mockResolvedValueOnce({ data: null, error: { code: 'P0001', message: msg } });
    await expect(repo.salvarContratoHf({ id: 'c1', arquivar_motivo: 'duplicado' })).resolves.toEqual({ ok: false, msg });
  });
  it('concluir etapa: p_id/p_data; 42501 → sem permissão de operar', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: null });
    await expect(repo.concluirEtapaParcela('p1', '2026-09-29')).resolves.toMatchObject({ ok: true });
    expect(rpc).toHaveBeenCalledWith('fn_fin_parcela_etapa_concluir', { p_id: 'p1', p_data: '2026-09-29' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Sem permissão.' } });
    await expect(repo.concluirEtapaParcela('p1', null)).resolves.toEqual({ ok: false, msg: 'Sem permissão para operar o financeiro.' });
  });
  it('desfundir: p_id/p_motivo; ficha reaberta muda a mensagem', async () => {
    rpc.mockResolvedValueOnce({ data: 'c9', error: null });
    await expect(repo.desfundirContratoHf('c1', 'sinal era de outra pessoa')).resolves.toMatchObject({ ok: true, msg: expect.stringContaining('reaberta') });
    expect(rpc).toHaveBeenCalledWith('fn_fin_contrato_hf_desfundir', { p_id: 'c1', p_motivo: 'sinal era de outra pessoa' });
    rpc.mockResolvedValueOnce({ data: null, error: null });
    await expect(repo.desfundirContratoHf('c1', 'xyz')).resolves.toEqual({ ok: true, msg: 'Fusão desfeita.' });
  });
});
