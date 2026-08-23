import { describe, it, expect } from 'vitest';
import { motivoUrgencia, urgencia } from './board';
import type { ContaReceber, ReguaPasso, StatusFinanceiro } from './types';

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

const REGUA_VAZIA: ReguaPasso[] = [];
const REGUA: ReguaPasso[] = [
  { ordem: 1, offset_dias: -3, titulo: 'Lembrete antes do vencimento', canal: 'whatsapp', ativo: true },
  { ordem: 2, offset_dias: 0, titulo: 'Cobrar no vencimento', canal: 'whatsapp', ativo: true },
  { ordem: 3, offset_dias: 5, titulo: 'Cobrar 5 dias depois', canal: 'whatsapp', ativo: true },
];

describe('urgencia', () => {
  it('0: conta morta', () => {
    expect(urgencia(conta({ status_financeiro: 'cancelado', saldo_a_pagar: 14700 }), REGUA_VAZIA, '2026-08-19')).toBe(0);
    expect(urgencia(conta({ status_financeiro: 'reembolsado', saldo_a_pagar: 14700 }), REGUA_VAZIA, '2026-08-19')).toBe(0);
  });

  it('0: quitada sem saldo', () => {
    expect(urgencia(conta({ status_financeiro: 'quitado', saldo_a_pagar: 0 }), REGUA_VAZIA, '2026-08-19')).toBe(0);
  });

  it('0: dentro do prazo, sem sinal de risco', () => {
    const c = conta({ status_financeiro: 'a_vencer', saldo_a_pagar: 5000, dias_atraso: null, vencimento: '2026-09-01' });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(0);
  });

  it('1: saldo positivo sem prazo definido (sem_acordo) — a dor silenciosa', () => {
    const c = conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 14700, dias_atraso: null });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(1);
  });

  it('1: saldo positivo sem prazo definido (incalculavel)', () => {
    const c = conta({ status_financeiro: 'incalculavel', saldo_a_pagar: null, dias_atraso: null });
    // saldo_a_pagar null -> saldoEfetivo 0 -> não entra em urgência por saldo > 0.
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(0);
  });

  it('2: dias_atraso entre 1 e 30', () => {
    const c = conta({ status_financeiro: 'vencido', saldo_a_pagar: 5000, dias_atraso: 15 });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(2);
  });

  it('2: proximaAcao atrasada com saldo > 0, mesmo sem dias_atraso', () => {
    const c = conta({
      status_financeiro: 'a_vencer', saldo_a_pagar: 5000, dias_atraso: null, vencimento: '2026-08-01',
    });
    // vencimento no passado, sem cobrança registrada -> régua acusa atraso.
    expect(urgencia(c, REGUA, '2026-08-19')).toBe(2);
  });

  it('3: dias_atraso > 30', () => {
    const c = conta({ status_financeiro: 'vencido', saldo_a_pagar: 5000, dias_atraso: 31 });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(3);
  });

  it('3: cancelamento solicitado, mesmo sem atraso', () => {
    const c = conta({ status_financeiro: 'cancelamento_solicitado', saldo_a_pagar: 5000, dias_atraso: 0 });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(3);
  });

  it('3: solicitou_cancelamento (flag) mesmo com outro status', () => {
    const c = conta({ status_financeiro: 'em_pagamento', solicitou_cancelamento: true, saldo_a_pagar: 5000 });
    expect(urgencia(c, REGUA_VAZIA, '2026-08-19')).toBe(3);
  });

  it('nenhum sinal isolado decide: dias_atraso null em sem_acordo não vira 0 nem 3, vira 1', () => {
    const c = conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 2300, dias_atraso: null, vencimento: null });
    expect(urgencia(c, REGUA, '2026-08-19')).toBe(1);
  });
});

// Mesmos casos do describe('urgencia') acima — a bijeção é o que impede o
// aria-label (motivoUrgencia) de mentir quando urgencia() mudar.
describe('motivoUrgencia — bijeção com urgencia()', () => {
  const HOJE = '2026-08-19';
  const casos: { titulo: string; c: ContaReceber; regua: ReguaPasso[] }[] = [
    { titulo: '0: conta morta (cancelado)', c: conta({ status_financeiro: 'cancelado', saldo_a_pagar: 14700 }), regua: REGUA_VAZIA },
    { titulo: '0: conta morta (reembolsado)', c: conta({ status_financeiro: 'reembolsado', saldo_a_pagar: 14700 }), regua: REGUA_VAZIA },
    { titulo: '0: quitada sem saldo', c: conta({ status_financeiro: 'quitado', saldo_a_pagar: 0 }), regua: REGUA_VAZIA },
    { titulo: '0: dentro do prazo, sem sinal de risco', c: conta({ status_financeiro: 'a_vencer', saldo_a_pagar: 5000, dias_atraso: null, vencimento: '2026-09-01' }), regua: REGUA_VAZIA },
    { titulo: '1: sem_acordo, saldo positivo sem prazo', c: conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 14700, dias_atraso: null }), regua: REGUA_VAZIA },
    { titulo: '0: incalculavel sem saldo (saldo_a_pagar null)', c: conta({ status_financeiro: 'incalculavel', saldo_a_pagar: null, dias_atraso: null }), regua: REGUA_VAZIA },
    { titulo: '2: dias_atraso entre 1 e 30', c: conta({ status_financeiro: 'vencido', saldo_a_pagar: 5000, dias_atraso: 15 }), regua: REGUA_VAZIA },
    { titulo: '2: proximaAcao atrasada com saldo > 0', c: conta({ status_financeiro: 'a_vencer', saldo_a_pagar: 5000, dias_atraso: null, vencimento: '2026-08-01' }), regua: REGUA },
    { titulo: '3: dias_atraso > 30', c: conta({ status_financeiro: 'vencido', saldo_a_pagar: 5000, dias_atraso: 31 }), regua: REGUA_VAZIA },
    { titulo: '3: cancelamento solicitado, mesmo sem atraso', c: conta({ status_financeiro: 'cancelamento_solicitado', saldo_a_pagar: 5000, dias_atraso: 0 }), regua: REGUA_VAZIA },
    { titulo: '3: solicitou_cancelamento (flag) com outro status', c: conta({ status_financeiro: 'em_pagamento', solicitou_cancelamento: true, saldo_a_pagar: 5000 }), regua: REGUA_VAZIA },
    { titulo: '1: dias_atraso null em sem_acordo vira 1, não 0 nem 3', c: conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 2300, dias_atraso: null, vencimento: null }), regua: REGUA },
  ];

  for (const { titulo, c, regua } of casos) {
    it(`${titulo} — motivo null sse urgencia 0`, () => {
      const u = urgencia(c, regua, HOJE);
      const motivo = motivoUrgencia(c, regua, HOJE);
      expect(motivo === null).toBe(u === 0);
    });
  }
});
