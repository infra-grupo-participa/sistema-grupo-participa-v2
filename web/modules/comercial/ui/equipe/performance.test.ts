import { describe, expect, it } from 'vitest';
import { MOTIVOS_PADRAO } from '../../domain/catalogo';
import type { Atividade, Conversa, Negocio } from '../../domain/types';
import {
  atividadesPorTipo, cadenciaCumprida, carteira, conversasSemResposta, funilPessoal, indicadoresVendedor, intervaloEquipe,
  mapaCalor, notaCriterio, perdidosDoVendedor, posicoesNoTime, rankingPor, referenciaTime, selosVendedor, tendenciaReceita,
  variacaoPct, vendasAgrupadas, type BaseEquipe, type IndicadoresVendedor,
} from './performance';

const agora = new Date('2026-10-05T19:00:00-03:00');
const h = (dia: number, hora: number, min = 0) =>
  new Date(`2026-10-${String(dia).padStart(2, '0')}T${String(hora).padStart(2, '0')}:${String(min).padStart(2, '0')}:00-03:00`).toISOString();

const neg = (p: Partial<Negocio>): Negocio => ({
  id: 'n', contatoId: 'c', produto: 'hm', origem: 'venda_ativa', funilId: 'f-hm', campanhaId: null, etapaId: 'e', etapaNome: 'Qualificar',
  etapa: 'qualificar', status: 'aberto', donoId: 'marcos', valor: 30000, campos: {}, motivoPerda: null, criadoEm: h(4, 10), etapaDesde: h(5, 18),
  fechadoEm: null, proximaAtividade: { id: 'a', tipo: 'ligacao', titulo: 'x', venceEm: h(5, 20) }, ultimaInteracaoEm: null, ...p,
});
const atv = (p: Partial<Atividade>): Atividade => ({
  id: 'a', negocioId: 'n', contatoId: 'c', donoId: 'marcos', tipo: 'whatsapp', titulo: 'x', venceEm: h(5, 10),
  concluidaEm: null, resultado: null, cadenciaDia: null, ...p,
});
const conversa = (contatoId: string, direcao: 'entrada' | 'saida', em: string, atribuidaA: string | null): Conversa => ({
  contatoId, naoLidas: direcao === 'entrada' ? 1 : 0, janelaAteEm: null, atribuidaA,
  ultimaMensagem: { id: `m-${contatoId}`, contatoId, canal: 'whatsapp', direcao, texto: 'Oi', em, status: null, autorId: null, templateId: null },
});

function base(p: Partial<BaseEquipe> = {}): BaseEquipe {
  return {
    negocios: [], atividades: [], eventos: [], conversas: [], motivos: MOTIVOS_PADRAO,
    funis: [{ id: 'f-hm', nome: 'HM venda ativa' } as BaseEquipe['funis'][number]], agora, ...p,
  };
}

const sete = intervaloEquipe('7d', agora).atual;

describe('intervaloEquipe', () => {
  it('personalizado: do início de "de" ao fim de "ate", anterior do mesmo tamanho logo antes', () => {
    const { atual, anterior } = intervaloEquipe('personalizado', agora, '2026-10-01', '2026-10-03');
    expect(new Date(atual.ini).toISOString()).toBe('2026-10-01T03:00:00.000Z');
    expect(new Date(atual.fim).toISOString()).toBe('2026-10-04T02:59:59.999Z');
    expect(new Date(anterior.ini).toISOString()).toBe('2026-09-28T03:00:00.000Z');
    expect(anterior.fim).toBe(atual.ini - 1);
  });
  it('personalizado até hoje para em agora; datas inválidas caem em 7 dias', () => {
    expect(intervaloEquipe('personalizado', agora, '2026-10-05', '2026-10-09').atual.fim).toBe(agora.getTime());
    expect(intervaloEquipe('personalizado', agora, '2026-10-05', '2026-10-01')).toEqual(intervaloEquipe('7d', agora));
  });
});

describe('indicadoresVendedor', () => {
  const b = base({
    negocios: [
      neg({ id: 'g1', status: 'ganho', fechadoEm: h(5, 11), valor: 30000 }),
      neg({ id: 'g2', status: 'ganho', fechadoEm: h(3, 11), valor: 1200, produto: 'sv' }),
      neg({ id: 'p1', status: 'perdido', fechadoEm: h(4, 11), motivoPerda: 'sem_interesse' }),
      neg({ id: 'p2', status: 'perdido', fechadoEm: h(4, 12), motivoPerda: 'sem_interesse' }),
      neg({ id: 'p3', status: 'perdido', fechadoEm: h(4, 13), motivoPerda: 'ja_atendido_outro_vendedor' }),
      neg({ id: 'novo', criadoEm: h(5, 9), proximaAtividade: null }),
      neg({ id: 'ronan', donoId: 'ronan', status: 'ganho', fechadoEm: h(5, 9) }),
    ],
    atividades: [
      atv({ id: 'a1', negocioId: 'novo', concluidaEm: h(5, 9, 12), venceEm: h(5, 9, 12) }),
      atv({ id: 'a2', negocioId: 'novo', concluidaEm: h(5, 10), venceEm: h(5, 10), tipo: 'ligacao' }),
      atv({ id: 'a3', venceEm: h(5, 8), concluidaEm: null }),
      atv({ id: 'a4', venceEm: h(4, 8), concluidaEm: h(4, 9), tipo: 'email' }),
    ],
    conversas: [conversa('c1', 'entrada', h(5, 17), 'marcos'), conversa('c2', 'saida', h(5, 17), 'marcos')],
  });
  const l = indicadoresVendedor(b, 'marcos', sete);

  it('vendas, receita, ticket e conversão contam só o dono no período', () => {
    expect(l.vendas).toBe(2);
    expect(l.receita).toBe(31200);
    expect(l.ticketMedio).toBe(15600);
    expect(l.encerrados).toBe(5);
    expect(l.conversao).toBe(40);
  });
  it('principal motivo, falha de processo e carga', () => {
    expect(l.principalMotivo).toMatchObject({ motivo: 'sem_interesse', quantidade: 2 });
    expect(l.falhaProcesso).toBe(1);
    expect(l.abertos).toBe(1);
    expect(l.semProximo).toBe(1);
    expect(l.atrasadas).toBe(1);
  });
  it('primeiro contato pela primeira atividade concluída; no prazo pelas vencidas', () => {
    expect(l.tempoPrimeiroContatoMin).toBe(12);
    expect(l.abordagens).toBe(2);
    expect(l.abordagensDia).toBeCloseTo(0.3);
    // vencidas: a1, a2, a3 (aberta), a4 (concluída 1h depois) → 2 de 4
    expect(l.noPrazo).toEqual({ cumpridas: 2, base: 4, pct: 50 });
    expect(l.semResposta).toBe(1);
    expect(l.reembolsos).toBeNull();
  });
  it('time (dono null) soma todo mundo', () => {
    expect(indicadoresVendedor(b, null, sete).vendas).toBe(3);
  });
});

const linha = (p: Partial<IndicadoresVendedor>): IndicadoresVendedor => ({
  vendedorId: 'x', vendas: 0, receita: 0, ticketMedio: null, ganhos: 0, perdidos: 0, encerrados: 0, conversao: null, abertos: 0, criticos: 0,
  semProximo: 0, atrasadas: 0, tempoPrimeiroContatoMin: null, abordagens: 0, abordagensDia: 0, atividadesConcluidas: 0,
  noPrazo: { cumpridas: 0, base: 0, pct: null }, principalMotivo: null, falhaProcesso: 0, reembolsos: null, condicaoEspecial: null, semResposta: 0, ...p,
});

describe('referência do time e selos', () => {
  const a = linha({ vendedorId: 'a', vendas: 6, receita: 60000, ganhos: 6, encerrados: 20, conversao: 30, abertos: 12, tempoPrimeiroContatoMin: 90, semProximo: 2, criticos: 1 });
  const b = linha({ vendedorId: 'b', vendas: 4, receita: 120000, ganhos: 8, encerrados: 10, conversao: 80, abertos: 4, tempoPrimeiroContatoMin: 8, atividadesConcluidas: 10, noPrazo: { cumpridas: 10, base: 10, pct: 100 } });
  const ref = referenciaTime([a, b]);

  it('taxa do time é do time somado, contagem é média', () => {
    expect(ref.conversao).toBeCloseTo(46.67, 1);
    expect(ref.ticketMedio).toBe(18000);
    expect(ref.abertos).toBe(8);
    expect(ref.tempoPrimeiroContatoMin).toBe(49);
  });
  it('quem mais vende pode ter alertas; o melhor convertedor ganha destaques', () => {
    const sa = selosVendedor(a, ref, [a, b]).map((s) => s.k);
    expect(sa).toEqual(['fila_parada', 'conversao_abaixo', 'contato_lento', 'mais_vende']);
    const sb = selosVendedor(b, ref, [a, b]).map((s) => s.k);
    expect(sb).toEqual(['melhor_conversao', 'responde_rapido', 'disciplina']);
    expect(selosVendedor(b, ref, [a, b]).every((s) => s.tipo === 'destaque')).toBe(true);
  });
  it('ranking muda conforme o critério', () => {
    expect(rankingPor([a, b], 'volume').map((x) => x.vendedorId)).toEqual(['b', 'a']);
    expect(rankingPor([a, b], 'conversao')[0]).toMatchObject({ vendedorId: 'b', posicao: 1 });
    expect(notaCriterio(a, 'disciplina')).toBe(80);
    expect(notaCriterio(linha({ encerrados: 2, conversao: 100 }), 'conversao')).toBeNull();
    const c = linha({ vendedorId: 'c', receita: 120000 });
    expect(rankingPor([a, b, c], 'volume').map((x) => x.posicao)).toEqual([1, 1, 3]);
    expect(posicoesNoTime([a, b], 'a').conversao).toEqual({ posicao: 2, de: 2 });
  });
  it('variação contra referência', () => {
    expect(variacaoPct(150, 100)).toBe(50);
    expect(variacaoPct(10, 0)).toBeNull();
  });
});

describe('detalhe do vendedor', () => {
  const b = base({
    negocios: [
      neg({ id: 'q', etapa: 'qualificar', criadoEm: h(4, 9) }),
      neg({ id: 'e1', etapa: 'primeiro_contato', criadoEm: h(4, 9), etapaDesde: h(4, 9) }),
      neg({ id: 'g', etapa: 'fechado', status: 'ganho', fechadoEm: h(5, 10), criadoEm: h(3, 9) }),
      neg({ id: 'r', donoId: 'ronan', etapa: 'primeiro_contato', criadoEm: h(4, 9), etapaDesde: h(5, 18, 55) }),
      neg({ id: 'perd', status: 'perdido', motivoPerda: 'sem_interesse', fechadoEm: h(4, 9) }),
      neg({ id: 'perdR', donoId: 'ronan', etapa: 'primeiro_contato', status: 'perdido', motivoPerda: 'contato_invalido', fechadoEm: h(4, 9) }),
    ],
    atividades: [
      atv({ id: 'x1', concluidaEm: h(5, 9, 30), tipo: 'ligacao' }), // segunda 9h30
      atv({ id: 'x2', concluidaEm: h(5, 7), tipo: 'whatsapp' }), // fora do horário
      atv({ id: 'x3', donoId: 'ronan', concluidaEm: h(5, 9), tipo: 'ligacao' }),
      atv({ id: 'c1', cadenciaDia: 1, venceEm: h(5, 9), concluidaEm: h(5, 9) }),
      atv({ id: 'c2', cadenciaDia: 2, venceEm: h(5, 9), concluidaEm: h(5, 11) }),
      atv({ id: 'c3', cadenciaDia: 3, venceEm: h(5, 9), concluidaEm: null }),
    ],
  });
  const time = ['marcos', 'ronan'];

  it('funil pessoal pelo papel, com passagem do time', () => {
    const f = funilPessoal(b, 'marcos', sete, time);
    expect(f[0]).toMatchObject({ etapa: 'primeiro_contato', chegaram: 4, passagem: null });
    expect(f[1]).toMatchObject({ etapa: 'qualificar', chegaram: 3, passagem: 75, passagemTime: 50 });
  });
  it('atividades por tipo e mapa de calor', () => {
    const t = atividadesPorTipo(b, 'marcos', sete, time);
    expect(t.find((x) => x.tipo === 'ligacao')).toEqual({ tipo: 'ligacao', vendedor: 1, mediaTime: 1 });
    const m = mapaCalor(b, 'marcos', sete);
    expect(m.celulas[0][0]).toBe(2); // segunda 8–10h: x1 + c1
    expect(m.celulas[0][6]).toBe(1); // fora do horário: x2
  });
  it('cadência: no prazo, com atraso e pendente', () => {
    expect(cadenciaCumprida(b, 'marcos', sete)).toEqual({ previstos: 3, noPrazo: 1, comAtraso: 1, pendentes: 1, pct: 33 });
  });
  it('perdidos com a fatia do time, vendas por funil e carteira', () => {
    expect(perdidosDoVendedor(b, 'marcos', sete, time)).toEqual([
      { motivo: 'sem_interesse', rotulo: expect.any(String), quantidade: 1, pct: 100, pctTime: 50, falha: false },
    ]);
    expect(vendasAgrupadas(b, 'marcos', sete, 'funil')).toEqual([{ chave: 'f-hm', rotulo: 'HM venda ativa', quantidade: 1, valor: 30000 }]);
    const c = carteira(b, 'marcos');
    expect(c.linhas.find((l) => l.etapa === 'primeiro_contato')).toMatchObject({ abertos: 1, criticos: 1 });
    expect(c.criticos.map((n) => n.id)).toEqual(['e1']);
  });
  it('tendência tem ao menos 7 dias', () => {
    const t = tendenciaReceita(b, 'marcos', intervaloEquipe('hoje', agora).atual);
    expect(t).toHaveLength(7);
    expect(t[6]).toEqual({ dia: '2026-10-05', valor: 30000 });
  });
  it('conversa sem resposta: lead escreveu por último, só do dono', () => {
    const r = conversasSemResposta({ agora, conversas: [conversa('a', 'entrada', h(5, 18), 'marcos'), conversa('b', 'entrada', h(5, 18, 30), 'ronan'), conversa('c', 'saida', h(5, 18), 'marcos')] }, 'marcos');
    expect(r).toEqual([{ contatoId: 'a', esperaMin: 60, naoLidas: 1, texto: 'Oi' }]);
  });
});
