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
