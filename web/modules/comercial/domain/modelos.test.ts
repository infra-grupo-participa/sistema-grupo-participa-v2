import { describe, expect, it } from 'vitest';
import { validarFunil } from './funis';
import { MODELOS_FUNIL, MODELOS_PROJETO, chaveProjeto, funilDoModelo, funisDoProjeto } from './modelos';

describe('modelos de funil', () => {
  it('todo modelo gera funil válido', () => {
    for (const m of MODELOS_FUNIL) {
      const f = funilDoModelo(m, { agrupadorId: 'ag', produto: 'hm', chave: 'x', prefixoId: m.id });
      expect(validarFunil(f, []), m.id).toEqual([]);
    }
  });
  it('todo projeto aponta para modelos que existem', () => {
    for (const p of MODELOS_PROJETO) for (const id of p.funis) expect(MODELOS_FUNIL.some((m) => m.id === id), `${p.tipo}:${id}`).toBe(true);
  });
  it('chave do projeto no padrão da casa', () => {
    expect(chaveProjeto('HT34 Meteórico · Out/26')).toBe('ht34-meteorico-out-26');
  });
  it('projeto cria os funis com a chave nas campanhas', () => {
    const fs = funisDoProjeto('lancamento_classico', 'Black Friday 26', { id: 'ag', nome: 'HT', produto: 'ht', ordem: 1 }, 'ht');
    expect(fs.map((f) => f.nome)).toEqual([
      'Black Friday 26 · Captação e MQL', 'Black Friday 26 · Venda ativa', 'Black Friday 26 · Checkout e recuperação', 'Black Friday 26 · Recuperação pós-carrinho',
    ]);
    expect(fs.every((f) => f.projeto === 'black-friday-26')).toBe(true);
    expect(fs[1].campanhas[0].regra).toBe('utm_campaign = black-friday-26');
    expect(new Set(fs.flatMap((f) => f.etapas.map((e) => e.id))).size).toBe(fs.reduce((s, f) => s + f.etapas.length, 0));
  });
});
