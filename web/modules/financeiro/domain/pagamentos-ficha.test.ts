import { describe, expect, it } from 'vitest';
import { juntarPagamentos, resumirPagamentos } from './pagamentos-ficha';
import type { Lancamento } from './types';
import type { TransacaoHotmart } from './hotmart';

const lanc = (o: Partial<Lancamento>): Lancamento => ({
  id: 'l1', categoria: 'sinal', valor_bruto: 300, valor_liquido: 287, taxas: 13, juros_parcelamento: 0,
  pago_em: '2026-07-26', origem: 'hotmart', transacao: 'HP1', oferta_codigo: 'z391kxd9', metodo_pagamento: 'PIX',
  parcela: 1, obs: null, autor: 'webhook', ...o,
} as Lancamento);
const tx = (o: Partial<TransacaoHotmart>): TransacaoHotmart => ({
  transacao: 'HP1', email: 'a@b', produto: 'Holding Masters', oferta_codigo: 'z391kxd9', status: 'APPROVED', grupo: 'pago',
  metodo: 'PIX', parcelas: 1, recorrencia: null, valor_oferta: 300, cobrado: 300, juros: 0, taxa_hotmart: 13, liquido: 287,
  liquido_estimado: false, pedido_em: '2026-07-26T10:00:00Z', aprovado_em: '2026-07-26T10:01:00Z', garantia_ate: null, origem_sck: null, ...o,
});

describe('juntarPagamentos', () => {
  it('a mesma venda aparece uma vez, marcada como Hotmart e board', () => {
    const r = juntarPagamentos([lanc({})], [tx({})]);
    expect(r).toHaveLength(1);
    expect(r[0].fonte).toBe('hotmart_e_board');
    expect(r[0].categoriaBoard).toBe('sinal');
  });
  it('venda paga só na Hotmart e lançamento manual só no board aparecem, cada um com sua marca, do mais novo ao mais antigo', () => {
    const r = juntarPagamentos(
      [lanc({ id: 'l2', transacao: null, pago_em: '2026-08-10', origem: 'manual', valor_bruto: 1000 })],
      [tx({ transacao: 'HP9', aprovado_em: '2026-09-01T00:00:00Z', valor_oferta: 11000 })],
    );
    expect(r.map((p) => p.fonte)).toEqual(['so_hotmart', 'so_board']);
    const s = resumirPagamentos(r);
    expect(s.valorPago).toBe(12000);
    expect(s.foraDoBoard).toBe(1);
    expect(s.valorForaDoBoard).toBe(11000);
  });
  it('tentativa recusada conta como tentativa, não como pago', () => {
    const s = resumirPagamentos(juntarPagamentos([], [tx({ grupo: 'recusado', aprovado_em: null })]));
    expect(s.pagos).toBe(0);
    expect(s.tentativas).toBe(1);
  });
});
