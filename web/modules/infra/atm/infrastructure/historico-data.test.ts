import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), resposta: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({
  createBrowserSupabase: () => ({ rpc: (...args: unknown[]) => { mocks.rpc(...args); return { abortSignal: () => mocks.resposta() }; } }),
}));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { carregarHistoricoEdicoes } from './historico-data';

const linhaAtm2 = {
  chave: 'atm-set-26', familia: 'seminario-atm', rotulo: 'ATM2 SET/26', ordem: 2, data_inicio: null, data_fim: null,
  leads: 911, invest_trafego_centavos: 0, invest_disparo_centavos: 211948, grupo: 743, pico_d1: 127, pico_d2: 62, pico_d3: 40,
  vendas: 9, receita_liquida_centavos: 1275291, pre_checkout: 33,
  fontes: { leads: 'debrief SET', invest_disparo: 'Custos SET B44', outra: 'ignorada' }, provisorio: ['pre_checkout'],
};
const linhaAtm1 = {
  ...linhaAtm2, chave: 'atm-jul-26', rotulo: 'ATM1 JUL/26', ordem: 1, leads: 424, invest_disparo_centavos: 203993,
  grupo: 345, pico_d1: 74, pico_d2: 21, pico_d3: null, vendas: 7, receita_liquida_centavos: 991907, pre_checkout: 26, provisorio: [],
};

describe('leitura do histórico de edições', () => {
  beforeEach(() => { mocks.rpc.mockReset(); mocks.resposta.mockReset(); });

  it('chama a RPC pela família, converte centavos em reais e ordena pela ordem', async () => {
    mocks.resposta.mockResolvedValue({ data: [linhaAtm2, linhaAtm1], error: null });
    const r = await carregarHistoricoEdicoes('seminario-atm');
    expect(mocks.rpc).toHaveBeenCalledWith('dados_historico_edicoes', { p_familia: 'seminario-atm' });
    expect(r.erro).toBeNull();
    expect(r.semDado).toBe(false);
    expect(r.data.map((e) => e.rotulo)).toEqual(['ATM1 JUL/26', 'ATM2 SET/26']);
    expect(r.data[0]).toMatchObject({ investTrafego: 0, investDisparo: 2039.93, receitaLiquida: 9919.07, picoD3: null });
    expect(r.data[1].fontes).toEqual({ leads: 'debrief SET', invest_disparo: 'Custos SET B44' });
    expect(r.data[1].provisorio).toEqual(['pre_checkout']);
  });

  it('função ainda inexistente (PGRST202) = sem dado ainda, sem mensagem de erro', async () => {
    mocks.resposta.mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'not found' } });
    expect(await carregarHistoricoEdicoes('seminario-atm')).toEqual({ data: [], semDado: true, erro: null });
  });

  it('recusa de acesso e tempo limite viram mensagem legível', async () => {
    mocks.resposta.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'x' } });
    expect((await carregarHistoricoEdicoes('seminario-atm')).erro).toBe('Sem permissão para ler o histórico.');
    mocks.resposta.mockResolvedValueOnce({ data: null, error: { code: '', message: 'TimeoutError: signal timed out' } });
    const r = await carregarHistoricoEdicoes('seminario-atm');
    expect(r.semDado).toBe(true);
    expect(r.erro).toContain('demorou demais');
  });

  it('falha de rede não derruba a tela', async () => {
    mocks.resposta.mockRejectedValue(new Error('rede'));
    const r = await carregarHistoricoEdicoes('seminario-atm');
    expect(r).toMatchObject({ data: [], semDado: true });
    expect(r.erro).toContain('Falha de conexão');
  });
});
