import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc: mocks.rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { carregarAtmDisparosLista, traduzirDisparosLista } from '@/modules/infra/atm/infrastructure/atm-data';
import { carregarDisparosCanais, carregarDisparosLista } from './presencial-data';

const CHAVE = 'clinica-miami-2026-12';
const linhaBruta = {
  disparo_id: 7, data_hora: '2026-10-08T22:30:00Z', enviado_em: null, canal: 'whatsapp_api', canal_pago: true, tipo: 'Convite',
  ferramenta: 'Ferramenta X', numero: null, campanha: 'Campanha de teste', publico_lista: null, publico_origem: null,
  copy_texto: null, copy_link: 'https://example.com/c', tamanho_lista: 40, entregues: 35, lidas: null, cliques: 4, falhas: 2,
  custo_centavos: null, origem: 'mensageria', retorno_em: null,
};

describe('visão de disparos da Clínica (mesmo contrato do ATM)', () => {
  beforeEach(() => { mocks.rpc.mockReset(); });
  afterEach(() => { vi.useRealTimers(); });

  it('chama as RPCs presenciais só com p_chave, sem período', async () => {
    mocks.rpc.mockResolvedValue({ data: [], error: null });
    await carregarDisparosCanais(CHAVE);
    await carregarDisparosLista(CHAVE);
    expect(mocks.rpc).toHaveBeenNthCalledWith(1, 'dados_presencial_disparos_canais', { p_chave: CHAVE });
    expect(mocks.rpc).toHaveBeenNthCalledWith(2, 'dados_presencial_disparos_lista', { p_chave: CHAVE });
  });

  it('devolve as linhas dos canais sem alterar nada, como o ATM', async () => {
    const canal = { canal: 'whatsapp_api', disparos: 3, enviados: 100, entregues: 90, lidas: 50, cliques: 5, falhas: 1, custo_centavos: null };
    mocks.rpc.mockResolvedValue({ data: [canal], error: null });
    expect(await carregarDisparosCanais(CHAVE)).toEqual({ data: [canal], semDado: false, erro: null });
  });

  it('traduz a lista igual à do ATM para a mesma linha, preservando null como sem dado', async () => {
    mocks.rpc.mockResolvedValue({ data: [linhaBruta], error: null });
    const presencial = await carregarDisparosLista(CHAVE);
    const atm = await carregarAtmDisparosLista('atm-elaine-1-2026-10');
    expect(presencial).toEqual(atm);
    expect(presencial.data[0]).toMatchObject({ id: 7, canal: 'whatsapp_api', enviados: 40, entregues: 35, lidas: null, falhas: 2, custoCentavos: null });
    expect(traduzirDisparosLista([linhaBruta])).toEqual(presencial.data);
  });

  it('função ainda fora do banco vira vazio sem dado, sem zero', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST202' } });
    expect(await carregarDisparosLista(CHAVE)).toEqual({ data: [], semDado: true, erro: null });
    expect((await carregarDisparosCanais(CHAVE)).semDado).toBe(true);
  });

  it('erro de permissão e falha de rede viram aviso com semDado', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect(await carregarDisparosLista(CHAVE)).toEqual({ data: [], semDado: true, erro: 'Sem permissão para ler este dashboard.' });
    mocks.rpc.mockRejectedValueOnce(new Error('rede'));
    const r = await carregarDisparosCanais(CHAVE);
    expect(r.semDado).toBe(true);
    expect(r.erro).toBeTruthy();
  });

  it('leitura que não volta no tempo limite vira falha com aviso', async () => {
    vi.useFakeTimers();
    mocks.rpc.mockReturnValue(new Promise(() => {}));
    const leitura = carregarDisparosLista(CHAVE, 1000);
    await vi.advanceTimersByTimeAsync(1000);
    expect(await leitura).toEqual({ data: [], semDado: true, erro: 'Os disparos demoraram a responder. Os últimos dados disponíveis foram mantidos.' });
  });
});
