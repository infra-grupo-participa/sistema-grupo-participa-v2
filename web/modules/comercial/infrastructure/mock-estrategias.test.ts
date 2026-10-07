import { describe, expect, it } from 'vitest';
import { MODELO_PROPRIA_HOLDING, MockEstrategiasRepository } from './mock-estrategias';

const novo = { titulo: 'Pedido teste', objetivo: 'Objetivo teste', publico: '', filtros: MODELO_PROPRIA_HOLDING.filtros,
  modelo: MODELO_PROPRIA_HOLDING.chave, linha: 'sv' as const, oferta: '', prazo: null, prioridade: 'media' as const, observacoes: '' };

describe('demonstração das Estratégias (mesmas regras do banco)', () => {
  it('solicitante sem ser gestor: pede, vê prévia sem amostra, não muda situação nem transforma', async () => {
    const r = new MockEstrategiasRepository({ solicitar: true, gestor: false });
    const s = await r.salvar(novo);
    expect(s.ok).toBe(true);
    const p = await r.previa(MODELO_PROPRIA_HOLDING.filtros);
    expect(p.previa!.total).toBeGreaterThan(0);
    expect(p.previa!.amostra).toEqual([]);
    expect((await r.mudarSituacao(s.id!, 'em_analise')).msg).toBe('Só o gestor comercial muda a situação.');
    expect((await r.transformar(s.id!, 'fila')).msg).toBe('Só o gestor comercial transforma em ação.');
  });

  it('gestor: amostra mascarada, transforma uma vez, prévia seguinte tira quem já está na ação, recusa exige motivo', async () => {
    const r = new MockEstrategiasRepository();
    const [p1] = await r.pedidos();
    const prev = (await r.previa(p1.filtros)).previa!;
    expect(prev.amostra.length).toBeGreaterThan(0);
    expect(prev.amostra.every((a) => a.email?.includes('***'))).toBe(true);
    const t = await r.transformar(p1.id, 'fila');
    expect(t.ok).toBe(true);
    expect(t.pessoas).toBe(prev.total);
    expect((await r.transformar(p1.id, 'fila')).msg).toBe('Este pedido já virou ação.');
    expect((await r.previa(p1.filtros)).previa!.excluidos.outraAcao).toBe(prev.total);
    const d = await r.pedido(p1.id);
    expect(d?.situacao).toBe('em_execucao');
    expect(d?.placar?.naLista).toBe(prev.total);
    const s = await r.salvar({ ...novo, titulo: 'Outro pedido' });
    expect((await r.mudarSituacao(s.id!, 'recusada', '')).msg).toBe('Diga o motivo da recusa.');
    expect((await r.mudarSituacao(s.id!, 'recusada', 'Fora do foco')).ok).toBe(true);
    expect((await r.mudarSituacao(s.id!, 'em_analise')).msg).toBe('Mudança de situação não permitida.');
  });
});
