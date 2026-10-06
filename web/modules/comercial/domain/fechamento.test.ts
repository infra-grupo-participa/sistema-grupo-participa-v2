import { describe, expect, it } from 'vitest';
import { calcularFechamento, mesmoDia } from './fechamento';
import type { Atividade, EventoTimeline, Negocio } from './types';

const dia = new Date('2026-10-05T19:00:00-03:00');
const hoje = (h: number) => new Date(`2026-10-05T${String(h).padStart(2, '0')}:00:00-03:00`).toISOString();
const ontem = new Date('2026-10-04T12:00:00-03:00').toISOString();

const neg = (p: Partial<Negocio>): Negocio => ({
  id: 'n', contatoId: 'c', produto: 'hm', origem: 'venda_ativa', funilId: 'f', campanhaId: null, etapaId: 'e', etapaNome: 'Qualificar', etapa: 'qualificar', status: 'aberto', donoId: 'marcos',
  valor: 30000, campos: {}, motivoPerda: null, criadoEm: ontem, etapaDesde: ontem, fechadoEm: null,
  proximaAtividade: { id: 'a', tipo: 'ligacao', titulo: 'x', venceEm: hoje(20) }, ultimaInteracaoEm: null, ...p,
});
const atv = (p: Partial<Atividade>): Atividade => ({
  id: 'a', negocioId: 'n', contatoId: 'c', donoId: 'marcos', tipo: 'whatsapp', titulo: 'x', venceEm: hoje(10),
  concluidaEm: null, resultado: null, cadenciaDia: null, ...p,
});

describe('mesmoDia', () => {
  it('compara no fuso de Brasília', () => {
    expect(mesmoDia('2026-10-06T01:30:00Z', dia)).toBe(true); // 22:30 do dia 5 em Brasília
    expect(mesmoDia(ontem, dia)).toBe(false);
    expect(mesmoDia(null, dia)).toBe(false);
  });
});

describe('calcularFechamento', () => {
  it('abordados = leads únicos com contato ativo concluído hoje', () => {
    const f = calcularFechamento([], [
      atv({ id: '1', contatoId: 'c1', concluidaEm: hoje(10) }),
      atv({ id: '2', contatoId: 'c1', tipo: 'ligacao', concluidaEm: hoje(11) }),
      atv({ id: '3', contatoId: 'c2', donoId: 'ronan', concluidaEm: hoje(12) }),
      atv({ id: '4', contatoId: 'c3', tipo: 'tarefa', concluidaEm: hoje(12) }),
      atv({ id: '5', contatoId: 'c4', concluidaEm: ontem }),
    ], [], dia);
    expect(f.total.abordados).toBe(2);
    expect(f.porVendedor.marcos.abordados).toBe(1);
    expect(f.porVendedor.ronan.abordados).toBe(1);
  });

  it('vendas e receita só com ganho fechado hoje, por produto', () => {
    const f = calcularFechamento([
      neg({ id: '1', status: 'ganho', etapa: 'fechado', fechadoEm: hoje(14), valor: 30000 }),
      neg({ id: '2', status: 'ganho', etapa: 'fechado', fechadoEm: ontem }),
      neg({ id: '3', status: 'ganho', etapa: 'fechado', fechadoEm: hoje(15), produto: 'ht', valor: 297, donoId: 'ronan' }),
    ], [], [], dia);
    expect(f.total.vendas).toBe(2);
    expect(f.total.receita).toBe(30297);
    expect(f.vendasPorProduto).toEqual(expect.arrayContaining([{ produto: 'hm', quantidade: 1, valor: 30000 }, { produto: 'ht', quantidade: 1, valor: 297 }]));
  });

  it('em negociação = abertos em Negociar ou Aguardar pagamento', () => {
    const f = calcularFechamento([
      neg({ id: '1', etapa: 'negociar' }), neg({ id: '2', etapa: 'aguardar_pagamento' }), neg({ id: '3', etapa: 'qualificar' }),
      neg({ id: '4', etapa: 'negociar', status: 'perdido' }),
    ], [], [], dia);
    expect(f.total.emNegociacao).toBe(2);
  });

  it('alertas: sem próximo passo, sem dono, atrasadas, perdidos do dia por motivo', () => {
    const f = calcularFechamento([
      neg({ id: '1', proximaAtividade: null }),
      neg({ id: '2', donoId: null }),
      neg({ id: '3', status: 'perdido', motivoPerda: 'sem_interesse', fechadoEm: hoje(9) }),
    ], [atv({ venceEm: hoje(8) }), atv({ id: 'b', venceEm: hoje(8), concluidaEm: hoje(9) })], [], dia);
    expect(f.alertas.semProximaAtividade).toBe(1);
    expect(f.alertas.semDono).toBe(1);
    expect(f.alertas.atrasadasPorVendedor).toEqual({ marcos: 1 });
    expect(f.alertas.perdidosPorMotivo).toEqual({ sem_interesse: 1 });
  });

  it('respostas e entradas vêm dos eventos do dia', () => {
    const ev = (p: Partial<EventoTimeline>): EventoTimeline => ({ id: 'e', contatoId: 'c', negocioId: 'n', tipo: 'etapa', titulo: '', detalhe: null, em: hoje(10), autorId: null, ...p });
    const f = calcularFechamento([neg({})], [], [
      ev({ id: '1', detalhe: 'qualificar' }),
      ev({ id: '2', detalhe: 'qualificar' }),
      ev({ id: '3', tipo: 'mensagem', titulo: 'Lead escreveu no WhatsApp', contatoId: 'c9' }),
      ev({ id: '4', detalhe: 'negociar' }),
    ], dia);
    expect(f.total.responderam).toBe(1);
    expect(f.total.entraramEmContato).toBe(1);
    expect(f.total.entraramEmNegociacaoHoje).toBe(1);
  });
});
