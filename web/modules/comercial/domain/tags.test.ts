import { describe, expect, it } from 'vitest';
import { aplicarTags, normalizarTag, tagsDoTexto } from './tags';

describe('tags do contato (espelho de crm.tag_normalizar)', () => {
  it('normaliza igual ao banco', () => {
    expect(normalizarTag('  Quente Ágora!! ')).toBe('quente-agora');
    expect(normalizarTag('[HT] ALUNOS')).toBe('ht-alunos');
    expect(normalizarTag('Ação São João')).toBe('acao-sao-joao');
    expect(normalizarTag('🔔')).toBeNull();
    const longa = normalizarTag('ab '.repeat(30))!;
    expect(longa.length).toBeLessThanOrEqual(40);
    expect(longa.endsWith('-')).toBe(false);
  });
  it('texto livre vira lista sem repetir', () => {
    expect(tagsDoTexto('VIP, quente; vip\nHT 30')).toEqual(['vip', 'quente', 'ht-30']);
  });
  it('aplicar: remove pela forma normalizada (tag importada crua) e adiciona só o que falta', () => {
    expect(aplicarTags(['[HT] ALUNOS', 'vip'], ['Quente', 'VIP'], ['ht alunos'])).toEqual({ tags: ['vip', 'quente'], erro: null });
  });
  it('aplicar: add e remove a mesma, e mais de 30, recusam', () => {
    expect(aplicarTags([], ['a'], ['A']).erro).toMatch(/mesma tag/);
    const trinta = Array.from({ length: 30 }, (_, i) => `t${i}`);
    expect(aplicarTags(trinta, ['nova'], []).erro).toMatch(/Máximo de 30/);
  });
});
