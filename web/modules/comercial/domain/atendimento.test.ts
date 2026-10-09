import { describe, expect, it } from 'vitest';
import { contaNaFila, contarPorAtendimento, estadoAtendimento, proximosEstados } from './atendimento';

describe('atendimento', () => {
  it('sem o campo conta como aberto; só a aberta entra na fila', () => {
    expect(estadoAtendimento({})).toBe('aberto');
    expect(estadoAtendimento(null)).toBe('aberto');
    expect(contaNaFila({ atendimento: 'aberto' })).toBe(true);
    expect(contaNaFila({ atendimento: 'espera' })).toBe(false);
    expect(contaNaFila({ atendimento: 'encerrado' })).toBe(false);
  });
  it('botões por estado', () => {
    expect(proximosEstados('aberto')).toEqual(['espera', 'encerrado']);
    expect(proximosEstados('espera')).toEqual(['aberto', 'encerrado']);
    expect(proximosEstados('encerrado')).toEqual(['aberto']);
  });
  it('contagem do filtro', () => {
    expect(contarPorAtendimento([{}, { atendimento: 'espera' }, { atendimento: 'encerrado' }, { atendimento: 'aberto' }]))
      .toEqual({ aberto: 2, espera: 1, encerrado: 1 });
  });
});
