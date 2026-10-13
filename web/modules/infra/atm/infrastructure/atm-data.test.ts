import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc: mocks.rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { carregarAtmDisparosLista, desmarcarAtmTestePorEmail, marcarAtmTestePorEmail, carregarAtmGrupo, carregarAtmSvVendas, carregarAtmLeads, carregarAtmResumo, carregarAtmTrafego, desmarcarAtmTeste, marcarAtmTeste } from './atm-data';

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
    }], error: null });

    const resultado = await carregarAtmResumo('atm-elaine-1-2026-10', { p_de: null, p_ate: null });

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_resumo', { p_chave: 'atm-elaine-1-2026-10', p_de: null, p_ate: null });
    expect(resultado.data.resumo.disparos).toEqual({ valor: 0, semDado: false });
    expect(resultado.data.resumo.custoDisparo).toEqual({ valor: 0, semDado: true });
    expect(resultado.data.resumo.custoTrafego).toEqual({ valor: 0, semDado: true });
    expect(resultado.data.resumo.investimentoTotal).toEqual({ valor: 0, semDado: true });
    expect(resultado.data.periodo).toEqual({ de: '2026-10-07', ate: '2026-10-14', leadsTeste: 1, grupoTeste: 2, vendasTeste: 1, receitaTesteBruta: 197 });
  });

  it('converte investimento geral e tráfego de centavos para reais', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ custo_disparo_centavos: 2500, custo_trafego_centavos: 5000, investimento_total_centavos: 7500 }], error: null });

    const resultado = await carregarAtmResumo('atm-elaine-1-2026-10');

    expect(resultado.data.resumo.custoDisparo).toEqual({ valor: 25, semDado: false });
    expect(resultado.data.resumo.custoTrafego).toEqual({ valor: 50, semDado: false });
    expect(resultado.data.resumo.investimentoTotal).toEqual({ valor: 75, semDado: false });
  });

  it('oculta CPL, CAC e ROAS antigos enquanto o resumo não informar investimento total', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ cpl_centavos: 1200, cac_centavos: 4000, roas_liquido: 2.5 }], error: null });

    const resultado = await carregarAtmResumo('atm-elaine-1-2026-10');

    expect(resultado.data.resumo.cpl.semDado).toBe(true);
    expect(resultado.data.resumo.cac.semDado).toBe(true);
    expect(resultado.data.resumo.roas.semDado).toBe(true);
  });

  it('envia o período, mapeia o JSON de tráfego e preserva os nulos', async () => {
    mocks.rpc.mockResolvedValue({ data: {
      periodo_de: '2026-10-08', periodo_ate: '2026-10-08', moeda: 'BRL', coletado_em: null,
      calculados: ['cpm_centavos', 'ctr_pct', 'cpc_centavos'],
      total: {
        gasto_centavos: 4987, impressoes: 883, alcance: null, frequencia: null, alcance_motivo: 'sem_total',
        alcance_de: null, alcance_ate: null, cliques_link: 0, cliques_total: null, cliques_saida: null,
        landing_page_views: null, engajamento: null, video_plays: null, video_thruplay: null, video_p25: null,
        video_p50: null, video_p75: null, video_p100: null, cpm_centavos: null, ctr_pct: null, cpc_centavos: null,
        dias: 1, primeiro_dia: '2026-10-08', ultimo_dia: '2026-10-08',
      },
      dias: [{ dia: '2026-10-08', gasto_centavos: 4987, impressoes: 883, alcance: null, frequencia: null, cliques_link: 0 }],
      campanhas: [{ id: 8441, nome: 'CF | ATM1OUT26 | DISTRIBUIÇÃO | BY THE WAY | META | PQ | ABO | ALCANCE', status: 'ACTIVE', objetivo: 'DISTRIBUIÇÃO', conta: 'Seminários - Leads', gasto_centavos: 4987, primeiro_dia: '2026-10-08', ultimo_dia: '2026-10-08' }],
    }, error: null });

    const resultado = await carregarAtmTrafego('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' });

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_trafego', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-08', p_ate: '2026-10-08',
    });
    expect(resultado.semDado).toBe(false);
    expect(resultado.data.total).toMatchObject({ gastoCentavos: 4987, impressoes: 883, alcance: null, frequencia: null, cliquesLink: 0, alcanceMotivo: 'sem_total' });
    expect(resultado.data.dias[0]).toMatchObject({ dia: '2026-10-08', gastoCentavos: 4987, alcance: null, frequencia: null });
    expect(resultado.data.campanhas[0].nome).toBe('CF | ATM1OUT26 | DISTRIBUIÇÃO | BY THE WAY | META | PQ | ABO | ALCANCE');
  });

  it('trata a RPC de tráfego ainda ausente como sem dado', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });

    const resultado = await carregarAtmTrafego('atm-elaine-1-2026-10', { p_de: null, p_ate: null });

    expect(resultado.semDado).toBe(true);
    expect(resultado.erro).toBeNull();
    expect(resultado.data.total.gastoCentavos).toBeNull();
  });

  it('trata recusa de leitura do tráfego como falha isolada sem conteúdo para substituir o último dado', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: '42501' } });

    const resultado = await carregarAtmTrafego('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' });

    expect(resultado.semDado).toBe(true);
    expect(resultado.erro).toBe('Sem permissão para ler este dashboard.');
  });

  it('envia inclusão de teste somente quando pedida e mapeia o estado do lead', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ email: 'qa@example.com', telefone: '5511999999999', pessoa_id: 'p1', teste: true, entrou_grupo: true, eh_aluno: false }], error: null });

    const resultado = await carregarAtmLeads('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' }, true);

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_leads', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-08', p_ate: '2026-10-08', p_incluir_teste: true,
    });
    expect(resultado.data[0]).toMatchObject({ pessoaId: 'p1', teste: true, entrouGrupo: true, aluno: false });
  });

  it('carrega o detalhe de disparos com os parâmetros do contrato e preserva valores nulos', async () => {
    mocks.rpc.mockResolvedValue({ data: [{
      disparo_id: 123,
      data_hora: '2026-10-08T22:30:00Z',
      enviado_em: null,
      canal: 'whatsapp_api',
      canal_pago: true,
      tipo: 'marketing',
      ferramenta: 'Infobip',
      numero: null,
      campanha: 'Campanha de teste',
      publico_lista: null,
      publico_origem: 'lista',
      copy_texto: null,
      copy_link: 'https://example.com/campanha',
      tamanho_lista: 40,
      entregues: 35,
      lidas: null,
      cliques: 4,
      falhas: 2,
      custo_centavos: null,
      origem: 'api',
      retorno_em: null,
    }], error: null });

    const resultado = await carregarAtmDisparosLista('atm-elaine-1-2026-10', { p_de: '2026-10-07', p_ate: '2026-10-14' });

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_disparos_lista', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-07', p_ate: '2026-10-14',
    });
    expect(resultado.data[0]).toMatchObject({
      id: 123, dataHora: '2026-10-08T22:30:00Z', enviadoEm: null, canal: 'whatsapp_api', canalPago: true,
      campanha: 'Campanha de teste', enviados: 40, entregues: 35, lidas: null, cliques: 4, falhas: 2,
      custoCentavos: null, copyTexto: null, copyLink: 'https://example.com/campanha',
    });
  });

  it('trata a RPC de detalhe ainda indisponível como sem dado', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });

    const resultado = await carregarAtmDisparosLista('atm-elaine-1-2026-10', { p_de: null, p_ate: null });

    expect(resultado).toEqual({ data: [], semDado: true, erro: null });
  });

  it('carrega números do grupo no período incluindo os já marcados para permitir desfazer', async () => {
    mocks.rpc.mockResolvedValue({ data: [{ fone_key: '5511999999999', nome: 'QA', entrou_em: '2026-10-08T12:00:00Z', no_grupo: true, eh_lead: false, teste: true, teste_motivo: 'teste' }], error: null });

    const resultado = await carregarAtmGrupo('atm-elaine-1-2026-10', { p_de: '2026-10-08', p_ate: '2026-10-08' }, true);

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_grupo_numeros', {
      p_chave: 'atm-elaine-1-2026-10', p_de: '2026-10-08', p_ate: '2026-10-08', p_incluir_teste: true,
    });
    expect(resultado.data[0]).toMatchObject({ foneKey: '5511999999999', teste: true, testeMotivo: 'teste' });
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

describe('marcação de teste da SV (só e-mail)', () => {
  beforeEach(() => { mocks.rpc.mockReset(); });

  it('marca mandando p_telefone nulo', async () => {
    mocks.rpc.mockResolvedValue({ data: 1, error: null });
    expect(await marcarAtmTestePorEmail('atm-elaine-1-2026-10', 'qa@example.com')).toEqual({ data: 1, erro: null });
    expect(mocks.rpc).toHaveBeenCalledWith('dados_marcar_teste', { p_chave: 'atm-elaine-1-2026-10', p_email: 'qa@example.com', p_telefone: null, p_motivo: 'teste' });
  });

  it('desmarca mandando p_telefone nulo', async () => {
    mocks.rpc.mockResolvedValue({ data: 1, error: null });
    await desmarcarAtmTestePorEmail('atm-elaine-1-2026-10', 'qa@example.com');
    expect(mocks.rpc).toHaveBeenCalledWith('dados_desmarcar_teste', { p_chave: 'atm-elaine-1-2026-10', p_email: 'qa@example.com', p_telefone: null });
  });
});

describe('vendas da Sessão de Viabilidade (dados_atm_sv_vendas)', () => {
  // Com chaves: devolver o mock faria o Vitest chamá-lo como limpeza depois de cada teste.
  beforeEach(() => { mocks.rpc.mockReset(); });
  afterEach(() => vi.useRealTimers());

  it('chama a RPC só com chave e inclusão de teste e mapeia o contrato, preservando nulos', async () => {
    mocks.rpc.mockResolvedValue({ data: [
      { transacao: 'HP-fixture-1', aprovado_em: '2026-10-14T01:30:00Z', pedido_em: '2026-10-14T01:20:00Z', dia_aprovado: '2026-10-13', nome: 'QA', email: 'qa@example.com', telefone: '5511999999999', valor_bruto: '10.50', valor_liquido: null, moeda: 'BRL', status: 'APPROVED', oferta_codigo: 'fixture', teste: true },
      { transacao: null, aprovado_em: null, pedido_em: null, dia_aprovado: null, nome: null, email: null, telefone: null, valor_bruto: null, valor_liquido: null, moeda: null, status: null, oferta_codigo: null, teste: null },
    ], error: null });

    const resultado = await carregarAtmSvVendas('atm-elaine-1-2026-10', true);

    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_sv_vendas', { p_chave: 'atm-elaine-1-2026-10', p_incluir_teste: true });
    expect(resultado.semDado).toBe(false);
    expect(resultado.erro).toBeNull();
    expect(resultado.data[0]).toEqual({
      id: 'HP-fixture-1', transacao: 'HP-fixture-1', aprovadoEm: '2026-10-14T01:30:00Z', pedidoEm: '2026-10-14T01:20:00Z', diaAprovado: '2026-10-13',
      nome: 'QA', email: 'qa@example.com', telefone: '5511999999999', valorBruto: 10.5, valorLiquido: null, moeda: 'BRL', status: 'APPROVED',
      ofertaCodigo: 'fixture', teste: true,
    });
    expect(resultado.data[1]).toMatchObject({ id: 'linha-1', transacao: null, valorBruto: null, moeda: null, teste: false });
  });

  it('não pede testes por padrão', async () => {
    mocks.rpc.mockResolvedValue({ data: [], error: null });
    const resultado = await carregarAtmSvVendas('atm-elaine-1-2026-10');
    expect(mocks.rpc).toHaveBeenCalledWith('dados_atm_sv_vendas', { p_chave: 'atm-elaine-1-2026-10', p_incluir_teste: false });
    expect(resultado).toEqual({ data: [], semDado: false, erro: null });
  });

  it('trata a RPC ainda não aplicada como sem dado, sem mensagem de erro', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });
    expect(await carregarAtmSvVendas('atm-elaine-1-2026-10')).toEqual({ data: [], semDado: true, erro: null });
  });

  it('trata recusa do banco como sem dado com aviso, para a tela manter a última lista', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: '42501' } });
    expect(await carregarAtmSvVendas('atm-elaine-1-2026-10')).toEqual({ data: [], semDado: true, erro: 'Sem permissão para ler este dashboard.', semPermissao: true });
  });

  it('só 42501 marca semPermissao; outras falhas não', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'XX000' } });
    const r = await carregarAtmSvVendas('atm-elaine-1-2026-10');
    expect(r.semPermissao).toBeUndefined();
    expect(r.erro).toBe('Não foi possível carregar os dados agora.');
  });

  it('trata falha de rede como sem dado com aviso', async () => {
    mocks.rpc.mockImplementation(async () => { throw new Error('offline'); });
    const resultado = await carregarAtmSvVendas('atm-elaine-1-2026-10');
    expect(resultado.semDado).toBe(true);
    expect(resultado.data).toEqual([]);
    expect(resultado.erro).toMatch(/Falha de conexão/);
  });

  it('desiste depois do tempo limite em vez de travar o bloco', async () => {
    vi.useFakeTimers();
    mocks.rpc.mockReturnValue(new Promise(() => {}));
    const pendente = carregarAtmSvVendas('atm-elaine-1-2026-10', false, 1000);
    await vi.advanceTimersByTimeAsync(1000);
    const resultado = await pendente;
    expect(resultado.semDado).toBe(true);
    expect(resultado.data).toEqual([]);
    expect(resultado.erro).toMatch(/demoraram a responder/);
  });
});
