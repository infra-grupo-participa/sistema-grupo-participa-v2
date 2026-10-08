import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc: mocks.rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { carregarAtmGrupo, carregarAtmLeads, carregarAtmResumo, desmarcarAtmTeste, marcarAtmTeste } from './atm-data';

describe('leitura e marcação do dashboard ATM', () => {
  beforeEach(() => mocks.rpc.mockReset());

  it('envia o período ao resumo e preserva zero medido e dados de aviso', async () => {
    mocks.rpc.mockResolvedValue({ data: [{
      disparos_qtd: 0,
      leads: 60,
      grupo_entradas: 7,
      grupo_pct: 11.67,
      evasao_pct: 14.29,
      custo_disparo_centavos: null,
      cpl_centavos: null,
      pre_checkout_pessoas: 0,
      vendas: 0,
      conversao_pre_checkout_pct: null,
      cac_centavos: null,
      receita_bruta: 0,
      receita_liquida: 0,
      roas_liquido: null,
      periodo_de: '2026-10-07',
      periodo_ate: '2026-10-14',
      leads_teste: 1,
      grupo_teste: 2,
      vendas_teste: 1,
      receita_teste_bruta: 197,
      grupo_entradas_aproximadas: 41,
      grupo_foto_em: '2026-10-08T19:35:00Z',
      grupo_no_grupo: 46,
    }], error: null });

    const resultado = await carregarAtmResumo('atm-elaine-1-2026-10', { p_de: null, p_ate: null });

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_resumo', { p_chave: 'atm-elaine-1-2026-10', p_de: null, p_ate: null });
    expect(resultado.data.resumo.disparos).toEqual({ valor: 0, semDado: false });
    expect(resultado.data.resumo.custoDisparo).toEqual({ valor: 0, semDado: true });
    expect(resultado.data.periodo).toEqual({
      de: '2026-10-07', ate: '2026-10-14', leadsTeste: 1, grupoTeste: 2, vendasTeste: 1, receitaTesteBruta: 197,
      grupoEntradasAproximadas: 41, grupoFotoEm: '2026-10-08T19:35:00Z', grupoNoGrupo: 46,
    });
  });

  it('envia inclusão de teste somente quando pedida e mapeia o estado do lead', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ email: 'qa@example.com', telefone: '5511999999999', pessoa_id: 'p1', teste: true, entrou_grupo: true, eh_aluno: false }], error: null });

    const resultado = await carregarAtmLeads('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' }, true);

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_leads', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-08', p_ate: '2026-10-08', p_incluir_teste: true,
    });
    expect(resultado.data[0]).toMatchObject({ pessoaId: 'p1', teste: true, entrouGrupo: true, aluno: false });
  });

  it('carrega números do grupo no período incluindo os já marcados para permitir desfazer', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ fone_key: '5511999999999', nome: 'QA', entrou_em: '2026-10-08T12:00:00Z', no_grupo: true, eh_lead: false, teste: true, teste_motivo: 'teste', entrada_aproximada: true, grupos: '13/10 #1' }], error: null });

    const resultado = await carregarAtmGrupo('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' }, true);

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_grupo_numeros', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-08', p_ate: '2026-10-08', p_incluir_teste: true,
    });
    expect(resultado.data[0]).toMatchObject({ foneKey: '5511999999999', teste: true, testeMotivo: 'teste', entradaAproximada: true, grupos: '13/10 #1' });
  });

  it('envia ambos identificadores para desfazer e comunica recusa do banco', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: 2, error: null });
    const resultado = await desmarcarAtmTeste('atm-elaine-1-2026-10', 'qa@example.com', '5511999999999');
    expect(mocks.rpc).toHaveBeenLastCalledWith('dados_desmarcar_teste', {
      p_chave: 'atm-elaine-1-2026-10', p_email: 'qa@example.com', p_telefone: '5511999999999',
    });
    expect(resultado).toEqual({ data: 2, erro: null });

    mocks.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect(await marcarAtmTeste('atm-elaine-1-2026-10', 'qa@example.com', null)).toEqual({
      data: null, erro: 'Seu usuário não tem permissão para marcar testes neste dashboard.',
    });
  });
});
