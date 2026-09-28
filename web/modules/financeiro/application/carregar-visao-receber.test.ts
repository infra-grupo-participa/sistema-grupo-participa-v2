// Carga da Visão geral com repositório falso: quantas chamadas, em que ordem, e dado × erro separados.
import { describe, expect, it, vi } from 'vitest';
import { carregarVisaoReceber, SEMANAS_PREVISTO, visaoTemErro } from './carregar-visao-receber';
import { normalizarFoto } from '../domain/visao-receber';

const foto = (foto_em: string, dia: string) => normalizarFoto({ foto_em, dia, cenario: 'base', linhas: 1, soma_a_receber: 1 });
const F1 = foto('2026-09-28T12:00:00+00:00', '2026-09-28');
const F2 = foto('2026-10-05T09:11:00+00:00', '2026-10-05');

const repoCom = (fotos: unknown) => ({
  loadFotosReceber: vi.fn(async () => { if (fotos instanceof Error) throw fotos; return fotos as ReturnType<typeof foto>[]; }),
  loadPrevistoRealizado: vi.fn(async () => []),
  loadMudancasReceber: vi.fn(async () => []),
});

describe('carregarVisaoReceber', () => {
  it('1 foto (até a segunda 05/10): 2 chamadas, sem "o que mudou"', async () => {
    const repo = repoCom([F1]);
    const v = await carregarVisaoReceber(repo);
    expect(repo.loadFotosReceber).toHaveBeenCalledTimes(1);
    expect(repo.loadPrevistoRealizado).toHaveBeenCalledWith(SEMANAS_PREVISTO);
    expect(repo.loadMudancasReceber).not.toHaveBeenCalled();
    expect(v.comparacao).toBeNull();
    expect(v.mudancas).toBeNull();
    expect(visaoTemErro(v)).toBe(false);
  });
  it('2 fotos: 3 chamadas; mudanças da anterior para a mais recente', async () => {
    const repo = repoCom([F2, F1]);
    const v = await carregarVisaoReceber(repo);
    expect(repo.loadMudancasReceber).toHaveBeenCalledWith(F1.foto_em, F2.foto_em);
    expect(v.mudancas).toEqual({ dados: [], erro: null });
  });
  it('falha das fotos: erro na parte (nunca lista vazia), o previsto continua; tentar de novo pede só o que falhou', async () => {
    const repo = repoCom(new Error('Sem permissão para ver o financeiro.'));
    const v = await carregarVisaoReceber(repo);
    expect(v.fotos).toEqual({ dados: null, erro: 'Sem permissão para ver o financeiro.' });
    expect(v.previsto.dados).toEqual([]);
    expect(visaoTemErro(v)).toBe(true);
    repo.loadFotosReceber.mockResolvedValueOnce([F2, F1]);
    const v2 = await carregarVisaoReceber(repo, v);
    expect(repo.loadPrevistoRealizado).toHaveBeenCalledTimes(1); // não repetiu
    expect(repo.loadFotosReceber).toHaveBeenCalledTimes(2);
    expect(v2.comparacao?.recente.foto_em).toBe(F2.foto_em);
    expect(repo.loadMudancasReceber).toHaveBeenCalledTimes(1);
  });
  it('mudanças que já vieram para o mesmo par de fotos não são pedidas de novo', async () => {
    const repo = repoCom([F2, F1]);
    repo.loadPrevistoRealizado.mockRejectedValueOnce(new Error('x'));
    const v = await carregarVisaoReceber(repo);
    await carregarVisaoReceber(repo, v);
    expect(repo.loadMudancasReceber).toHaveBeenCalledTimes(1);
    expect(repo.loadPrevistoRealizado).toHaveBeenCalledTimes(2);
  });
});
