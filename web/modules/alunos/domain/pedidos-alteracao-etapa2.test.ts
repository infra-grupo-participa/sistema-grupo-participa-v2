import { describe, expect, it } from 'vitest';
import { abasPedidos, aprovouProprioPedido, ordenarHistorico, type ItemHistoricoAluno } from './pedidos-alteracao';

describe('aba "Aprovar" na tela de pedidos', () => {
  it('só aparece com pode_aprovar verdadeiro', () => {
    expect(abasPedidos({ pode_aprovar: true })).toEqual(['pedir', 'aprovar']);
    expect(abasPedidos({ pode_aprovar: false })).toEqual(['pedir']);
  });
  it('papel que falhou ou ainda não chegou não mostra "Aprovar"', () => {
    expect(abasPedidos(null)).toEqual(['pedir']);
    expect(abasPedidos(undefined)).toEqual(['pedir']);
  });
});

describe('selo "aprovou o próprio pedido"', () => {
  it('aprovado ou aplicado pela mesma pessoa que pediu', () => {
    expect(aprovouProprioPedido({ autoaprovado: true, status: 'aplicado' })).toBe(true);
    expect(aprovouProprioPedido({ autoaprovado: true, status: 'aprovado' })).toBe(true);
  });
  it('recusa do próprio pedido não é aprovação', () => {
    expect(aprovouProprioPedido({ autoaprovado: true, status: 'recusado' })).toBe(false);
  });
  it('sem decisão, outra pessoa, ou campo ausente (migration não aplicada): sem selo', () => {
    expect(aprovouProprioPedido({ autoaprovado: true, status: 'pendente' })).toBe(false);
    expect(aprovouProprioPedido({ autoaprovado: false, status: 'aplicado' })).toBe(false);
    expect(aprovouProprioPedido({ autoaprovado: null, status: 'aplicado' })).toBe(false);
    expect(aprovouProprioPedido({ status: 'aplicado' })).toBe(false);
  });
});

describe('histórico do aluno', () => {
  const it_ = (em: string, pedido_id: number): ItemHistoricoAluno => ({ em, pedido_id, papel: 'aluno', texto: `p${pedido_id}` });
  it('mais recente primeiro, sem mexer na lista recebida', () => {
    const l = [it_('2026-10-01T10:00:00Z', 1), it_('2026-10-06T09:00:00-03:00', 3), it_('2026-10-03T00:00:00Z', 2)];
    expect(ordenarHistorico(l).map((x) => x.pedido_id)).toEqual([3, 2, 1]);
    expect(l.map((x) => x.pedido_id)).toEqual([1, 3, 2]);
  });
  it('mesmo instante (os 3 textos de uma troca): pedido maior primeiro, ordem estável dentro do pedido', () => {
    const em = '2026-10-06T12:00:00Z';
    const l: ItemHistoricoAluno[] = [
      { em, pedido_id: 9, papel: 'titular', texto: 'a' },
      { em, pedido_id: 10, papel: 'sai', texto: 'b' },
      { em, pedido_id: 9, papel: 'entra', texto: 'c' },
    ];
    expect(ordenarHistorico(l).map((x) => x.texto)).toEqual(['b', 'a', 'c']);
  });
  it('data ilegível vai para o fim, não some', () => {
    const l = [it_('lixo', 7), it_('2026-10-01T10:00:00Z', 1)];
    expect(ordenarHistorico(l).map((x) => x.pedido_id)).toEqual([1, 7]);
  });
});
