import { describe, it, expect } from 'vitest';
import { faixaPrazoDe, distribuicaoPrazo, agruparPorFaixaPrazo } from './prazo';
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
    intencao_pagamento: null, intencao_pagamento_obs: null,
    reuniao_motivo_tipo: null, reuniao_retomar_em: null,
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

const HOJE = '2026-08-20';

describe('faixaPrazoDe', () => {
  it('sem vencimento (mas com saldo) = sem_data', () => {
    expect(faixaPrazoDe(conta({ vencimento: null, saldo_a_pagar: 14700 }), HOJE)).toBe('sem_data');
  });
  it('vencimento no passado = vencidas', () => {
    expect(faixaPrazoDe(conta({ vencimento: '2026-08-01', saldo_a_pagar: 14700 }), HOJE)).toBe('vencidas');
  });
  it('vencimento hoje = vencidas (>= hoje não conta como vencido, mas < hoje sim; hoje mesmo entra em vencem_7d)', () => {
    expect(faixaPrazoDe(conta({ vencimento: HOJE, saldo_a_pagar: 14700 }), HOJE)).toBe('vencem_7d');
  });
  it('vencimento em 3 dias = vencem_7d', () => {
    expect(faixaPrazoDe(conta({ vencimento: '2026-08-23', saldo_a_pagar: 14700 }), HOJE)).toBe('vencem_7d');
  });
  it('vencimento em exatamente 7 dias = vencem_7d (inclusive)', () => {
    expect(faixaPrazoDe(conta({ vencimento: '2026-08-27', saldo_a_pagar: 14700 }), HOJE)).toBe('vencem_7d');
  });
  it('vencimento em 8 dias = a_vencer', () => {
    expect(faixaPrazoDe(conta({ vencimento: '2026-08-28', saldo_a_pagar: 14700 }), HOJE)).toBe('a_vencer');
  });
  it('vencimento distante = a_vencer', () => {
    expect(faixaPrazoDe(conta({ vencimento: '2026-12-01', saldo_a_pagar: 14700 }), HOJE)).toBe('a_vencer');
  });
  it('quitado, morto e saldo zero saem da faixa (null)', () => {
    expect(faixaPrazoDe(conta({ status_financeiro: 'quitado', vencimento: '2026-08-01' }), HOJE)).toBeNull();
    expect(faixaPrazoDe(conta({ status_financeiro: 'cancelado', vencimento: '2026-08-01' }), HOJE)).toBeNull();
    expect(faixaPrazoDe(conta({ status_financeiro: 'reembolsado', vencimento: '2026-08-01' }), HOJE)).toBeNull();
    expect(faixaPrazoDe(conta({ saldo_a_pagar: 0, vencimento: '2026-08-01' }), HOJE)).toBeNull();
  });
  it('saldo residual dentro da tolerância de centavos sai da faixa (null)', () => {
    expect(faixaPrazoDe(conta({ saldo_a_pagar: 0.5, vencimento: '2026-08-01' }), HOJE)).toBeNull();
  });
});

describe('distribuicaoPrazo', () => {
  it('soma valor e alunos por faixa, na ordem canônica', () => {
    const d = distribuicaoPrazo([
      conta({ vencimento: '2026-08-01', saldo_a_pagar: 100 }), // vencidas
      conta({ vencimento: '2026-08-01', saldo_a_pagar: 200 }), // vencidas
      conta({ vencimento: null, saldo_a_pagar: 900 }), // sem_data
    ], HOJE);
    expect(d[0]).toMatchObject({ faixa: 'vencidas', alunos: 2, valor: 300 });
    expect(d.find((x) => x.faixa === 'sem_data')).toMatchObject({ alunos: 1, valor: 900 });
  });
  it('contas mortas/quitadas não entram em nenhuma fatia', () => {
    const d = distribuicaoPrazo([
      conta({ status_financeiro: 'quitado', vencimento: '2026-08-01', saldo_a_pagar: 100 }),
      conta({ status_financeiro: 'cancelado', vencimento: '2026-08-01', saldo_a_pagar: 100 }),
    ], HOJE);
    expect(d).toEqual([]);
  });
});

describe('agruparPorFaixaPrazo', () => {
  it('agrupa nas 4 faixas, ordenado por saldo_a_pagar desc dentro de cada uma', () => {
    const grupos = agruparPorFaixaPrazo([
      conta({ contato_hm_id: 'a', vencimento: '2026-08-01', saldo_a_pagar: 100 }),
      conta({ contato_hm_id: 'b', vencimento: '2026-08-01', saldo_a_pagar: 500 }),
      conta({ contato_hm_id: 'c', vencimento: null, saldo_a_pagar: 900 }),
    ], HOJE);
    expect(grupos.vencidas.map((c) => c.contato_hm_id)).toEqual(['b', 'a']);
    expect(grupos.sem_data.map((c) => c.contato_hm_id)).toEqual(['c']);
    expect(grupos.vencem_7d).toEqual([]);
    expect(grupos.a_vencer).toEqual([]);
  });
});
