import { describe, expect, it } from 'vitest';
import type { Aluno360 } from './aluno-360';
import { distribuicaoNivel, distribuicaoSituacao, distribuicaoTurmas, ingressos12m, serieEntrada } from './dashboard-executivo';

const a = (p: Partial<Aluno360>): Aluno360 => ({ id: Math.random().toString(), ...p } as Aluno360);

describe('distribuicaoTurmas', () => {
  it('ordem T maior → menor, % sobre quem tem turma', () => {
    const base = [a({ turma_codigo: 'T2' }), a({ turma_codigo: 'T10' }), a({ turma_codigo: 'T10' }), a({ turma_codigo: 'T9' }), a({})];
    const d = distribuicaoTurmas(base, 'turma_codigo');
    expect(d.fatias.map((f) => [f.key, f.count, f.pct])).toEqual([['T10', 2, 50], ['T9', 1, 25], ['T2', 1, 25]]);
    expect([d.comTurma, d.semTurma]).toEqual([4, 1]);
  });

  it('acima do topN: as maiores na ordem das turmas + "Outras"', () => {
    const base = [
      ...Array.from({ length: 3 }, () => a({ turma_aurum_codigo: 'A1' })),
      ...Array.from({ length: 2 }, () => a({ turma_aurum_codigo: 'A3' })),
      a({ turma_aurum_codigo: 'A2' }), a({ turma_aurum_codigo: 'A4' }),
    ];
    const d = distribuicaoTurmas(base, 'turma_aurum_codigo', 2);
    expect(d.fatias.map((f) => [f.key, f.count])).toEqual([['A3', 2], ['A1', 3], ['__outras__', 2]]);
    expect(d.fatias[2].label).toBe('Outras 2 turmas');
  });
});

describe('distribuicaoNivel / distribuicaoSituacao', () => {
  it('nível na ordem da escala, sem nível ao fim', () => {
    const d = distribuicaoNivel([a({ nivel_resultado: 'diamante' }), a({ nivel_resultado: 'Ouro' }), a({ nivel_resultado: null }), a({ nivel_resultado: 'ouro' })]);
    expect(d.map((f) => [f.key, f.count, f.pct])).toEqual([['ouro', 2, 50], ['diamante', 1, 25], ['__none__', 1, 25]]);
  });

  it('situação na ordem do catálogo; valor desconhecido vira sem situação', () => {
    const d = distribuicaoSituacao([a({ situacao_acesso: 'vencido' }), a({ situacao_acesso: 'em_dia' }), a({ situacao_acesso: 'x' })]);
    expect(d.map((f) => f.key)).toEqual(['em_dia', 'vencido', '__none__']);
    expect(d[2].label).toBe('Sem situação');
  });
});

describe('serieEntrada', () => {
  it('mensal até 36 meses, com mês vazio zerado e segmentos por espaço', () => {
    const s = serieEntrada([
      a({ data_compra_importada: '2025-01-10', espaco_instrucao: 'aurum' }),
      a({ data_compra_importada: '2025-03-02T10:00:00Z', espaco_instrucao: 'holding_masters' }),
      a({ data_compra_importada: '2025-03-20' }),
      a({ data_compra_importada: null }),
    ]);
    expect(s.granularidade).toBe('mes');
    expect(s.colunas.map((c) => [c.rotulo, c.total, c.marco])).toEqual([['jan/25', 1, 'ano'], ['fev/25', 0, null], ['mar/25', 2, null]]);
    expect(s.colunas[2].segs).toEqual([{ key: 'holding_masters', count: 1 }, { key: '__outros__', count: 1 }]);
    expect(s.colunas[2].rotuloLongo).toBe('mar/2025');
  });

  it('anual acima de 36 meses, sem pular ano', () => {
    const s = serieEntrada([a({ data_compra_importada: '2020-05-01' }), a({ data_compra_importada: '2023-06-01' })]);
    expect(s.granularidade).toBe('ano');
    expect(s.colunas.map((c) => [c.rotulo, c.total])).toEqual([['2020', 1], ['2021', 0], ['2022', 0], ['2023', 1]]);
  });

  it('sem datas: série vazia', () => {
    expect(serieEntrada([a({})]).colunas).toEqual([]);
  });
});

describe('ingressos12m', () => {
  it('12 meses até o mês de hoje × os 12 anteriores', () => {
    const r = ingressos12m([
      a({ data_compra_importada: '2026-09-01' }),
      a({ data_compra_importada: '2025-10-15' }),
      a({ data_compra_importada: '2025-09-30' }),
      a({ data_compra_importada: '2024-09-01' }),
      a({ data_compra_importada: '2026-10-01' }),
    ], '2026-09-30');
    expect([r.atual, r.anterior]).toEqual([2, 1]);
    expect(r.meses[11]).toBe(1);
    expect(r.meses[0]).toBe(1);
  });
});
