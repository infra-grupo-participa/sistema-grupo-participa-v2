import { describe, expect, it } from 'vitest';
import { argsRegra, mapOrigemDetalhada, mapPainelCatalogo } from './mapeamento-catalogacao';
import { mapContatos, mapOrigemContato, mapResumoContatos } from './mapeamento-supabase';
import { MockComercialRepository } from './mock-comercial.repository';

// Formato devolvido por public.crm_catalogo (20261007141044), com valores do ensaio de 07/10/2026.
const PAINEL = {
  podeEditar: true,
  regras: [{ id: 1, campo: 'ac_lista', operador: 'comeca', padrao: 'Patrimônio Brasil', projeto: 'seminario-conjunto-2026-11',
    projetoNome: 'Patrimônio Brasil 2026', valeDe: null, valeAte: null, prioridade: 100, ativo: true, nota: 'Listas 603, 609–612',
    atualizadoEm: '2026-10-07T15:00:00Z', contatos: 22 }],
  listasAc: [{ id: '603', nome: 'Patrimônio Brasil - Geral' }],
  projetos: [{ chave: 'seminario-conjunto-2026-11', nome: 'Patrimônio Brasil 2026', contatos: 24 }],
  resumo: { total: 2793, comProjeto: 1517, produtoSemProjeto: 1159, semNada: 117,
    motivos: { regra_sem_projeto: 116, sem_regra: 1046, sem_dado: 114 },
    porCanal: [{ canal: 'hotmart', total: 2074, comProjeto: 923 }, { canal: 'canal_novo', total: 1, comProjeto: 0 }],
    semProjetoPorLinha: [{ linha: 'ht', total: 513 }] },
  pendencias: [{ campo: 'hotmart_produto', valor: '1560865', nome: 'Holding Total', contatos: 484 }],
};

describe('mapPainelCatalogo', () => {
  it('mapeia o painel e cai em "sistema" com canal desconhecido', () => {
    const p = mapPainelCatalogo(PAINEL);
    expect(p.regras[0]).toMatchObject({ id: 1, campo: 'ac_lista', operador: 'comeca', projeto: 'seminario-conjunto-2026-11', contatos: 22 });
    expect(p.resumo.porCanal[1].canal).toBe('sistema');
    expect(p.resumo.motivos.sem_regra).toBe(1046);
    expect(p.pendencias[0]).toEqual({ campo: 'hotmart_produto', valor: '1560865', nome: 'Holding Total', contatos: 484 });
    expect(p.regras[0].tipo).toBe('projeto');
    expect(p.podeClassificar).toBe(true);
    const leitura = mapPainelCatalogo({ ...PAINEL, podeEditar: false, podeClassificar: true, regras: [{ ...PAINEL.regras[0], tipo: 'mql' }] });
    expect(leitura).toMatchObject({ podeEditar: false, podeClassificar: true, regras: [{ tipo: 'mql' }] });
  });
  it('formato fora do contrato vira erro (nunca painel zerado)', () => {
    expect(() => mapPainelCatalogo(null)).toThrow(/crm_catalogo/);
    expect(() => mapPainelCatalogo({ ...PAINEL, regras: null })).toThrow(/regras/);
    expect(() => mapPainelCatalogo({ ...PAINEL, regras: [{ ...PAINEL.regras[0], campo: 'xyz' }] })).toThrow(/campo/);
  });
});

describe('origem do contato', () => {
  it('crm_contato_origem: null = sem origem; detalhe sem as chaves', () => {
    expect(mapOrigemDetalhada(null)).toBeNull();
    const o = mapOrigemDetalhada({
      canal: 'clint', entrouEm: '2026-09-23T10:00:00Z', projeto: 'seminario-elaine-2026-09', projetoNome: null, motivo: 'regra',
      manual: false, linha: 'sv', podeDefinir: true, detalhe: { clint: { funil: 'Clint · MQLS' } },
      regra: { id: 8, campo: 'funil', operador: 'igual', padrao: 'Clint · MQLS' }, mqlDesde: '2026-10-07T12:00:00Z',
      mqlProjeto: 'seminario-conjunto-2026-11', mqlProjetoNome: 'Patrimônio Brasil 2026',
    });
    expect(o).toMatchObject({ mqlDesde: '2026-10-07T12:00:00Z', mqlProjeto: 'seminario-conjunto-2026-11', canal: 'clint', motivo: 'regra', regra: { id: 8, campo: 'funil' }, detalhe: { clint: { funil: 'Clint · MQLS' } } });
  });
  it('item da lista traz origem; ausente no banco antigo = campo ausente', () => {
    const base = { id: 'x', nome: 'N', criadoEm: '2026-10-01' };
    expect(mapContatos([base])[0]).not.toHaveProperty('origem');
    expect(mapContatos([{ ...base, origem: null }])[0].origem).toBeNull();
    expect(mapOrigemContato({ canal: 'activecampaign', entrouEm: 'e', projeto: null, projetoNome: null, linha: null }))
      .toEqual({ canal: 'activecampaign', entrouEm: 'e', projeto: null, projetoNome: null, linha: null });
  });
  it('resumo: canais/projetos só quando o banco manda', () => {
    const antigo = mapResumoContatos({ total: 1, semDono: 0, optOut: 0, alunos: 0, ufs: [], tags: [] });
    expect(antigo.canais).toBeUndefined();
    const novo = mapResumoContatos({ total: 1, semDono: 0, optOut: 0, alunos: 0, ufs: [], tags: [],
      canais: [{ canal: 'hotmart', total: 1 }], projetos: [{ chave: 'cnhf-2026-08', nome: null, total: 1 }], semProjeto: 0 });
    expect(novo).toMatchObject({ canais: [{ canal: 'hotmart', total: 1 }], projetos: [{ chave: 'cnhf-2026-08', nome: null, total: 1 }], semProjeto: 0 });
  });
  it('argumento da regra vai como p jsonb', () => {
    expect(argsRegra({ id: null, campo: 'ac_tag', operador: 'comeca', padrao: 'PB ', projeto: 'seminario-conjunto-2026-11',
      valeDe: null, valeAte: null, prioridade: 100, ativo: true, nota: null }).p)
      .toMatchObject({ id: null, campo: 'ac_tag', operador: 'comeca', padrao: 'PB ', projeto: 'seminario-conjunto-2026-11' });
  });
});

describe('demonstração', () => {
  it('lista com origem, filtro por canal/projeto e regra nova recataloga', async () => {
    const repo = new MockComercialRepository();
    const todos = await repo.contatosPagina({ limite: 200 });
    expect(todos.itens.every((c) => !!c.origem)).toBe(true);
    const ac = await repo.contatosPagina({ canal: 'activecampaign', limite: 200 });
    expect(ac.total).toBeGreaterThan(0);
    expect(ac.itens.every((c) => c.origem?.canal === 'activecampaign')).toBe(true);
    const antes = await repo.catalogo();
    const pend = antes.pendencias.find((p) => p.campo === 'hotmart_oferta' && p.valor === '30gjdp9b');
    expect(pend).toBeTruthy();
    const res = await repo.salvarRegraCatalogo({ id: null, campo: 'hotmart_oferta', operador: 'igual', padrao: '30gjdp9b',
      projeto: 'acelera-holding-2026-08', valeDe: null, valeAte: null, prioridade: 100, ativo: true, nota: null });
    expect(res.ok).toBe(true);
    const depois = await repo.catalogo();
    expect(depois.pendencias.some((p) => p.valor === '30gjdp9b')).toBe(false);
    expect(depois.resumo.comProjeto).toBe(antes.resumo.comProjeto + (pend?.contatos ?? 0));
    const so = await repo.contatosPagina({ projeto: 'acelera-holding-2026-08', limite: 200 });
    expect(so.total).toBe(pend?.contatos);
    const dup = await repo.salvarRegraCatalogo({ id: null, campo: 'hotmart_oferta', operador: 'igual', padrao: '30GJDP9B',
      projeto: 'x-projeto', valeDe: null, valeAte: null, prioridade: 100, ativo: true, nota: null });
    expect(dup).toMatchObject({ ok: false });
  });
  it('gestor fixa o projeto à mão e devolve às regras', async () => {
    const repo = new MockComercialRepository();
    const c = (await repo.contatosPagina({ limite: 1 })).itens[0];
    expect((await repo.definirProjetoContato(c.id, 'Black Friday')).ok).toBe(false);
    expect((await repo.definirProjetoContato(c.id, 'black-friday-2026-10')).ok).toBe(true);
    expect(await repo.origemContato(c.id)).toMatchObject({ projeto: 'black-friday-2026-10', motivo: 'manual', manual: true });
    expect((await repo.definirProjetoContato(c.id, null)).ok).toBe(true);
    expect((await repo.origemContato(c.id))?.manual).toBe(false);
  });
});
