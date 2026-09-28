import { describe, expect, it } from 'vitest';
import { cobrancasRecorrentes, normalizarLinhaReceber } from './contas-receber';
import {
  acertoPct, alertasReceber, domingoDe, normalizarFoto, normalizarMudanca, normalizarPrevistoRealizado, parComparacao,
  primeiraSemanaComparavel, proximaFoto, proximas4Semanas, resumirPrevistoRealizado, segundaEmOuDepois, separarMudancas,
} from './visao-receber';

const L = (p: Record<string, unknown>) => normalizarLinhaReceber({
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', situacao: 'a_receber', valor: 0, ...p,
});
const F = (p: Record<string, unknown>) => normalizarFoto({
  foto_em: '2026-09-28T12:00:00+00:00', dia: '2026-09-28', cenario: 'base', linhas: 10, soma_a_receber: '100.5', reconstruida: false, ...p,
});

describe('calendário', () => {
  it('domingo da semana e 1ª segunda >= dia', () => {
    expect(domingoDe('2026-09-28')).toBe('2026-10-04'); // segunda
    expect(domingoDe('2026-10-04')).toBe('2026-10-04'); // domingo
    expect(segundaEmOuDepois('2026-09-28')).toBe('2026-09-28');
    expect(segundaEmOuDepois('2026-09-29')).toBe('2026-10-05');
    expect(segundaEmOuDepois('2026-10-04')).toBe('2026-10-05');
  });
  it('próxima foto: segunda 06:11 em São Paulo', () => {
    expect(proximaFoto('2026-09-28', 6 * 60 + 10)).toBe('2026-09-28'); // segunda antes das 06:11: hoje
    expect(proximaFoto('2026-09-28', 6 * 60 + 11)).toBe('2026-10-05'); // já tirou: a próxima
    expect(proximaFoto('2026-10-01', 0)).toBe('2026-10-05');
  });
});

describe('proximas4Semanas', () => {
  it('4 semanas seg–dom a partir de hoje; certo (1, 2, 5) × estimado (3, 4, 6); só a_receber soma', () => {
    const linhas = [
      L({ data_caixa: '2026-09-30', valor: 100 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', data_caixa: '2026-10-06', valor: 50.1 }),
      L({ bloco: 5, grupo: 'Renovações Diamante', componente: 'cheio', data_caixa: '2026-10-25', valor: 0.2 }),
      L({ bloco: 3, grupo: 'HM avulso', data_caixa: '2026-10-13', valor: 30 }),
      L({ bloco: 6, grupo: 'Reserva de reembolso e chargeback', componente: 'reserva', data_caixa: '2026-10-13', valor: -3 }),
      L({ data_caixa: '2026-10-26', valor: 999 }), // fora (5ª semana)
      L({ data_caixa: '2026-09-25', valor: 7 }), // antes de hoje: na 1ª semana, como na grade
      L({ situacao: 'realizada', data_caixa: '2026-09-30', valor: 1000 }),
      L({ bloco: 8, grupo: 'Informativo: acordos no board', situacao: 'informativo', data_caixa: '2026-09-30', valor: 1000 }),
      L({ bloco: 3, grupo: 'Holding Total', situacao: 'sem_base', data_caixa: null, valor: 0 }),
    ];
    const q = proximas4Semanas(linhas, '2026-09-28');
    expect(q.semanas.map((s) => [s.inicio, s.fim])).toEqual([
      ['2026-09-28', '2026-10-04'], ['2026-10-05', '2026-10-11'], ['2026-10-12', '2026-10-18'], ['2026-10-19', '2026-10-25'],
    ]);
    expect(q.semanas[0]).toMatchObject({ certo: 107, estimado: 0, total: 107 });
    expect(q.semanas[1]).toMatchObject({ certo: 50.1, estimado: 0 });
    expect(q.semanas[2]).toMatchObject({ certo: 0, estimado: 27 });
    expect(q.semanas[3]).toMatchObject({ certo: 0.2 });
    expect(q).toMatchObject({ certo: 157.3, estimado: 27, total: 184.3 });
  });
  it('hoje no meio da semana: a 1ª vai de hoje ao domingo', () => {
    const q = proximas4Semanas([], '2026-10-01');
    expect(q.semanas[0]).toMatchObject({ inicio: '2026-10-01', fim: '2026-10-04' });
    expect(q.semanas[3]).toMatchObject({ inicio: '2026-10-19', fim: '2026-10-25' });
  });
});

describe('alertasReceber', () => {
  it('fora da projeção conta cobranças (antecipação + garantia = 1); informados a cobrar; sem base; projeção', () => {
    const linhas = [
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', situacao: 'em_atraso_fora', ref: 'r1', origem_dia: '2026-09-01', valor: 90, valor_bruto: 90 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'garantia', situacao: 'em_atraso_fora', ref: 'r1', origem_dia: '2026-09-01', valor: 10, valor_bruto: 10 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', situacao: 'em_atraso_fora', ref: 'r2', origem_dia: '2026-09-02', valor: 5, valor_bruto: 5 }),
      L({ bloco: 5, grupo: 'Renovações Aurum', componente: 'cheio', situacao: 'em_atraso_fora', valor: 300 }),
      L({ bloco: 3, grupo: 'Holding Total', situacao: 'sem_base' }),
      L({ bloco: 3, grupo: 'Holding Total', situacao: 'sem_base' }),
    ];
    const a = alertasReceber(linhas, cobrancasRecorrentes(linhas));
    expect(a.foraDaProjecao).toEqual({ n: 2, valor: 105 });
    expect(a.informadosACobrar).toEqual({ n: 1, valor: 300 });
    expect(a.semBase).toEqual([{ bloco: 3, grupo: 'Holding Total' }]);
    expect(a.projecaoDesligada).toBe(false);
  });
  it('sem nenhuma linha dos blocos 3, 4, 6 e 8: projeção desligada', () => {
    const linhas = [L({ data_caixa: '2026-09-30', valor: 1 })];
    expect(alertasReceber(linhas, []).projecaoDesligada).toBe(true);
  });
});

describe('fotos', () => {
  it('normaliza numeric como texto; só base entra na comparação; A = anterior, B = mais recente', () => {
    expect(F({}).soma_a_receber).toBe(100.5);
    const fotos = [
      F({ foto_em: '2026-09-28T12:00:00+00:00', dia: '2026-09-28' }),
      F({ foto_em: '2026-10-05T09:11:00+00:00', dia: '2026-10-05' }),
      F({ foto_em: '2026-10-06T10:00:00+00:00', dia: '2026-10-06', cenario: 'otimista' }),
    ];
    const par = parComparacao(fotos)!;
    expect(par.anterior.dia).toBe('2026-09-28');
    expect(par.recente.dia).toBe('2026-10-05');
    expect(parComparacao([fotos[0], fotos[2]])).toBeNull(); // 1 foto base: sem comparação
  });
  it('1ª semana comparável: a da foto mais antiga; sai na segunda seguinte', () => {
    expect(primeiraSemanaComparavel([F({})])).toEqual({ de: '2026-09-28', ate: '2026-10-04', sai: '2026-10-05' });
    expect(primeiraSemanaComparavel([F({ dia: '2026-09-29' })])).toEqual({ de: '2026-10-05', ate: '2026-10-11', sai: '2026-10-12' });
    expect(primeiraSemanaComparavel([])).toBeNull();
  });
});

describe('mudanças', () => {
  it('motivos em jsonb (objeto ou texto); grupos sem mudança viram contagem', () => {
    const m = [
      normalizarMudanca({ bloco: '2', grupo: 'Parcelas a vencer HM', valor_a: '100', valor_b: '80', delta: '-20',
        motivos: JSON.stringify([{ motivo: 'saiu_pagamento', itens: 2, valor: '-20' }]) }),
      normalizarMudanca({ bloco: 1, grupo: 'Vendas já realizadas', valor_a: 5, valor_b: 5, delta: 0, motivos: [] }),
    ];
    expect(m[0].motivos).toEqual([{ motivo: 'saiu_pagamento', itens: 2, valor: -20 }]);
    expect(separarMudancas(m)).toEqual({ mudaram: [m[0]], semMudanca: 1 });
  });
});

describe('previsto × realizado', () => {
  it('acerto: mesma fórmula do banco', () => {
    expect(acertoPct(100, 90)).toBe(90);
    expect(acertoPct(100, 250)).toBe(0);
    expect(acertoPct(0, 10)).toBeNull();
    expect(acertoPct(3, 2)).toBe(66.7);
  });
  it('por semana: certo medido, estimado só previsto, "Fora da foto" à parte; semanas sem foto contadas; perda', () => {
    const P = (p: Record<string, unknown>) => normalizarPrevistoRealizado({ linha: 'semana', semana_de: '2026-09-28', semana_ate: '2026-10-04',
      janela_de: '2026-09-29', janela_ate: '2026-10-04', foto_em: '2026-09-28T12:00:00+00:00', ...p });
    const linhas = [
      P({ bloco: 1, grupo: 'Vendas já realizadas', previsto: '100', realizado: '95' }),
      P({ bloco: 2, grupo: 'Parcelas a vencer HM', previsto: 50, realizado: 40 }),
      P({ bloco: 3, grupo: 'HM avulso', previsto: 30, realizado: null }),
      P({ bloco: null, grupo: 'Fora da foto (vendas novas e outros)', previsto: 0, realizado: 12 }),
      P({ semana_de: '2026-09-21', semana_ate: '2026-09-27', foto_em: null, janela_de: null, janela_ate: null, bloco: null, grupo: null,
        nota: 'sem foto base no início da semana' }),
      normalizarPrevistoRealizado({ linha: 'perda', bloco: 2, grupo: 'Parcelas a vencer HM', perda_medida: '0.05', premissa_atual: '0.03',
        cobrancas_resolvidas: 20, cobrancas_perdidas: 1 }),
    ];
    const r = resumirPrevistoRealizado(linhas);
    expect(r.semanasSemFoto).toBe(1);
    expect(r.semanas).toHaveLength(1);
    expect(r.semanas[0]).toMatchObject({
      de: '2026-09-28', ate: '2026-10-04', certoPrevisto: 150, certoRealizado: 135, certoAcerto: 90, estimadoPrevisto: 30, foraDaFoto: 12,
    });
    expect(r.semanas[0].linhas).toHaveLength(4);
    expect(r.perda).toHaveLength(1);
    expect(r.perda[0].perda_medida).toBe(0.05);
  });
});
