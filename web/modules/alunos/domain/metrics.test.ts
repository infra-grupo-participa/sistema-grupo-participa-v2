import { describe, it, expect } from 'vitest';
import { computeAlunosMetrics } from './metrics';
import type { Aluno360 } from './aluno-360';

const a = (p: Partial<Aluno360>): Aluno360 => ({ id: Math.random().toString(), ...p } as Aluno360);

describe('computeAlunosMetrics', () => {
  const alunos = [
    a({ nivel_resultado: 'ouro', tem_ht: true, tem_hm: true, status_acesso: 'expirado', eh_socio: false, espaco_instrucao: 'holding_masters', estado: 'SP', data_compra_importada: '2025-01-10' }),
    a({ nivel_resultado: 'diamante', tem_hm: true, status_acesso: 'renovado', eh_socio: true, turma_aurum_id: 3, estado: 'SP', data_compra_importada: '2026-02-01' }),
    a({ nivel_resultado: null, status_acesso: 'expirado', eh_socio: false, estado: 'RJ' }),
  ];

  it('conta total, ativos e jornada', () => {
    const m = computeAlunosMetrics(alunos, 'alunos');
    expect(m.total).toBe(3);
    expect(m.ativos).toBe(1); // só 'renovado' conta como ATIVO
    expect(m.ht).toBe(1);
    expect(m.hm).toBe(2);
    expect(m.aurum).toBe(1);
    expect(m.socios).toBe(1);
  });

  it('porEspaco ordena por volume e inclui sem espaço', () => {
    const m = computeAlunosMetrics(alunos, 'alunos');
    expect(m.porEspaco[0].key).toBe('holding_masters'); // único espaço presente
    expect(m.porEspaco.some((d) => d.key === '__none__')).toBe(true); // 2 alunos sem espaço
  });

  it('card do espaço novo vem logo depois do Holding Masters, com titulares × sócios', () => {
    const base = [
      a({ espaco_instrucao: 'holding_masters', eh_socio: false }),
      a({ espaco_instrucao: 'holding_masters_implementacao', eh_socio: false }),
      a({ espaco_instrucao: 'holding_masters_implementacao', eh_socio: false }),
      a({ espaco_instrucao: 'holding_masters_implementacao', eh_socio: true }),
    ];
    const m = computeAlunosMetrics(base, 'alunos');
    expect(m.espacoKpi.map((e) => e.key).slice(0, 2)).toEqual(['holding_masters', 'holding_masters_implementacao']);
    expect(m.espacoKpi.find((e) => e.key === 'holding_masters_implementacao')).toMatchObject({
      label: 'Holding Masters Implementação', total: 3, titulares: 2, socios: 1, color: 'var(--produto-hm)',
    });
    // O espaço novo não pode vazar para o card do Holding Masters.
    expect(m.espacoKpi.find((e) => e.key === 'holding_masters')?.total).toBe(1);
    expect(m.porEspaco.find((d) => d.key === 'holding_masters_implementacao')?.count).toBe(3);
  });

  it('view socios filtra eh_socio', () => {
    const m = computeAlunosMetrics(alunos, 'socios');
    expect(m.total).toBe(1);
  });
});
