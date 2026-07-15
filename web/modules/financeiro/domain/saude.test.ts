import { describe, it, expect } from 'vitest';
import {
  condicaoAging, condicaoPrevisibilidade, condicaoVencido, estadoTurma, metaVsReal, pior, progressoMeta,
} from './saude';
import type { ContaReceber, Meta, StatusFinanceiro } from './types';

function conta(over: Partial<ContaReceber> = {}): ContaReceber {
  return {
    contato_hm_id: 'c1', comprador_id: 'p1', aluno_id: null,
    nome: 'Fulano', email: 'f@x.com', telefone: null, documento: null,
    turma: 'T39', turma_origem: null, canal: 'HT ATM', publico: 'lead_novo', tags: [],
    estagio_nome: null, estagio_aba: null,
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

describe('pior', () => {
  it('a condição mais grave vence', () => {
    expect(pior('boa', 'critica')).toBe('critica');
    expect(pior('atencao', 'boa')).toBe('atencao');
    expect(pior('boa', 'neutra')).toBe('neutra');
  });
});

describe('progressoMeta', () => {
  it('sem meta = neutra', () => {
    expect(progressoMeta(50, null).condicao).toBe('neutra');
  });
  it('perto da meta = boa; longe = crítica', () => {
    expect(progressoMeta(95, 100).condicao).toBe('boa');
    expect(progressoMeta(70, 100).condicao).toBe('atencao');
    expect(progressoMeta(20, 100).condicao).toBe('critica');
  });
  it('pct é limitado a 100', () => {
    expect(progressoMeta(150, 100).pct).toBe(100);
  });
});

describe('condicaoAging', () => {
  it('saldo velho (60+) acima de 20% = crítica', () => {
    const r = condicaoAging([
      conta({ vencimento: '2026-05-01', dias_atraso: 70, saldo_a_pagar: 800, status_financeiro: 'vencido' }),
      conta({ vencimento: '2026-07-20', dias_atraso: -5, saldo_a_pagar: 200, status_financeiro: 'a_vencer' }),
    ]);
    expect(r.condicao).toBe('critica');
  });
  it('tudo a vencer = boa', () => {
    expect(condicaoAging([conta({ vencimento: '2026-12-01', dias_atraso: -30, saldo_a_pagar: 1000, status_financeiro: 'a_vencer' })]).condicao).toBe('boa');
  });
});

describe('condicaoPrevisibilidade', () => {
  it('maioria sem data combinada = crítica', () => {
    const r = condicaoPrevisibilidade([
      conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 9000 }),
      conta({ status_financeiro: 'a_vencer', vencimento: '2026-08-01', saldo_a_pagar: 1000 }),
    ]);
    expect(r.condicao).toBe('critica');
  });
});

describe('condicaoVencido', () => {
  it('sem vencido = boa; com vencido = alerta', () => {
    expect(condicaoVencido([conta({ status_financeiro: 'a_vencer', saldo_a_pagar: 100 })]).condicao).toBe('boa');
    const r = condicaoVencido([conta({ status_financeiro: 'vencido', saldo_a_pagar: 5000, dias_atraso: 3 })]);
    expect(['atencao', 'critica']).toContain(r.condicao);
  });
});

describe('estadoTurma', () => {
  it('sem contas = neutra', () => {
    expect(estadoTurma([]).condicao).toBe('neutra');
  });
  it('saldo muito velho domina como risco', () => {
    const e = estadoTurma([
      conta({ vencimento: '2026-04-01', dias_atraso: 90, saldo_a_pagar: 9000, status_financeiro: 'vencido' }),
    ]);
    expect(e.condicao).toBe('critica');
  });
  it('carteira sem data combinada vira atenção de previsibilidade', () => {
    const e = estadoTurma([
      conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 9000 }),
      conta({ status_financeiro: 'sem_acordo', saldo_a_pagar: 9000 }),
    ]);
    expect(e.condicao).toBe('atencao');
    expect(e.motivo).toMatch(/sem data combinada/);
  });
  it('em dia = saudável', () => {
    const e = estadoTurma([
      conta({ status_financeiro: 'a_vencer', vencimento: '2026-08-10', saldo_a_pagar: 100 }),
      conta({ status_financeiro: 'quitado', saldo_a_pagar: 0 }),
    ]);
    expect(e.condicao).toBe('boa');
  });
});

describe('metaVsReal', () => {
  const meta: Meta = {
    turma: 'T39', meta_arrecadacao: 2000000, meta_cobertura_pct: 95,
    prazo_quitacao_dias: 45, data_fechamento: '2026-09-30', obs: null,
    atualizado_em: null, atualizado_por: null,
  };
  it('cruza realizado com meta e conta dias para fechar', () => {
    const r = metaVsReal([conta({ total_pago_bruto: 500000, pacote: 15000 })], meta, '2026-07-14');
    expect(r.arrecadacao.meta).toBe(2000000);
    expect(r.arrecadacao.realizado).toBe(500000);
    expect(r.diasParaFechar).toBe(78);
    expect(r.cobertura.meta).toBe(95);
  });
  it('sem meta → indicadores neutros', () => {
    const r = metaVsReal([conta()], null, '2026-07-14');
    expect(r.arrecadacao.ind.condicao).toBe('neutra');
    expect(r.diasParaFechar).toBeNull();
  });
});
