import { describe, it, expect } from 'vitest';
import { hmBadgeTotal, HM_CATEGORIA_LABEL, HM_BUCKETS, turmaPendente, type HmFilaItem } from './acesso-hm';

const base: HmFilaItem = {
  compraId: 'x', alunoId: null, compradorId: null, nome: 'T', email: null, telefone: null,
  offerCode: null, ofertaLabel: null, categoria: 'compra_cheia', preco: null, dataCompra: null,
  bucket: 'pendente', alunoNovo: true, turmaId: null, turmaCodigo: null,
  acessoEm: null, acessoPorNome: null, ignoradoEm: null, obs: null,
};

describe('acesso-hm domain', () => {
  it('badge conta só pendentes', () => {
    expect(hmBadgeTotal({ pendente: 12, concluido: 40 })).toBe(12);
    expect(hmBadgeTotal({})).toBe(0);
  });

  it('toda categoria do catálogo tem rótulo e tom', () => {
    for (const c of ['compra_cheia', 'renovacao', 'sinal', 'reserva', 'diferenca']) {
      expect(HM_CATEGORIA_LABEL[c]?.label).toBeTruthy();
      expect(HM_CATEGORIA_LABEL[c]?.tone).toBeTruthy();
    }
  });

  it('só concluídos são não-acionáveis', () => {
    expect(HM_BUCKETS.find((b) => b.key === 'concluido')?.acionavel).toBe(false);
    expect(HM_BUCKETS.find((b) => b.key === 'pendente')?.acionavel).toBe(true);
  });

  it('turma pendente só para aluno novo sem turma', () => {
    expect(turmaPendente({ ...base, alunoNovo: true, turmaId: null })).toBe(true);
    expect(turmaPendente({ ...base, alunoNovo: true, turmaId: 53 })).toBe(false);
    expect(turmaPendente({ ...base, alunoNovo: false, turmaId: null })).toBe(false);
  });
});
