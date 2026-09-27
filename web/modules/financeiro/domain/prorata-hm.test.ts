import { describe, it, expect } from 'vitest';
import { normalizarProrataHM, prorataDoCard } from './prorata-hm';
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
