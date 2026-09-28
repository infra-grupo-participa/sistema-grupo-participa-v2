import { describe, expect, it, vi } from 'vitest';
import { criarCacheListasSemCard, listasVisiveis, type ListaSemCard } from './carregar-listas-sem-card';

function montar() {
  const repo = {
    loadProgramaSemCard: vi.fn(async (f: 'HM' | 'AURUM') => [{ email: `${f}@x.com` }] as never),
    loadAssinaturaHMSemCard: vi.fn(async () => [{ pessoa_chave: 'p1' }] as never),
  };
  const recebidas: ListaSemCard[] = [];
  const cache = criarCacheListasSemCard(repo, (l) => { recebidas.push(l); });
  const familias = () => repo.loadProgramaSemCard.mock.calls.map(([f]) => f);
  return { repo, cache, recebidas, familias };
}
const tick = () => new Promise((r) => setTimeout(r, 0));

describe('listasVisiveis', () => {
  it('HM mostra Programa HM e mensalidade; Aurum só Programa Aurum; fora do board ou no Diamante, nada', () => {
    expect(listasVisiveis('board', 'HM', false)).toEqual(['programa_HM', 'assinatura_HM']);
    expect(listasVisiveis('board', 'AURUM', false)).toEqual(['programa_AURUM']);
    expect(listasVisiveis('board', 'HM', true)).toEqual([]);
    expect(listasVisiveis('faturamento', 'AURUM', false)).toEqual([]);
  });
});

describe('cache das listas sem card', () => {
  it('abrir o board (HM visível) sem visitar Aurum não chama loadProgramaSemCard("AURUM")', async () => {
    const { repo, cache, familias } = montar();
    cache.garantir(listasVisiveis('board', 'HM', false));
    await tick();
    expect(familias()).toEqual(['HM']);
    expect(repo.loadAssinaturaHMSemCard).toHaveBeenCalledTimes(1);
  });

  it('visitar Aurum 2× (voltando ao HM no meio) chama Aurum 1× e não repete o HM', async () => {
    const { repo, cache, familias } = montar();
    for (const p of ['HM', 'AURUM', 'HM', 'AURUM'] as const) cache.garantir(listasVisiveis('board', p, false));
    await tick();
    expect(familias().filter((f) => f === 'AURUM')).toHaveLength(1);
    expect(familias().filter((f) => f === 'HM')).toHaveLength(1);
    expect(repo.loadAssinaturaHMSemCard).toHaveBeenCalledTimes(1);
  });

  it('recarregar o board: invalida e recarrega só o visível; Aurum já visitado recarrega na próxima visita', async () => {
    const { cache, familias } = montar();
    cache.garantir(listasVisiveis('board', 'HM', false));
    cache.garantir(listasVisiveis('board', 'AURUM', false));
    cache.invalidar();
    cache.garantir(listasVisiveis('board', 'HM', false)); // visível na hora do recarregar
    await tick();
    expect(familias()).toEqual(['HM', 'AURUM', 'HM']);
    cache.garantir(listasVisiveis('board', 'AURUM', false));
    expect(familias()).toEqual(['HM', 'AURUM', 'HM', 'AURUM']);
  });

  it('resposta que chega depois de invalidar é descartada; falha vira lista vazia', async () => {
    const { repo, cache, recebidas } = montar();
    cache.garantir(['programa_HM']);
    cache.invalidar();
    await tick();
    expect(recebidas).toEqual([]);
    repo.loadAssinaturaHMSemCard.mockRejectedValueOnce(new Error('rede'));
    const dados: unknown[] = [];
    const c2 = criarCacheListasSemCard(repo, (_l, d) => { dados.push(d); });
    c2.garantir(['assinatura_HM']);
    await tick();
    expect(dados).toEqual([[]]);
  });
});
