import { describe, it, expect } from 'vitest';
import { explicarProrata, inicioDoCiclo, normalizarProrataHM, prorataDoCard, simularProrata } from './prorata-hm';
import type { BoardHotmart, ProrataHM } from './hotmart';

function pr(over: Partial<ProrataHM> = {}): ProrataHM {
  return {
    pessoa_chave: 'p1', nome: 'Carlos Roberto Elias da Silva', email: null, turma: 'T34',
    vencimento: '2026-10-05', meses_restantes: 0, pago_no_ciclo: 23964, pagamentos_no_ciclo: 12,
    formas: '12 mensalidades', credito: 0, diferenca: 15000, ultimo_pagamento: '2026-09-03',
    tem_card: true, contato_hm_id: 'c1', no_gps: false,
    ...over,
  };
}
const hm = (over: Partial<BoardHotmart> = {}) => ({ origem: 'HM', pessoa_chave: 'p1', ...over }) as BoardHotmart;

describe('normalizarProrataHM', () => {
  it('numeric string → number (caso Carlos: crédito 0, diferença 15.000)', () => {
    const n = normalizarProrataHM(pr({ credito: '0.00' as unknown as number, diferenca: '15000.00' as unknown as number }));
    expect(n.credito).toBe(0);
    expect(n.diferenca).toBe(15000);
  });
});

describe('prorataDoCard', () => {
  it('acha pelo contato_hm_id', () => {
    expect(prorataDoCard([pr()], 'c1', hm())?.turma).toBe('T34');
  });
  it('2º card HM da mesma pessoa acha pela pessoa_chave', () => {
    expect(prorataDoCard([pr()], 'c2', hm())?.turma).toBe('T34');
  });
  it('card AURUM não herda pro rata do HM', () => {
    expect(prorataDoCard([pr()], 'c2', hm({ origem: 'AURUM' }))).toBeNull();
  });
  it('sem linha → null', () => {
    expect(prorataDoCard([], 'c1', hm())).toBeNull();
    expect(prorataDoCard([pr({ contato_hm_id: null, pessoa_chave: 'outra' })], 'c1', hm())).toBeNull();
  });
});

describe('inicioDoCiclo', () => {
  it('vencimento − 12 meses − 60 dias', () => {
    expect(inicioDoCiclo('2026-12-31')).toBe('2025-11-01');
    expect(inicioDoCiclo('2026-10-05')).toBe('2025-08-06');
  });
});

describe('explicarProrata', () => {
  const base = { pagamentos: 1, vencimento: '2026-12-31', inicioCiclo: '2025-11-01', valorPrograma: 15000 };
  it('Marcio: pagou 3.997, faltam 3 meses → crédito 999,25 → paga 14.000,75', () => {
    const t = explicarProrata({ ...base, pago: 3997, meses: 3, credito: 999.25, diferenca: 14000.75 });
    expect(t).toContain('R$ 3.997,00');
    expect(t).toContain('3 meses cheios');
    expect(t).toContain('R$ 999,25');
    expect(t).toContain('paga R$ 14.000,75');
  });
  it('Carlos: pagou 23.964 mas 0 mês cheio → valor cheio', () => {
    const t = explicarProrata({ ...base, pago: 23964, pagamentos: 12, meses: 0, credito: 0, diferenca: 15000 });
    expect(t).toContain('não vira crédito');
    expect(t).toContain('R$ 15.000,00');
  });
  it('sem pagamento no ciclo → valor cheio e confirmar com a Isabela', () => {
    expect(explicarProrata({ ...base, pago: 0, meses: 5, credito: 0, diferenca: 15000 })).toContain('Isabela');
  });
});

describe('simularProrata (mesma regra do banco)', () => {
  it('Marcio: 3.997 × 3 ÷ 12 = 999,25 → 14.000,75', () => {
    expect(simularProrata(3997, 3)).toEqual({ credito: 999.25, diferenca: 14000.75 });
  });
  it('trunca no centavo e nunca paga negativo', () => {
    expect(simularProrata(1000, 1).credito).toBe(83.33);
    expect(simularProrata(200000, 11).diferenca).toBe(0);
  });
  it('0 mês cheio → valor cheio', () => {
    expect(simularProrata(23964, 0)).toEqual({ credito: 0, diferenca: 15000 });
  });
});
