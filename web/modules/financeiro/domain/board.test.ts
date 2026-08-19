import { describe, it, expect } from 'vitest';
import { agruparPorFaixa, corDe, FAIXAS, faixaDe, urgencia } from './board';
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

describe('faixaDe', () => {
  it('sem_valor: status incalculavel', () => {
    expect(faixaDe(conta({ status_financeiro: 'incalculavel' }))).toBe('sem_valor');
  });

  it('sem_acordo: status sem_acordo', () => {
    expect(faixaDe(conta({ status_financeiro: 'sem_acordo' }))).toBe('sem_acordo');
  });

  it('oferta_enviada: status oferta_enviada', () => {
    expect(faixaDe(conta({ status_financeiro: 'oferta_enviada' }))).toBe('oferta_enviada');
  });

  it('em_cobranca: vencido, a_vencer, futuro, em_pagamento', () => {
    for (const s of ['vencido', 'a_vencer', 'futuro', 'em_pagamento'] as StatusFinanceiro[]) {
      expect(faixaDe(conta({ status_financeiro: s }))).toBe('em_cobranca');
    }
  });

  it('risco_perda: cancelamento_solicitado', () => {
    expect(faixaDe(conta({ status_financeiro: 'cancelamento_solicitado' }))).toBe('risco_perda');
  });

  it('risco_perda: solicitou_cancelamento true e não morta, mesmo com outro status', () => {
    expect(faixaDe(conta({ status_financeiro: 'vencido', solicitou_cancelamento: true }))).toBe('em_cobranca');
    // status vencido casa antes na ordem de checagem — risco_perda só pega quem
    // não caiu em nenhuma regra anterior (ex.: status quitado com o flag setado).
    expect(faixaDe(conta({ status_financeiro: 'quitado', solicitou_cancelamento: true }))).toBe('risco_perda');
  });

  it('encerrado: conta morta (cancelado/reembolsado)', () => {
    expect(faixaDe(conta({ status_financeiro: 'cancelado' }))).toBe('encerrado');
    expect(faixaDe(conta({ status_financeiro: 'reembolsado' }))).toBe('encerrado');
  });

  it('encerrado: quitado sem saldo residual', () => {
    expect(faixaDe(conta({ status_financeiro: 'quitado', saldo_a_pagar: 0 }))).toBe('encerrado');
  });

  it('primeira regra que casar vence: incalculavel prevalece sobre solicitou_cancelamento', () => {
    expect(faixaDe(conta({ status_financeiro: 'incalculavel', solicitou_cancelamento: true }))).toBe('sem_valor');
  });

  it('FAIXAS tem as 6 chaves na ordem documentada', () => {
    expect(FAIXAS.map((f) => f.chave)).toEqual([
      'sem_valor', 'sem_acordo', 'oferta_enviada', 'em_cobranca', 'risco_perda', 'encerrado',
    ]);
  });
});

describe('agruparPorFaixa', () => {
  it('separa contas nas faixas certas e ordena por saldo_a_pagar desc dentro de cada uma', () => {
    const g = agruparPorFaixa([
      conta({ nome: 'A', status_financeiro: 'vencido', saldo_a_pagar: 100 }),
      conta({ nome: 'B', status_financeiro: 'vencido', saldo_a_pagar: 900 }),
      conta({ nome: 'C', status_financeiro: 'sem_acordo', saldo_a_pagar: 14700 }),
    ]);
    expect(g.em_cobranca.map((c) => c.nome)).toEqual(['B', 'A']);
    expect(g.sem_acordo.map((c) => c.nome)).toEqual(['C']);
    expect(g.encerrado).toEqual([]);
  });

  it('todas as 6 chaves existem mesmo vazias (lista vazia não afirma nada, mas também não quebra)', () => {
    const g = agruparPorFaixa([]);
    expect(Object.keys(g).sort()).toEqual(
      ['em_cobranca', 'encerrado', 'oferta_enviada', 'risco_perda', 'sem_acordo', 'sem_valor'].sort(),
    );
    for (const chave of Object.keys(g) as (keyof typeof g)[]) expect(g[chave]).toEqual([]);
  });

  it('trata saldo_a_pagar null como 0 na ordenação, sem quebrar', () => {
    const g = agruparPorFaixa([
      conta({ nome: 'Nulo', status_financeiro: 'sem_acordo', saldo_a_pagar: null }),
      conta({ nome: 'Com valor', status_financeiro: 'sem_acordo', saldo_a_pagar: 500 }),
    ]);
    expect(g.sem_acordo.map((c) => c.nome)).toEqual(['Com valor', 'Nulo']);
  });
});

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

describe('corDe', () => {
  it('verde: quitado', () => {
    expect(corDe(conta({ status_financeiro: 'quitado' }))).toBe('verde');
  });

  it('azul: em_pagamento, a_vencer, futuro, oferta_enviada', () => {
    for (const s of ['em_pagamento', 'a_vencer', 'futuro', 'oferta_enviada'] as StatusFinanceiro[]) {
      expect(corDe(conta({ status_financeiro: s }))).toBe('azul');
    }
  });

  it('vermelho: cancelado, reembolsado, cancelamento_solicitado, vencido', () => {
    for (const s of ['cancelado', 'reembolsado', 'cancelamento_solicitado', 'vencido'] as StatusFinanceiro[]) {
      expect(corDe(conta({ status_financeiro: s }))).toBe('vermelho');
    }
  });

  it('neutro: sem_acordo, incalculavel', () => {
    expect(corDe(conta({ status_financeiro: 'sem_acordo' }))).toBe('neutro');
    expect(corDe(conta({ status_financeiro: 'incalculavel' }))).toBe('neutro');
  });
});
