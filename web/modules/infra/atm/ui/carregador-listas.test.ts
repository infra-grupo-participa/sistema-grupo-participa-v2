import { describe, expect, it, vi } from 'vitest';
import type { Resultado } from '../infrastructure/atm-data';
import { chaveListaAtm, criarCarregadorListasAtm, estadoAposLeitura, LISTA_CARREGANDO } from './carregador-listas';

const ok = (data: number[]): Resultado<number[]> => ({ data, semDado: false, erro: null });
const falha = (erro: string): Resultado<number[]> => ({ data: [], semDado: true, erro });
function adiado<T>() {
  let resolver!: (v: T) => void;
  const promessa = new Promise<T>((r) => { resolver = r; });
  return { promessa, resolver };
}
const AGORA = new Date('2026-10-13T22:00:00Z');

describe('carregador das listas dos modais (bug do modal de leads zerado)', () => {
  it('antes da primeira leitura o estado é CARREGANDO, nunca lista vazia nem indisponível', () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    const e = c.estado<number>('k');
    expect(e).toBe(LISTA_CARREGANDO);
    expect(e.fase).toBe('carregando');
    expect(e.data).toBeNull();
  });

  it('sucesso: pronto com a lista e a hora da leitura', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => ok([1, 2, 3]));
    expect(c.estado('k')).toEqual({ fase: 'pronto', data: [1, 2, 3], erro: null, lidoEm: AGORA, revalidando: false });
  });

  it('vazio honesto: lista vazia lida com sucesso é "pronto" com [] (não é erro nem indisponível)', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => ok([]));
    expect(c.estado('k')).toMatchObject({ fase: 'pronto', data: [] });
  });

  it('erro sem lista anterior: fase erro com a mensagem da leitura', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => falha('Não foi possível carregar os dados agora.'));
    expect(c.estado('k')).toMatchObject({ fase: 'erro', data: null, erro: 'Não foi possível carregar os dados agora.' });
  });

  it('exceção na leitura também vira erro (não trava em carregando)', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => { throw new Error('rede'); });
    expect(c.estado('k').fase).toBe('erro');
  });

  it('PGRST202: só aqui a fase é naoPublicada', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => ({ data: [], semDado: true, erro: null, naoPublicada: true }));
    expect(c.estado('k')).toMatchObject({ fase: 'naoPublicada', data: null });
  });

  it('42501 limpa a lista anterior (dado pessoal não fica na tela sem permissão)', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => ok([1]));
    await c.carregar('k', async () => ({ data: [], semDado: true, erro: 'Sem permissão para ler este dashboard.', semPermissao: true }));
    expect(c.estado('k')).toMatchObject({ fase: 'semPermissao', data: null });
  });

  it('cache: reabrir mostra a última lista na hora, marca revalidando e troca quando a releitura chega', async () => {
    let t = 0;
    const c = criarCarregadorListasAtm(() => new Date(AGORA.getTime() + (t++) * 1000));
    await c.carregar('k', async () => ok([1, 2]));
    const d = adiado<Resultado<number[]>>();
    const releitura = c.carregar('k', () => d.promessa);
    expect(c.estado('k')).toMatchObject({ fase: 'pronto', data: [1, 2], revalidando: true });
    d.resolver(ok([1, 2, 3]));
    await releitura;
    expect(c.estado('k')).toMatchObject({ fase: 'pronto', data: [1, 2, 3], revalidando: false });
  });

  it('releitura que falha mantém a última lista, com o erro e a hora antiga', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    await c.carregar('k', async () => ok([1, 2]));
    await c.carregar('k', async () => falha('A lista demorou a responder. Os últimos dados disponíveis foram mantidos.'));
    expect(c.estado('k')).toEqual({ fase: 'pronto', data: [1, 2], erro: 'A lista demorou a responder. Os últimos dados disponíveis foram mantidos.', lidoEm: AGORA, revalidando: false });
  });

  it('não pede duas vezes a mesma chave enquanto a leitura está em curso', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    const d = adiado<Resultado<number[]>>();
    const ler = vi.fn(() => d.promessa);
    const p1 = c.carregar('k', ler);
    const p2 = c.carregar('k', ler);
    expect(ler).toHaveBeenCalledTimes(1);
    d.resolver(ok([7]));
    await Promise.all([p1, p2]);
    expect(c.estado('k').data).toEqual([7]);
  });

  it('troca de período: chave nova começa carregando; a resposta atrasada do período antigo não invade o novo', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    const kEvento = chaveListaAtm('dados_atm_leads', 'atm-x', { p_de: null, p_ate: null }, true);
    const kHoje = chaveListaAtm('dados_atm_leads', 'atm-x', { p_de: '2026-10-13', p_ate: '2026-10-13' }, true);
    expect(kEvento).not.toBe(kHoje);
    const lento = adiado<Resultado<number[]>>();
    const pEvento = c.carregar(kEvento, () => lento.promessa);
    const pHoje = c.carregar(kHoje, async () => ok([1]));
    expect(c.estado(kEvento).fase).toBe('carregando');
    await pHoje;
    lento.resolver(ok([1, 2, 3]));
    await pEvento;
    expect(c.estado(kHoje).data).toEqual([1]);
    expect(c.estado(kEvento).data).toEqual([1, 2, 3]);
  });

  it('a chave separa incluir teste (master) de sem teste', () => {
    expect(chaveListaAtm('dados_atm_leads', 'atm-x', null, true)).not.toBe(chaveListaAtm('dados_atm_leads', 'atm-x', null, false));
  });

  it('avisa os inscritos a cada mudança e deixa de avisar depois de sair', async () => {
    const c = criarCarregadorListasAtm(() => AGORA);
    const fn = vi.fn();
    const sair = c.inscrever(fn);
    await c.carregar('k', async () => ok([1]));
    const chamadas = fn.mock.calls.length;
    expect(chamadas).toBeGreaterThan(0);
    sair();
    await c.carregar('k', async () => ok([2]));
    expect(fn).toHaveBeenCalledTimes(chamadas);
  });

  it('estadoAposLeitura: sem mensagem de erro numa falha, usa uma mensagem padrão (nunca vazio calado)', () => {
    expect(estadoAposLeitura(undefined, { data: [], semDado: true, erro: null }, AGORA)).toMatchObject({ fase: 'erro', erro: 'Não foi possível carregar os dados agora.' });
  });
});
