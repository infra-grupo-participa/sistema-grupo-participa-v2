import { describe, expect, it } from 'vitest';
import type { FaixaScore, SinalRecuperacao, StatusFila } from '../../domain/types';
import { numerosFila } from './numeros-fila';

const it_ = (faixa: FaixaScore, status: StatusFila, sinais: SinalRecuperacao[] = []) => ({ faixa, status, sinais });

describe('numerosFila', () => {
  it('conta total, ganhos, taxa, em trabalho e sem retorno', () => {
    const n = numerosFila([
      it_('A', 'ganho'),
      it_('A', 'a_abordar', ['respondeu_sem_retorno']),
      it_('B', 'em_conversa', ['respondeu_sem_retorno']),
      it_('C', 'declinou'),
    ]);
    expect(n.total).toBe(4);
    expect(n.ganhos).toBe(1);
    expect(n.taxa).toBe(25);
    expect(n.emTrabalho).toBe(2);
    expect(n.semRetorno).toBe(1);
    expect(n.porFaixa.A).toEqual({ total: 2, aAbordar: 1 });
    expect(n.porFaixa.D).toEqual({ total: 0, aAbordar: 0 });
  });
  it('fila vazia não divide por zero', () => {
    expect(numerosFila([]).taxa).toBe(0);
  });
});
