import { describe, it, expect } from 'vitest';
import { COR_POR_STATUS, corStatus, ROTULO_COR } from './cor-status';
import type { StatusFinanceiro } from './types';

describe('corStatus', () => {
  it('verde: quitado, em_pagamento', () => {
    for (const s of ['quitado', 'em_pagamento'] as StatusFinanceiro[]) {
      expect(corStatus(s)).toBe('verde');
    }
  });

  it('azul: sem_acordo, oferta_enviada, a_vencer, futuro, incalculavel', () => {
    for (const s of ['sem_acordo', 'oferta_enviada', 'a_vencer', 'futuro', 'incalculavel'] as StatusFinanceiro[]) {
      expect(corStatus(s)).toBe('azul');
    }
  });

  it('amarelo: vencido', () => {
    expect(corStatus('vencido' as StatusFinanceiro)).toBe('amarelo');
  });

  it('vermelho: cancelado, reembolsado, cancelamento_solicitado', () => {
    for (const s of ['cancelado', 'reembolsado', 'cancelamento_solicitado'] as StatusFinanceiro[]) {
      expect(corStatus(s)).toBe('vermelho');
    }
  });

  it('exaustividade: COR_POR_STATUS cobre os 11 status', () => {
    expect(Object.keys(COR_POR_STATUS).length).toBe(11);
  });

  it('neutro é inalcançável por status conhecido — só fallback de status desconhecido', () => {
    expect(Object.values(COR_POR_STATUS).every((c) => c !== 'neutro')).toBe(true);
  });

  it('fallback: status desconhecido vindo do banco vira neutro', () => {
    expect(corStatus('status_que_o_banco_inventou')).toBe('neutro');
  });
});

describe('ROTULO_COR', () => {
  it('tem rótulo para as 5 cores, incluindo neutro', () => {
    expect(Object.keys(ROTULO_COR).sort()).toEqual(['amarelo', 'azul', 'neutro', 'verde', 'vermelho'].sort());
  });
});
