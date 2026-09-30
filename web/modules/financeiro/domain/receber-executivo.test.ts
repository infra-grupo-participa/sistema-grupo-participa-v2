import { describe, expect, it } from 'vitest';
import type { CobrancaRecorrente } from './contas-receber';
import { normalizarLinhaReceber } from './contas-receber';
import { normalizarInformado } from './recebimentos-informados';
import { normalizarEventoPlanejado } from './eventos-planejados';
import { agruparPremissas, normalizarSugestao, normalizarVigencia } from './premissas-receber';
import { normalizarMudanca, type SemanaPrevistoRealizado } from './visao-receber';
import {
  diasEntre, maiorAReceber, resumoAcerto, resumoEventos, resumoInformados, resumoMudancas, resumoPremissas, resumoRecorrencias,
} from './receber-executivo';

const HOJE = '2026-09-28';
const cob = (p: Partial<CobrancaRecorrente>): CobrancaRecorrente => ({
  ref: null, grupo: 'Parcelas a vencer HM', rotulo: null, produto: null, prevista: HOJE, caixa: [], valor: 0, esperado: 0,
  situacao: 'a_receber', k: null, ...p,
});

describe('diasEntre', () => {
  it('conta dias de calendário, atravessando mês', () => {
    expect(diasEntre('2026-08-29', '2026-09-28')).toBe(30);
    expect(diasEntre('2026-09-28', '2026-09-27')).toBe(-1);
  });
});

describe('resumoRecorrencias', () => {
  const xs = [
    cob({ valor: 0.1, produto: 'HM' }), cob({ valor: 0.2, produto: 'HM' }), cob({ valor: 1, produto: null, grupo: 'Aurum' }),
    cob({ situacao: 'em_atraso_fora', valor: 10, prevista: '2026-08-29' }), // 30 dias
    cob({ situacao: 'em_atraso_fora', valor: 20, prevista: '2026-08-28' }), // 31 dias
    cob({ situacao: 'em_atraso_fora', valor: 40, prevista: '2026-07-01' }), // 89 dias
    cob({ situacao: 'realizada', valor: 5 }), cob({ situacao: 'coberta_informado', valor: 7 }),
  ];
  const r = resumoRecorrencias(xs, HOJE);
  it('soma por situação em centavos', () => {
    expect(r.aReceber).toEqual({ n: 3, valor: 1.3 });
    expect(r.atraso).toEqual({ n: 3, valor: 70 });
    expect(r.realizada.valor).toBe(5);
    expect(r.coberta.valor).toBe(7);
  });
  it('aging nas 3 faixas, com a borda de 30 dias na 1ª', () => {
    expect(r.aging.map((a) => [a.faixa, a.n, a.valor])).toEqual([['ate30', 1, 10], ['de31a60', 1, 20], ['mais60', 1, 40]]);
    expect(r.maiorAtrasoDias).toBe(89);
  });
  it('% em dia = a receber ÷ (a receber + atraso); sem os dois, NULL (não 0%)', () => {
    expect(r.pctEmDia).toBe(1.8);
    expect(resumoRecorrencias([], HOJE).pctEmDia).toBeNull();
    expect(resumoRecorrencias([], HOJE).maiorAtrasoDias).toBeNull();
  });
  it('concentração por produto (sem produto = grupo), maior primeiro', () => {
    expect(r.porProduto.map((p) => [p.produto, p.valor, p.pct])).toEqual([['Aurum', 1, 76.9], ['HM', 0.3, 23.1]]);
  });
});

describe('resumoInformados', () => {
  const I = (p: Record<string, unknown>) => normalizarInformado({ id: String(Math.random()), cliente: 'X', tipo: 't', ...p });
  const lista = [
    I({ situacao: 'em_atraso_cobrar', valor: 100, data_prevista: '2026-09-18' }),
    I({ situacao: 'em_atraso_cobrar', valor: 50, data_prevista: '2026-09-25' }),
    I({ situacao: 'a_receber', valor: 30, data_prevista: '2026-10-05' }),
    I({ situacao: 'a_receber', valor: 20, data_prevista: '2026-10-05' }),
    I({ situacao: 'a_receber', valor: 90, data_prevista: '2026-11-01' }),
    I({ situacao: 'realizado_hotmart', valor: 10 }), I({ situacao: 'baixado_fora', valor: 15 }), I({ situacao: 'arquivado', valor: 999 }),
  ];
  it('a cobrar, recebido, baixado, atraso mais antigo e o próximo a receber', () => {
    const r = resumoInformados(lista, HOJE);
    expect(r.aCobrar).toEqual({ n: 2, valor: 150 });
    expect(r.aReceber).toEqual({ n: 3, valor: 140 });
    expect(r.recebidoHotmart.valor).toBe(10);
    expect(r.baixadoFora.valor).toBe(15);
    expect(r.atrasoMaisAntigoDias).toBe(10);
    expect(r.proximo).toEqual({ data: '2026-10-05', n: 2, valor: 50 });
  });
  it('z93: baixa automática pela Hotmart (baixado_fora + transacao_hotmart) NÃO entra no "Baixado fora"', () => {
    const r = resumoInformados([...lista, I({ situacao: 'baixado_fora', valor: 500, transacao_hotmart: 'HP1' })], HOJE);
    expect(r.baixadoFora).toEqual({ n: 1, valor: 15 });
  });
  it('lista vazia: sem atraso nem próximo', () => {
    const r = resumoInformados([], HOJE);
    expect(r.atrasoMaisAntigoDias).toBeNull();
    expect(r.proximo).toBeNull();
  });
});

describe('resumoEventos', () => {
  const E = (p: Record<string, unknown>) => normalizarEventoPlanejado({ evento_ref_id: 1, tamanho_base: 1, tamanho_conservador: 0.7, tamanho_otimista: 1.3, ...p });
  const evs = [
    E({ id: 1, nome: 'A', abertura: '2026-10-10', situacao: 'ativo', total_ref: 1000 }),
    E({ id: 2, nome: 'B', abertura: '2026-11-10', situacao: 'ativo', total_ref: null }),
    E({ id: 3, nome: 'C', abertura: '2026-08-01', situacao: 'encerrado', total_ref: 500 }),
    E({ id: 4, nome: 'D', abertura: '2026-10-01', situacao: 'arquivado', total_ref: 9000 }),
  ];
  it('soma só ativos com referência; sem referência conta à parte (não é zero)', () => {
    const r = resumoEventos(evs, HOJE);
    expect(r.ativos).toBe(2);
    expect(r.encerrados).toBe(1);
    expect(r.previstoAtivos).toBe(1000);
    expect(r.semReferencia).toBe(1);
    expect(r.proximo).toEqual({ nome: 'A', abertura: '2026-10-10' });
    expect(r.porEvento.map((e) => [e.nome, e.previsto])).toEqual([['A', 1000], ['C', 500], ['B', null]]);
  });
});

describe('resumoPremissas', () => {
  const V = (p: Record<string, unknown>) => normalizarVigencia({ grupo_tela: 'G', unidade: 'percentual', minimo: 0, maximo: 1,
    situacao: 'vigente', vigente_de: '2026-09-01', ...p });
  const grupos = agruparPremissas([
    V({ chave: 'a', rotulo: 'A', valor: 0.05 }),
    V({ chave: 'b', rotulo: 'B', valor: 0.03 }),
    V({ chave: 'c', rotulo: 'C', valor: 0.1 }),
  ]);
  const sug = new Map([
    ['a', normalizarSugestao({ chave: 'a', unidade: 'percentual', sugestao: 0.05 })],
    ['b', normalizarSugestao({ chave: 'b', unidade: 'percentual', sugestao: 0.04 })],
  ]);
  it('conta com sugestão e quantas divergem do valor em uso', () => {
    const r = resumoPremissas(grupos.flatMap((g) => g.premissas), sug);
    expect(r).toEqual({ total: 3, comSugestao: 2, divergentes: 1, semVigente: 0 });
  });
});

describe('resumoMudancas', () => {
  it('soma por motivo entre grupos; entrou positivo, saiu negativo, líquido', () => {
    const r = resumoMudancas([
      normalizarMudanca({ bloco: 2, grupo: 'X', valor_a: 0, valor_b: 0, delta: 0, motivos: [{ motivo: 'entrou', itens: 2, valor: 100 }, { motivo: 'saiu_pagamento', itens: 1, valor: -30 }] }),
      normalizarMudanca({ bloco: 5, grupo: 'Y', valor_a: 0, valor_b: 0, delta: 0, motivos: [{ motivo: 'saiu_pagamento', itens: 3, valor: -90.1 }] }),
    ]);
    expect(r.porMotivo).toEqual([{ motivo: 'saiu_pagamento', itens: 4, valor: -120.1 }, { motivo: 'entrou', itens: 2, valor: 100 }]);
    expect(r.entrou).toBe(100);
    expect(r.saiu).toBe(-120.1);
    expect(r.liquido).toBe(-20.1);
  });
});

describe('resumoAcerto', () => {
  const S = (certoAcerto: number | null) => ({ certoAcerto }) as SemanaPrevistoRealizado;
  it('última, variação em pontos e média; sem semanas, tudo NULL', () => {
    expect(resumoAcerto([S(90), S(80), S(null)])).toEqual({ ultima: 90, variacaoPp: 10, media: 85, semanas: 2 });
    expect(resumoAcerto([])).toEqual({ ultima: null, variacaoPp: null, media: null, semanas: 0 });
  });
});

describe('maiorAReceber', () => {
  it('só linha a receber conta', () => {
    const L = (p: Record<string, unknown>) => normalizarLinhaReceber({ bloco: 1, grupo: 'g', componente: 'cheio', ...p });
    const m = maiorAReceber([L({ situacao: 'a_receber', valor: 10 }), L({ situacao: 'realizada', valor: 99 }), L({ situacao: 'a_receber', valor: 20 })]);
    expect(m?.valor).toBe(20);
    expect(maiorAReceber([])).toBeNull();
  });
});
