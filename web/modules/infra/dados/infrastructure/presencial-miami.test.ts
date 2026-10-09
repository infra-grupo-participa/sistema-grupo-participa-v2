import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc: mocks.rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { carregarDiamantesMiami, carregarFichasInteresseMiami } from './presencial-data';

describe('abas novas da Clínica Miami', () => {
  beforeEach(() => mocks.rpc.mockReset());

  it('carrega a lista de Diamantes pela RPC da chave do dashboard', async () => {
    const linha = { lista_ordem: 1, lista_nome: 'Pessoa de teste', status: 'pendente', casamento: null, situacao: null };
    mocks.rpc.mockResolvedValue({ data: [linha], error: null });

    const resultado = await carregarDiamantesMiami('clinica-miami-2026-12');

    expect(mocks.rpc).toHaveBeenCalledWith('dados_miami_diamantes', { p_chave: 'clinica-miami-2026-12' });
    expect(resultado).toEqual({ data: [linha], erro: null });
  });

  it('preserva a classificação de ficha preenchida sem compra para a lista do time', async () => {
    const linha = { resposta_uuid: 'uuid-teste', nome: 'Pessoa de teste', comprou: false, compra_status: 'em_aberto', casou_por: 'telefone' };
    mocks.rpc.mockResolvedValue({ data: [linha], error: null });

    const resultado = await carregarFichasInteresseMiami('clinica-miami-2026-12');

    expect(mocks.rpc).toHaveBeenCalledWith('dados_miami_interesse', { p_chave: 'clinica-miami-2026-12' });
    expect(resultado.data?.[0]).toMatchObject({ comprou: false, compra_status: 'em_aberto', casou_por: 'telefone' });
  });

  it('retorna erro PGRST202 sem derrubar a leitura quando a função não está disponível', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });

    const resultado = await carregarFichasInteresseMiami('clinica-miami-2026-12');

    expect(resultado).toEqual({ data: null, erro: 'Esta função ainda não está no banco. Avise quem cuida do sistema.' });
  });
});
