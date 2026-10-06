// Leitura em lotes de crm_contatos (ajuste rápido de 06/10/2026): páginas de 500, teto de 10.000 com erro claro.
// O cliente Supabase não é criado: `rpc` é trocado por um falso que conta as chamadas.
import { describe, expect, it, vi } from 'vitest';
import { SupabaseComercialRepository } from './supabase-comercial.repository';

const contato = (i: number) => ({
  id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, nome: `Pessoa ${i}`, email: null, telefone: null,
  cidade: null, uf: null, perfil: null, atuaComHolding: null, donoId: null, tags: [], utm: null, score: null,
  ehAluno: false, optOut: false, criadoEm: '2026-10-06T09:40:00+00:00',
});

/** Base falsa com `total` contatos; responde como a RPC (limite, offset, temMais). */
function repoCom(total: number) {
  const r = new SupabaseComercialRepository();
  const rpc = vi.fn(async (fn: string, args?: Record<string, unknown>) => {
    if (fn === 'crm_jornada') return [];
    const lim = Number(args?.p_limite), off = Number(args?.p_offset);
    const fim = Math.min(off + lim, total);
    return { itens: Array.from({ length: Math.max(fim - off, 0) }, (_, k) => contato(off + k)), temMais: fim < total };
  });
  (r as unknown as { rpc: typeof rpc }).rpc = rpc;
  return { r, rpc };
}

describe('contatos(): leitura em lotes de 500', () => {
  it('2.648 contatos (lista do gestor em 06/10) vêm em 6 chamadas de 500', async () => {
    const { r, rpc } = repoCom(2648);
    const lista = await r.contatos();
    expect(lista).toHaveLength(2648);
    expect(rpc).toHaveBeenCalledTimes(6);
    for (const [fn, args] of rpc.mock.calls) {
      expect(fn).toBe('crm_contatos');
      expect(args).toMatchObject({ p_busca: null, p_limite: 500 });
    }
    expect(rpc.mock.calls.map(([, a]) => a?.p_offset)).toEqual([0, 500, 1000, 1500, 2000, 2500]);
  });

  it('exatamente 10.000 contatos ainda carregam', async () => {
    const { r, rpc } = repoCom(10_000);
    expect(await r.contatos()).toHaveLength(10_000);
    expect(rpc).toHaveBeenCalledTimes(20);
  });

  it('acima de 10.000 para com mensagem clara (não corta calado)', async () => {
    const { r, rpc } = repoCom(10_001);
    await expect(r.contatos()).rejects.toThrow('Lista grande demais para carregar de uma vez (crm_contatos: mais de 10.000 contatos).');
    expect(rpc).toHaveBeenCalledTimes(20);
  });
});

describe('jornada(): uma pessoa por chamada', () => {
  it('busca só o contato pedido', async () => {
    const { r, rpc } = repoCom(0);
    await r.jornada('abc');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('crm_jornada', { p_pessoa: 'abc' });
  });
});

describe('buscarContatos(): busca no servidor (20261006191824)', () => {
  it('manda o termo para crm_contatos numa chamada só, até 50', async () => {
    const { r, rpc } = repoCom(3);
    const achados = await r.buscarContatos('  maria  ');
    expect(achados).toHaveLength(3);
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('crm_contatos', { p_busca: 'maria', p_limite: 50, p_offset: 0 });
  });

  it('menos de 3 letras não chama o banco', async () => {
    const { r, rpc } = repoCom(3);
    expect(await r.buscarContatos('ma')).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
  });
});

// ── Migration 20261006m: lista paginada, resumo e contatos por id, com volta ao caminho antigo ──

type Resposta = { data: unknown; error: { code?: string; message?: string } | null };
const AUSENTE = { data: null, error: { code: 'PGRST202', message: 'Could not find the function' } };

/** Troca a chamada crua: `responde(fn, args)` decide cada resposta; conta todas as chamadas. */
function repoBruto(responde: (fn: string, args: Record<string, unknown>) => Resposta) {
  const r = new SupabaseComercialRepository();
  const bruto = vi.fn(async (fn: string, args: Record<string, unknown> = {}) => responde(fn, args));
  (r as unknown as { bruto: typeof bruto }).bruto = bruto;
  return { r, bruto };
}

/** Banco antigo (sem as RPCs novas): crm_contatos em lotes, crm_negocios, crm_vendedores. */
function bancoAntigo(total: number, extra: (fn: string, args: Record<string, unknown>) => Resposta | null = () => null) {
  return (fn: string, args: Record<string, unknown>): Resposta => {
    const e = extra(fn, args);
    if (e) return e;
    if (fn === 'crm_contatos_pagina' || fn === 'crm_contatos_resumo' || fn === 'crm_contatos_por_ids') return AUSENTE;
    if (fn === 'crm_contatos') {
      const lim = Number(args.p_limite), off = Number(args.p_offset);
      const fim = Math.min(off + lim, total);
      return { data: { itens: Array.from({ length: Math.max(fim - off, 0) }, (_, k) => contato(off + k)), temMais: fim < total }, error: null };
    }
    if (fn === 'crm_negocios' || fn === 'crm_vendedores') return { data: [], error: null };
    return { data: null, error: { code: 'XX000', message: `inesperado: ${fn}` } };
  };
}

describe('contatosPagina(): uma página do servidor', () => {
  it('manda filtros, ordem e página para crm_contatos_pagina numa chamada só', async () => {
    const { r, bruto } = repoBruto(() => ({ data: { itens: [contato(1)], total: 2649 }, error: null }));
    const p = await r.contatosPagina({
      busca: ' maria ', dono: 'sem_dono', perfil: 'sem', uf: 'SP', tags: ['a'], optOut: true, soAlunos: false,
      ordem: 'ultima', dir: 'desc', limite: 50, offset: 100,
    });
    expect(p.total).toBe(2649);
    expect(p.itens).toHaveLength(1);
    expect(bruto).toHaveBeenCalledTimes(1);
    expect(bruto).toHaveBeenCalledWith('crm_contatos_pagina', {
      p_busca: 'maria', p_dono: 'sem_dono', p_perfil: 'sem', p_uf: 'SP', p_tags: ['a'], p_opt_out: true, p_so_alunos: false,
      p_ordem: 'ultima', p_dir: 'desc', p_limite: 50, p_offset: 100,
    });
  });

  it('sem a RPC (migration não aplicada): cai na lista antiga e pagina aqui; não tenta a RPC de novo', async () => {
    const { r, bruto } = repoBruto(bancoAntigo(2648));
    const p1 = await r.contatosPagina({ limite: 50, offset: 0 });
    expect(p1.total).toBe(2648);
    expect(p1.itens).toHaveLength(50);
    const chamadasLista = bruto.mock.calls.filter(([fn]) => fn === 'crm_contatos').length;
    expect(chamadasLista).toBe(6);
    // 2ª página: nem tenta a RPC ausente, nem baixa a lista de novo (30 s em memória)
    const p2 = await r.contatosPagina({ limite: 50, offset: 50 });
    expect(p2.itens[0].id).not.toBe(p1.itens[0].id);
    expect(bruto.mock.calls.filter(([fn]) => fn === 'crm_contatos_pagina')).toHaveLength(1);
    expect(bruto.mock.calls.filter(([fn]) => fn === 'crm_contatos')).toHaveLength(6);
  });

  it('outro erro da RPC nova não cai no caminho antigo: vira erro na tela', async () => {
    const { r } = repoBruto(() => ({ data: null, error: { code: '42501', message: 'Sem acesso ao Comercial.' } }));
    await expect(r.contatosPagina({})).rejects.toThrow('Sem acesso ao Comercial.');
  });
});

describe('contatosResumo()', () => {
  it('lê crm_contatos_resumo', async () => {
    const { r, bruto } = repoBruto(() => ({ data: { total: 2649, semDono: 1801, optOut: 0, alunos: 568, ufs: ['SP'], tags: [] }, error: null }));
    expect(await r.contatosResumo()).toEqual({ total: 2649, semDono: 1801, optOut: 0, alunos: 568, ufs: ['SP'], tags: [] });
    expect(bruto).toHaveBeenCalledWith('crm_contatos_resumo', {});
  });

  it('sem a RPC: conta a lista antiga', async () => {
    const { r } = repoBruto(bancoAntigo(30));
    expect((await r.contatosResumo()).total).toBe(30);
  });
});

describe('contatosPorIds(): só os contatos pedidos', () => {
  it('sem ids não chama o banco; ids repetidos vão uma vez só', async () => {
    const { r, bruto } = repoBruto(() => ({ data: { itens: [contato(1)] }, error: null }));
    expect(await r.contatosPorIds([])).toEqual([]);
    expect(bruto).not.toHaveBeenCalled();
    await r.contatosPorIds(['a', 'a', 'b']);
    expect(bruto).toHaveBeenCalledWith('crm_contatos_por_ids', { p_ids: ['a', 'b'] });
  });

  it('mais de 1.000 ids vão em lotes de 1.000', async () => {
    const { r, bruto } = repoBruto(() => ({ data: { itens: [] }, error: null }));
    await r.contatosPorIds(Array.from({ length: 2500 }, (_, i) => `id-${i}`));
    expect(bruto.mock.calls.map(([, a]) => (a as { p_ids: string[] }).p_ids.length)).toEqual([1000, 1000, 500]);
  });

  it('sem a RPC: filtra a lista antiga', async () => {
    const { r } = repoBruto(bancoAntigo(10));
    const achados = await r.contatosPorIds([contato(3).id, contato(7).id, 'fora-da-lista']);
    expect(achados.map((c) => c.id)).toEqual([contato(3).id, contato(7).id]);
  });
});

describe('duplicadosDe(): aviso da ficha', () => {
  it('pede os duplicados ao banco e depois só os contatos achados', async () => {
    const dup = contato(2).id;
    const { r, bruto } = repoBruto((fn, args) => {
      if (args.p_duplicados) return { data: { itens: [{ ...contato(1), duplicados: [dup] }] }, error: null };
      return { data: { itens: [contato(2)] }, error: null };
    });
    const achados = await r.duplicadosDe(contato(1).id);
    expect(achados.map((c) => c.id)).toEqual([dup]);
    expect(bruto).toHaveBeenNthCalledWith(1, 'crm_contatos_por_ids', { p_ids: [contato(1).id], p_duplicados: true });
    expect(bruto).toHaveBeenNthCalledWith(2, 'crm_contatos_por_ids', { p_ids: [dup] });
  });

  it('sem duplicado: uma chamada só', async () => {
    const { r, bruto } = repoBruto(() => ({ data: { itens: [{ ...contato(1), duplicados: [] }] }, error: null }));
    expect(await r.duplicadosDe(contato(1).id)).toEqual([]);
    expect(bruto).toHaveBeenCalledTimes(1);
  });
});

describe('negocios(filtro): filtro no banco', () => {
  it('contato, funil e status viram p_pessoa, p_funil e p_status', async () => {
    const { r, bruto } = repoBruto(() => ({ data: [], error: null }));
    await r.negocios({ contatoId: 'p1', funilId: 'f1', status: 'aberto' });
    expect(bruto).toHaveBeenCalledWith('crm_negocios', { p_pessoa: 'p1', p_funil: 'f1', p_status: 'aberto', p_limite: 2000, p_offset: 0 });
  });

  it('sem filtro: como antes (só página)', async () => {
    const { r, bruto } = repoBruto(() => ({ data: [], error: null }));
    await r.negocios();
    expect(bruto).toHaveBeenCalledWith('crm_negocios', { p_limite: 2000, p_offset: 0 });
  });
});
