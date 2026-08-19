import { describe, it, expect } from 'vitest';
import { calcularTotais } from './totais';
import type { ContaReceber, StatusFinanceiro } from './types';

function conta(over: Partial<ContaReceber> = {}): ContaReceber {
  return {
    contato_hm_id: 'c1', comprador_id: 'p1', aluno_id: null,
    nome: 'Fulano', email: 'f@x.com', telefone: null, documento: null,
    turma: 'T39', turma_origem: null, canal: 'HT ATM', publico: 'lead_novo', tags: [],
    estagio_nome: null, estagio_aba: null, estagio_id: null,
    produto: 'Holding Masters',
    vendedor: null, reuniao_em: null, reuniao_resultado: null,
    entrevista_em: null, entrevista_resultado: null, obs_comercial: null,
    solicitou_cancelamento: false,
    sinal_bruto: 300, sinal_liquido: 287, sinal_taxas: 13,
    sinal_pago_em: '2026-07-01', sinal_metodo: 'PIX', sinal_transacao: 'TX1',
    saldo_pago_bruto: 0, saldo_pago_liquido: 0, saldo_taxas: 0,
    saldo_pago_em: null, saldo_metodo: null, saldo_lancamentos: 0,
    total_pago_bruto: 300, total_pago_liquido: 287,
    pacote: 15000, pacote_regra: 15000, divergencia_regra: null,
    credito: null, saldo_a_pagar: 14700, pago_pct: 2,
    vencimento: null, acordo: null, pagamento_meio: null, pagamento_forma: null,
    pagamento_parcelas: null, parcelas_pagas: 0, parcelas_contratadas: null,
    valor_parcela: null, dias_atraso: null,
    oferta_codigo: null, oferta_valor: null, oferta_link: null,
    oferta_recorrente: null, oferta_enviada_em: null,
    cancelamento_em: null, cancelamento_motivo: null, cancelamento_efetivado_em: null,
    quitado_em: null, reembolso_em: null, reembolso_status: null, reembolso_valor: null,
    ultimo_pagamento_em: null, situacao_ativacao: null,
    status_financeiro: 'sem_acordo' as StatusFinanceiro,
    ultima_cobranca_em: null, cobrancas_total: 0, remarcacoes: 0,
    ...over,
  };
}

describe('calcularTotais — lista vazia', () => {
  it('zera tudo, mas isso é distinguível de "tudo pago" pelo consumidor (nenhuma métrica finge ter varrido dados)', () => {
    const t = calcularTotais([]);
    expect(t).toEqual({
      emCasa: 0, emCasaLiquido: 0, naRua: 0, perda: 0,
      perdaDetalhe: { devolvido: 0, naoRealizado: 0 },
      esperado: 0,
      semValorDefinido: 0, reservas: 0, segundaMetade: { valor: 0, parceiros: 0 },
    });
  });
});

describe('calcularTotais — EM CASA nunca usa status como fonte de valor', () => {
  it('85 "quitado com saldo positivo": entra em EM CASA pelo bruto pago, e o saldo entra em NA RUA (não em PERDA nem ignorado)', () => {
    // Reproduz o furo medido: quitado_em setado, mas saldo_a_pagar > 0 (view
    // prioriza timestamp sobre saldo). status_financeiro='quitado' não pode
    // decidir sozinho se a conta é "encerrada" para fins de totais.
    const c = conta({
      status_financeiro: 'quitado', total_pago_bruto: 12000, total_pago_liquido: 11500,
      saldo_a_pagar: 2727.5, // parte dos R$ 231.637,57 medidos em 85 contas
    });
    const t = calcularTotais([c]);
    expect(t.emCasa).toBe(12000);
    expect(t.emCasaLiquido).toBe(11500);
    expect(t.naRua).toBe(2727.5); // viva (status quitado não é contaMorta) com saldo real
    expect(t.perda).toBe(0);
  });

  it('conta morta (cancelado/reembolsado) entra só em EM CASA e PERDA, nunca em NA RUA', () => {
    const cancelado = conta({
      status_financeiro: 'cancelado', total_pago_bruto: 5000, total_pago_liquido: 4800, saldo_a_pagar: 9700,
    });
    const reembolsado = conta({
      status_financeiro: 'reembolsado', total_pago_bruto: 3000, total_pago_liquido: 2900,
      saldo_a_pagar: 0, reembolso_em: '2026-08-01T00:00:00Z', reembolso_valor: 3000,
    });
    const t = calcularTotais([cancelado, reembolsado]);
    expect(t.emCasa).toBe(8000); // 5000 + 3000 — o que pagaram é real
    expect(t.naRua).toBe(0); // morta nunca entra aqui
    expect(t.perda).toBe(9700 + 3000);
    // As duas parcelas são de natureza distinta e ficam separadas no detalhe.
    expect(t.perdaDetalhe.naoRealizado).toBe(9700); // saldo do cancelado, nunca vai entrar
    expect(t.perdaDetalhe.devolvido).toBe(3000); // saiu do caixa de volta
  });

  it('devolvido usa total_pago_bruto, não reembolso_valor (compras.preco é a PARCELA em parcelada)', () => {
    // Cenário real: compra em 12x estornada. reembolso_valor vem de
    // sum(compras.preco) e traz só a parcela (R$ 1.225), enquanto a pessoa
    // pagou R$ 14.700. Usar reembolso_valor subestimaria a perda em 12x.
    const parcelada = conta({
      status_financeiro: 'reembolsado', total_pago_bruto: 14700, total_pago_liquido: 14000,
      saldo_a_pagar: 0, reembolso_em: '2026-08-01T00:00:00Z', reembolso_valor: 1225,
    });
    const t = calcularTotais([parcelada]);
    expect(t.perdaDetalhe.devolvido).toBe(14700); // o que de fato pagou, não a parcela
    expect(t.perda).toBe(14700);
  });

  it('conta morta sem reembolso efetivado não conta como devolvido (só o saldo não realizado)', () => {
    const canceladoSemReembolso = conta({
      status_financeiro: 'cancelado', total_pago_bruto: 2000, total_pago_liquido: 1900,
      saldo_a_pagar: 13000, reembolso_em: null,
    });
    const t = calcularTotais([canceladoSemReembolso]);
    expect(t.perdaDetalhe.devolvido).toBe(0); // o dinheiro dele continua conosco
    expect(t.perdaDetalhe.naoRealizado).toBe(13000);
    expect(t.emCasa).toBe(2000); // e segue contado como recebido
  });
});

describe('calcularTotais — saldo NULL (Aurum com exceção) não vira 0 silenciosamente', () => {
  it('conta viva com saldo_a_pagar NULL não soma em NA RUA e é contada em semValorDefinido', () => {
    const c = conta({ status_financeiro: 'incalculavel', saldo_a_pagar: null, total_pago_bruto: 300 });
    const t = calcularTotais([c]);
    expect(t.naRua).toBe(0);
    expect(t.semValorDefinido).toBe(1);
    expect(t.emCasa).toBe(300); // o que já pagou continua contando
  });

  it('mistura: NULL não contamina a soma das demais contas', () => {
    const t = calcularTotais([
      conta({ saldo_a_pagar: null, total_pago_bruto: 300 }),
      conta({ saldo_a_pagar: 5000, total_pago_bruto: 300 }),
    ]);
    expect(t.naRua).toBe(5000);
    expect(t.semValorDefinido).toBe(1);
  });
});

describe('calcularTotais — reserva de vaga entra em NA RUA e é contada separadamente', () => {
  it('reserva (só sinal, nada do saldo) soma em naRua e incrementa reservas', () => {
    const c = conta({
      status_financeiro: 'sem_acordo', sinal_bruto: 300, saldo_pago_bruto: 0, saldo_a_pagar: 14700,
      total_pago_bruto: 300,
    });
    const t = calcularTotais([c]);
    expect(t.naRua).toBe(14700);
    expect(t.reservas).toBe(1);
  });

  it('quem já pagou algo do saldo não conta como reserva', () => {
    const c = conta({ sinal_bruto: 300, saldo_pago_bruto: 1225, saldo_a_pagar: 13475 });
    const t = calcularTotais([c]);
    expect(t.reservas).toBe(0);
    expect(t.naRua).toBe(13475);
  });
});

describe('calcularTotais — esperado e tolerância de centavos', () => {
  it('esperado = emCasa + naRua', () => {
    const t = calcularTotais([
      conta({ total_pago_bruto: 1000, saldo_a_pagar: 500 }),
      conta({ total_pago_bruto: 2000, saldo_a_pagar: 1500 }),
    ]);
    expect(t.esperado).toBe(t.emCasa + t.naRua);
    expect(t.esperado).toBe(3000 + 2000);
  });

  it('resíduo de centavos (<R$1) não aparece em naRua nem perda (saldoEfetivo)', () => {
    const viva = conta({ status_financeiro: 'a_vencer', saldo_a_pagar: 0.03 });
    const morta = conta({ status_financeiro: 'cancelado', saldo_a_pagar: 0.02 });
    const t = calcularTotais([viva, morta]);
    expect(t.naRua).toBe(0);
    expect(t.perda).toBe(0);
  });
});

describe('calcularTotais — 2ª metade condicional fica fora dos 4 totais', () => {
  it('segundaMetade é exposta separada e não soma em esperado', () => {
    const c = conta({ status_financeiro: 'quitado', saldo_pago_bruto: 14700, saldo_a_pagar: 0, total_pago_bruto: 15000 });
    const t = calcularTotais([c]);
    expect(t.segundaMetade).toEqual({ valor: 15000, parceiros: 1 });
    // esperado não inflou com a condicional:
    expect(t.esperado).toBe(t.emCasa + t.naRua);
  });
});
