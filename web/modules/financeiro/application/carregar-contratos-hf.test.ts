// Cache da sub-aba Contratos (z93): quantas chamadas, a sonda que esconde a sub-aba sem a z93, falha não guardada e a
// invalidação depois de gravar. Repositório falso — prova a contagem de chamadas do front, não o banco vivo.
import { describe, expect, it, vi } from 'vitest';
import { RecursoAusenteError } from './ports';
import { criarCacheContratosHF, entradaNovaParcela, repoColagemNoContrato } from './carregar-contratos-hf';
import { formDeInformado, TIPO_CONTRATO, type InformadoEntrada } from '../domain/recebimentos-informados';

const SYNC = { ultima_em: null, fichas: null, baixas: null, desfeitas: null, erros: null, mensagem: null };
const repoFalso = (o: { mensal?: () => Promise<never[]>; pags?: () => Promise<never[]> } = {}) => ({
  loadContratosHfMensal: vi.fn(o.mensal ?? (async () => [])),
  loadContratosHfPagamentos: vi.fn(o.pags ?? (async () => [])),
  loadContratosHfSyncStatus: vi.fn(async () => SYNC),
});

describe('cache dos contratos HF', () => {
  it('sonda: 1 chamada (pagamentos, todos — não só a fila); repetir e ler os pagamentos não consulta de novo', async () => {
    const repo = repoFalso();
    const c = criarCacheContratosHF(repo);
    expect(c.disponibilidade()).toBe('desconhecida');
    const [a, b] = await Promise.all([c.sondar(), c.sondar()]);
    expect([a, b]).toEqual(['sim', 'sim']);
    await c.pagamentos();
    await c.sondar();
    expect(repo.loadContratosHfPagamentos).toHaveBeenCalledTimes(1);
    expect(repo.loadContratosHfPagamentos).toHaveBeenCalledWith(false);
    expect(repo.loadContratosHfMensal).not.toHaveBeenCalled(); // a grade só quando a sub-aba abre
    expect(repo.loadContratosHfSyncStatus).not.toHaveBeenCalled(); // o status também
  });

  it('status da sincronização: 1 chamada; escrever (invalidar) não o esquece — só o cron o muda', async () => {
    const repo = repoFalso();
    const c = criarCacheContratosHF(repo);
    await Promise.all([c.sync(), c.sync()]);
    c.invalidar();
    await c.sync();
    expect(c.syncLido()).toEqual(SYNC);
    expect(repo.loadContratosHfSyncStatus).toHaveBeenCalledTimes(1);
  });

  it('função ausente (z93 não aplicada): "nao", guardado — não consulta a cada volta à aba', async () => {
    const repo = repoFalso({ pags: async () => { throw new RecursoAusenteError(); } });
    const c = criarCacheContratosHF(repo);
    expect(await c.sondar()).toBe('nao');
    expect(await c.sondar()).toBe('nao');
    expect(c.disponibilidade()).toBe('nao');
    expect(repo.loadContratosHfPagamentos).toHaveBeenCalledTimes(1);
  });

  it('outra falha (rede, permissão): a sub-aba aparece ("sim") e a falha não fica guardada', async () => {
    let n = 0;
    const repo = repoFalso({ pags: async () => { n += 1; if (n === 1) throw new Error('rede'); return []; } });
    const c = criarCacheContratosHF(repo);
    expect(await c.sondar()).toBe('sim');
    expect(c.pagamentosLidos()).toBeUndefined();
    await expect(c.pagamentos()).resolves.toEqual([]);
    expect(repo.loadContratosHfPagamentos).toHaveBeenCalledTimes(2);
  });

  it('grade: 1 chamada com o período padrão do banco; ausente na grade também marca "nao"', async () => {
    const repo = repoFalso();
    const c = criarCacheContratosHF(repo);
    await c.grade(); await c.grade();
    expect(repo.loadContratosHfMensal).toHaveBeenCalledTimes(1);
    expect(repo.loadContratosHfMensal).toHaveBeenCalledWith(null, null);
    const c2 = criarCacheContratosHF(repoFalso({ mensal: async () => { throw new RecursoAusenteError(); } }));
    await expect(c2.grade()).rejects.toBeInstanceOf(RecursoAusenteError);
    expect(c2.disponibilidade()).toBe('nao');
  });

  it('invalidar(): próxima leitura consulta; resposta que estava em voo não sobrescreve', async () => {
    let solta: (v: never[]) => void = () => {};
    let n = 0;
    const repo = repoFalso({ mensal: () => { n += 1; return n === 1 ? new Promise<never[]>((r) => { solta = r; }) : Promise.resolve([]); } });
    const c = criarCacheContratosHF(repo);
    const velha = c.grade();
    c.invalidar();
    solta([]);
    await velha;
    expect(c.gradeLida()).toBeUndefined(); // a velha não entrou no cache
    await c.grade();
    expect(repo.loadContratosHfMensal).toHaveBeenCalledTimes(2);
    expect(c.gradeLida()).toEqual([]);
  });
});

describe('colar da planilha dentro da ficha', () => {
  const linha = (p: Partial<InformadoEntrada>): InformadoEntrada => ({
    data_prevista: '2026-10-10', cliente: 'Ana', tipo: TIPO_CONTRATO, valor: 1000, via_hotmart: false, produtos: [],
    acordo_desde: null, ...p,
  });

  it('liga cada linha ao contrato (contrato_id) e repassa simular; nome igual ao da ficha não pergunta', async () => {
    const importarInformados = vi.fn(async () => ({ ok: true, linhas: [] }));
    const confirmar = vi.fn(async () => true);
    const r = repoColagemNoContrato({ importarInformados }, 'c1', 'ANA', confirmar);
    await r.importarInformados([linha({}), linha({ data_prevista: '2026-11-10' })], true);
    expect(importarInformados).toHaveBeenCalledWith([
      expect.objectContaining({ contrato_id: 'c1', data_prevista: '2026-10-10' }),
      expect.objectContaining({ contrato_id: 'c1', data_prevista: '2026-11-10' }),
    ], true);
    expect(confirmar).not.toHaveBeenCalled();
  });

  it('nome diferente do da ficha: pergunta ANTES de enviar; "não" = nada vai ao banco', async () => {
    const importarInformados = vi.fn(async () => ({ ok: true, linhas: [] }));
    const confirmar = vi.fn(async () => false);
    const r = repoColagemNoContrato({ importarInformados }, 'c1', 'Ana', confirmar);
    expect(await r.importarInformados([linha({}), linha({ cliente: 'Bia' })], true)).toMatchObject({ ok: false, linhas: [] });
    expect(confirmar).toHaveBeenCalledWith(['Bia']);
    expect(importarInformados).not.toHaveBeenCalled();
  });

  it('confirmado: envia (o banco grava com o nome da ficha); conferir → gravar não pergunta de novo o mesmo nome', async () => {
    const importarInformados = vi.fn(async () => ({ ok: true, linhas: [] }));
    const confirmar = vi.fn(async () => true);
    const r = repoColagemNoContrato({ importarInformados }, 'c1', 'Ana', confirmar);
    await r.importarInformados([linha({ cliente: 'Bia' })], true);
    await r.importarInformados([linha({ cliente: ' bia ' })], false);
    expect(confirmar).toHaveBeenCalledTimes(1);
    expect(importarInformados).toHaveBeenCalledTimes(2);
    await r.importarInformados([linha({ cliente: 'Carla' })], false);
    expect(confirmar).toHaveBeenLastCalledWith(['Carla']);
  });

  it('linha que não é contrato: recusada sem perguntar e sem ir ao banco', async () => {
    const importarInformados = vi.fn(async () => ({ ok: true, linhas: [] }));
    const confirmar = vi.fn(async () => true);
    const r = repoColagemNoContrato({ importarInformados }, 'c1', 'Ana', confirmar);
    expect(await r.importarInformados([linha({ tipo: 'renovacao_aurum' })], true)).toMatchObject({ ok: false, linhas: [] });
    expect(confirmar).not.toHaveBeenCalled();
    expect(importarInformados).not.toHaveBeenCalled();
  });
});

describe('nova parcela na ficha', () => {
  it('reusa entradaDoFormulario, força o tipo contrato e acrescenta contrato_id', () => {
    const f = { ...formDeInformado(null, false), tipo: 'outro', cliente: 'Ana', data_prevista: '2026-10-10', valor: '1.000,00', contrato_assinado: 'S' as const };
    const r = entradaNovaParcela(f, 'c1', false);
    expect(r.erros).toEqual([]);
    expect(r.entrada).toMatchObject({ tipo: TIPO_CONTRATO, contrato_id: 'c1', valor: 1000, via_hotmart: false, contrato_assinado: true });
    expect(r.entrada).not.toHaveProperty('identificador1'); // sem gp_pode_ver_cpf: nunca vai
  });
  it('erro do formulário volta sem entrada', () => {
    expect(entradaNovaParcela(formDeInformado(null, true), 'c1', true).entrada).toBeNull();
  });
});
