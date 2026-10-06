import { describe, expect, it } from 'vitest';
import type { FaixaScore, SinalRecuperacao, StatusFila } from '../../domain/types';
import { grupoPrioridade, itemLiberado, ordenarFila, pendentesAB } from './ordem-fila';

const item = (id: string, sinais: SinalRecuperacao[], score = 50, status: StatusFila = 'a_abordar') => ({ id, sinais, score, status });

describe('grupoPrioridade', () => {
  it('segue a ordem do playbook', () => {
    expect(grupoPrioridade(['respondeu_sem_retorno', 'carrinho'])).toBe(1);
    expect(grupoPrioridade(['ficha_completa', 'senhas'])).toBe(2);
    expect(grupoPrioridade(['senhas', 'chat'])).toBe(3);
    expect(grupoPrioridade(['cartao_recusado'])).toBe(4);
    expect(grupoPrioridade(['boleto_aberto'])).toBe(5);
    expect(grupoPrioridade(['ficha_completa', 'quer_parceria'])).toBe(6);
    expect(grupoPrioridade(['carrinho', 'chat'])).toBe(7);
  });

  it('carrinho sozinho, ficha sem parceria e sem sinal caem no resto', () => {
    expect(grupoPrioridade(['carrinho'])).toBe(8);
    expect(grupoPrioridade(['ficha_completa'])).toBe(8);
    expect(grupoPrioridade([])).toBe(8);
  });
});

describe('ordenarFila', () => {
  it('ordena por grupo e, dentro do grupo, por score decrescente', () => {
    const r = ordenarFila([
      item('a', ['carrinho'], 99),
      item('b', ['boleto_aberto'], 40),
      item('c', ['senhas'], 30),
      item('d', ['senhas'], 70),
      item('e', ['respondeu_sem_retorno'], 10),
    ]);
    expect(r.map((i) => i.id)).toEqual(['e', 'd', 'c', 'b', 'a']);
  });

  it('manda encerrados para o fim e não altera a entrada', () => {
    const entrada = [item('x', ['respondeu_sem_retorno'], 90, 'ganho'), item('y', [], 5)];
    const r = ordenarFila(entrada);
    expect(r.map((i) => i.id)).toEqual(['y', 'x']);
    expect(entrada[0].id).toBe('x');
  });
});

describe('prioridade de faixa', () => {
  const f = (faixa: FaixaScore, status: StatusFila = 'a_abordar') => ({ faixa, status });

  it('conta só A/B ainda a abordar', () => {
    expect(pendentesAB([f('A'), f('B', 'tentando_contato'), f('C'), f('B')])).toBe(2);
  });

  it('trava C e D enquanto houver A/B a abordar', () => {
    const fila = [f('A'), f('C')];
    expect(itemLiberado('A', fila)).toBe(true);
    expect(itemLiberado('C', fila)).toBe(false);
    expect(itemLiberado('D', [f('A', 'em_conversa'), f('D')])).toBe(true);
  });
});
