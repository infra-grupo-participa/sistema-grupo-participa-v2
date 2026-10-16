import { beforeEach, describe, expect, it, vi } from 'vitest';
import { respostaExemplo } from '../domain/relatorio-miami.fixture';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), abortSignal: vi.fn(), log: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc: mocks.rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: mocks.log }));

import { carregarRelatorioMiami, TIMEOUT_RELATORIO_MS } from './relatorio-miami-data';

const responde = (resposta: unknown) => { mocks.abortSignal.mockResolvedValue(resposta); mocks.rpc.mockReturnValue({ abortSignal: mocks.abortSignal }); };

describe('carregarRelatorioMiami', () => {
  beforeEach(() => { mocks.rpc.mockReset(); mocks.abortSignal.mockReset(); mocks.log.mockReset(); });

  it('primeira leitura chama a RPC só com a chave e com timeout', async () => {
    responde({ data: JSON.parse(JSON.stringify(respostaExemplo())), error: null });
    const r = await carregarRelatorioMiami('clinica-miami-2026-12', null);
    expect(mocks.rpc).toHaveBeenCalledWith('dados_miami_relatorio', { p_chave: 'clinica-miami-2026-12' });
    expect(mocks.abortSignal).toHaveBeenCalledTimes(1);
    expect(mocks.abortSignal.mock.calls[0][0]).toBeInstanceOf(AbortSignal);
    expect(TIMEOUT_RELATORIO_MS).toBe(15_000);
    expect(r).toMatchObject({ erro: null, permanente: false });
    expect(r.data?.md5).toBe('md5-a');
  });

  it('manda o md5 da cópia que a tela já tem', async () => {
    responde({ data: { ...respostaExemplo({ igual: true, conteudo: null }) }, error: null });
    const r = await carregarRelatorioMiami('clinica-miami-2026-12', 'md5-a');
    expect(mocks.rpc).toHaveBeenCalledWith('dados_miami_relatorio', { p_chave: 'clinica-miami-2026-12', p_md5: 'md5-a' });
    expect(r.data).toMatchObject({ igual: true, conteudo: null });
  });

  it('função ainda não aplicada (PGRST202) vira erro permanente com mensagem clara, sem lançar', async () => {
    responde({ data: null, error: { code: 'PGRST202' } });
    const r = await carregarRelatorioMiami('clinica-miami-2026-12', null);
    expect(r).toEqual({ data: null, erro: 'Esta função ainda não está no banco. Avise quem cuida do sistema.', permanente: true });
  });

  it('sem acesso (42501) é permanente; erro desconhecido não é', async () => {
    responde({ data: null, error: { code: '42501' } });
    expect(await carregarRelatorioMiami('k', null)).toMatchObject({ erro: 'Você não tem acesso a este dashboard.', permanente: true });
    responde({ data: null, error: { code: '57014' } });
    expect(await carregarRelatorioMiami('k', null)).toMatchObject({ erro: 'Não foi possível carregar agora.', permanente: false });
  });

  it('falha de rede ou timeout que lança vira erro tratado, não exceção', async () => {
    mocks.abortSignal.mockRejectedValue(new Error('rede'));
    mocks.rpc.mockReturnValue({ abortSignal: mocks.abortSignal });
    expect(await carregarRelatorioMiami('k', null)).toEqual({ data: null, erro: 'Não foi possível carregar agora.', permanente: false });
  });

  it('resposta fora do contrato vira erro, nunca dado', async () => {
    responde({ data: { disponivel: true, conteudo: { versao: 9 } }, error: null });
    expect(await carregarRelatorioMiami('k', null)).toEqual({ data: null, erro: 'A resposta do banco veio em formato inesperado.', permanente: false });
  });

  it('não registra dado pessoal no log', async () => {
    responde({ data: null, error: { code: 'PGRST202', message: 'x@y.com' } });
    await carregarRelatorioMiami('k', null);
    expect(mocks.log).toHaveBeenCalledWith('dados_miami_relatorio', { message: 'PGRST202' });
  });
});
