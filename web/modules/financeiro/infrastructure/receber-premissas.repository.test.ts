// Adapter do contrato v2 (z66): argumentos exatos de cada RPC e tradução dos erros do banco. Rede mockada — prova o
// que o front ENVIA e como traduz a resposta, não que a RPC viva aceita (a z66 ainda não está aplicada).
import { beforeEach, describe, expect, it, vi } from 'vitest';

const rpc = vi.fn();
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

const { SupabaseFinanceiroRepository, erroPremissa } = await import('./supabase-financeiro.repository');
const repo = new SupabaseFinanceiroRepository();

beforeEach(() => rpc.mockReset());

describe('loadContasReceber — cenário', () => {
  it("'base' NÃO envia p_cenario (funciona com a RPC da z63 durante o deploy)", async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await repo.loadContasReceber();
    await repo.loadContasReceber('base');
    expect(rpc).toHaveBeenNthCalledWith(1, 'fn_fin_receber_semanal', { p_corte: null, p_ate: null });
    expect(rpc).toHaveBeenNthCalledWith(2, 'fn_fin_receber_semanal', { p_corte: null, p_ate: null });
  });
  it('conservador/otimista enviam p_cenario', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await repo.loadContasReceber('conservador');
    expect(rpc).toHaveBeenCalledWith('fn_fin_receber_semanal', { p_corte: null, p_ate: null, p_cenario: 'conservador' });
  });
  it('erro vira exceção (nunca grade vazia)', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'x' } });
    await expect(repo.loadContasReceber('otimista')).rejects.toThrow('contas a receber');
  });
});

describe('premissas e feriados', () => {
  it('salvarPremissaReceber: argumentos da RPC, valor na unidade do banco', async () => {
    rpc.mockResolvedValue({ data: [{}], error: null });
    const r = await repo.salvarPremissaReceber('perda_mensal:parcelas_hm', 0.07, '2026-10-01', 'conservador');
    expect(r.ok).toBe(true);
    expect(rpc).toHaveBeenCalledWith('fn_fin_premissa_receber_salvar',
      { p_chave: 'perda_mensal:parcelas_hm', p_valor: 0.07, p_vigente_de: '2026-10-01', p_cenario: 'conservador' });
  });
  it('salvarFeriado: fn_fin_feriado_salvar(p_dia, p_nome, p_ativo)', async () => {
    rpc.mockResolvedValue({ data: [{}], error: null });
    await repo.salvarFeriado('2026-11-20', 'Consciência Negra', false);
    expect(rpc).toHaveBeenCalledWith('fn_fin_feriado_salvar', { p_dia: '2026-11-20', p_nome: 'Consciência Negra', p_ativo: false });
  });
  it('listas normalizadas (numeric como texto)', async () => {
    rpc.mockResolvedValueOnce({ data: [{ chave: 'x', chave_base: 'x', cenario: 'base', unidade: 'percentual', minimo: '0', maximo: '0.5', valor: '0.05', vigente_de: '2000-01-01', situacao: 'vigente', aceita_cenario: true }], error: null });
    const [p] = await repo.loadPremissasReceber();
    expect(p.valor).toBe(0.05);
    expect(p.maximo).toBe(0.5);
    rpc.mockResolvedValueOnce({ data: [{ dia: '2026-12-25', nome: 'Natal', ativo: true }], error: null });
    const [f] = await repo.loadFeriados();
    expect(f).toMatchObject({ dia: '2026-12-25', nome: 'Natal', ativo: true });
  });
  it('erro do banco mapeado: 42501, 22023 e 23505 (mensagem do SQL), PGRST202, rede', () => {
    expect(erroPremissa('t', { code: '42501', message: 'Sem permissão.' }, 'gravar')).toBe('Sem permissão para operar o financeiro.');
    expect(erroPremissa('t', { code: '22023', message: 'Valor fora da faixa de "X" (0 a 0.5).' }, 'gravar')).toBe('Valor fora da faixa de "X" (0 a 0.5).');
    expect(erroPremissa('t', { code: '23505', message: 'Já existe vigência desta premissa nesta data. Grave com outra data.' }, 'gravar'))
      .toContain('Já existe vigência');
    expect(erroPremissa('t', { code: 'PGRST202' }, 'gravar a premissa')).toContain('ainda não disponível no banco');
    expect(erroPremissa('t', {}, 'gravar a premissa')).toContain('erro de rede');
  });
  it('escrita com erro devolve ok=false com a mensagem (não lança)', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '23505', message: 'Já existe vigência desta premissa nesta data. Grave com outra data.' } });
    const r = await repo.salvarPremissaReceber('tolerancia_atraso_dias', 5, '2026-10-01', 'base');
    expect(r).toEqual({ ok: false, msg: 'Já existe vigência desta premissa nesta data. Grave com outra data.' });
  });
});
