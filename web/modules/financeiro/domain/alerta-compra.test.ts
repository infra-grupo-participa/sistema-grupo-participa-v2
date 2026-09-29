import { describe, it, expect } from 'vitest';
import { alertaCompraCheia, temContrato } from './alerta-compra';
import type { BoletoAberto } from './hotmart';

const brl = (n: number) => `R$ ${n.toLocaleString('pt-BR')}`;

function boleto(over: Partial<BoletoAberto> = {}): BoletoAberto {
  return { valor: 15000, categoria: 'compra_cheia', rotulo: 'compra_cheia', oferta_codigo: 'x', metodo: 'BILLET', pedido_em: '2026-09-26', ...over };
}

const HT30 = { sinal_bruto: 697, pacote: 15000, total_pago_bruto: 697, saldo_a_pagar: 14303 };

describe('alertaCompraCheia', () => {
  it('HT30: sinal 697, pacote 15.000, boleto cheio 15.000 → paga R$ 697 a mais, saldo R$ 14.303', () => {
    const a = alertaCompraCheia(HT30, [boleto()], brl)!;
    expect(a.aMais).toBe(697);
    expect(a.saldo).toBe(14303);
    expect(a.texto).toBe(
      'Boleto do HM cheio não desconta o que já foi pago: se pagar, paga R$ 697 a mais. '
      + 'Mande o link do saldo de R$ 14.303: peça ao comercial um link do saldo nesse valor.',
    );
    expect(a.curto).toBe('Boleto cheio · R$ 697 a mais');
  });

  it('card sem contrato (sem sinal, sem pago) com boleto compra_cheia → sem alerta', () => {
    const semContrato = { sinal_bruto: null, pacote: null, total_pago_bruto: 0, saldo_a_pagar: null };
    expect(temContrato(semContrato)).toBe(false);
    expect(alertaCompraCheia(semContrato, [boleto()], brl)).toBeNull();
    // pacote definido mas nada pago também não é contrato em curso
    expect(alertaCompraCheia({ ...semContrato, pacote: 15000, saldo_a_pagar: 15000 }, [boleto()], brl)).toBeNull();
  });

  it("boleto 'diferenca' (link do saldo) → sem alerta", () => {
    expect(alertaCompraCheia(HT30, [boleto({ categoria: 'diferenca', valor: 14303 })], brl)).toBeNull();
  });

  it('FALSO medido em produção: parcela da compra cheia parcelada (pago 2.552,28 + boleto 1.276,14 < pacote 15.000) → sem alerta', () => {
    const c = { sinal_bruto: 0, pacote: 15000, total_pago_bruto: 2552.28, saldo_a_pagar: 12447.72 };
    expect(alertaCompraCheia(c, [boleto({ valor: 1276.14 })], brl)).toBeNull();
  });

  it('com pacote, boleto que fecha o pacote exato (a mais = 0) → sem alerta', () => {
    expect(alertaCompraCheia({ ...HT30, total_pago_bruto: 0 }, [boleto()], brl)).toBeNull();
  });

  it('sem boleto / lista null → sem alerta', () => {
    expect(alertaCompraCheia(HT30, null, brl)).toBeNull();
    expect(alertaCompraCheia(HT30, [], brl)).toBeNull();
  });

  it('compra cheia inferida fora do catálogo (categoria null) → sem alerta: a regra é só a categoria do catálogo', () => {
    expect(alertaCompraCheia(HT30, [boleto({ categoria: null, rotulo: 'compra_cheia_inferida' })], brl)).toBeNull();
  });

  it('usa o compra_cheia mais recente mesmo com outro boleto antes na lista', () => {
    const a = alertaCompraCheia(HT30, [boleto({ categoria: 'sinal', valor: 697 }), boleto({ metodo: 'PIX' })], brl)!;
    expect(a.boleto).toBe(15000);
    expect(a.curto).toBe('Pix cheio · R$ 697 a mais');
  });

  it('contrato por pacote + pago, sem sinal → dispara', () => {
    const a = alertaCompraCheia({ sinal_bruto: 0, pacote: 15000, total_pago_bruto: 5000, saldo_a_pagar: 10000 }, [boleto()], brl)!;
    expect(a.aMais).toBe(5000);
    expect(a.saldo).toBe(10000);
  });

  it('sinal pago sem pacote definido → dispara sem inventar o "a mais" e sem saldo', () => {
    const a = alertaCompraCheia({ sinal_bruto: 697, pacote: null, total_pago_bruto: 697, saldo_a_pagar: null }, [boleto()], brl)!;
    expect(a.aMais).toBeNull();
    expect(a.saldo).toBeNull();
    expect(a.texto).toBe('Boleto do HM cheio não desconta o que já foi pago (R$ 697). Peça ao comercial um link do saldo.');
  });
});
