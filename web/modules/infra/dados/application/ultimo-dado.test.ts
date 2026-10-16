import { describe, expect, it } from 'vitest';
import { manterUltimaLeituraAtm, manterUltimoDado } from './ultimo-dado';

describe('manterUltimoDado', () => {
  it('preserva o último resultado em falha de leitura', () => {
    expect(manterUltimoDado({ data: { vendas: 3 }, erro: null }, { data: null, erro: 'Sem acesso' }))
      .toEqual({ data: { vendas: 3 }, erro: 'Sem acesso' });
  });

  it('aceita uma lista vazia válida e não a troca pelo resultado anterior', () => {
    expect(manterUltimoDado({ data: [1], erro: null }, { data: [], erro: null }))
      .toEqual({ data: [], erro: null });
  });

  it('mantém ausência de dado como ausência, sem fabricar zero', () => {
    expect(manterUltimoDado(null, { data: null, erro: 'Falha' }))
      .toEqual({ data: null, erro: 'Falha' });
  });
});

describe('manterUltimaLeituraAtm', () => {
  it('em falha (semDado) mantém a última lista e só troca o aviso', () => {
    expect(manterUltimaLeituraAtm({ data: [1], semDado: false, erro: null }, { data: [], semDado: true, erro: 'Falha' }))
      .toEqual({ data: [1], semDado: false, erro: 'Falha' });
  });

  it('leitura válida, mesmo vazia, substitui a anterior', () => {
    expect(manterUltimaLeituraAtm({ data: [1], semDado: false, erro: 'Falha' }, { data: [], semDado: false, erro: null }))
      .toEqual({ data: [], semDado: false, erro: null });
  });
});
