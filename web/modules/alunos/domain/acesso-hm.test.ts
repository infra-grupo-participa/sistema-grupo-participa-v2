import { describe, it, expect } from 'vitest';
import { hmBadgeTotal, HM_CATEGORIA_LABEL, HM_BUCKETS } from './acesso-hm';

describe('acesso-hm domain', () => {
  it('badge soma só liberações + renovações', () => {
    expect(hmBadgeTotal({ liberacoes: 30, renovacoes: 7, aguardando_diferenca: 38, nao_classificado: 4 })).toBe(37);
  });

  it('badge tolera buckets ausentes', () => {
    expect(hmBadgeTotal({ liberacoes: 5 })).toBe(5);
    expect(hmBadgeTotal({})).toBe(0);
  });

  it('toda categoria do catálogo tem rótulo e tom', () => {
    for (const c of ['compra_cheia', 'renovacao', 'sinal', 'reserva', 'diferenca']) {
      expect(HM_CATEGORIA_LABEL[c]?.label).toBeTruthy();
      expect(HM_CATEGORIA_LABEL[c]?.tone).toBeTruthy();
    }
  });

  it('buckets acionáveis excluem concluído', () => {
    expect(HM_BUCKETS.find((b) => b.key === 'concluido')?.acionavel).toBe(false);
    expect(HM_BUCKETS.find((b) => b.key === 'liberacoes')?.acionavel).toBe(true);
  });
});
