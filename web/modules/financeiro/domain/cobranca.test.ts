import { describe, it, expect } from 'vitest';
import { agingDe, distribuicaoAging, preverRecebimento, precisaAcao, proximaAcao } from './cobranca';
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

const REGUA: ReguaPasso[] = [
  { ordem: 1, offset_dias: -3, titulo: 'Lembrete pré-vencimento', canal: 'whatsapp', ativo: true },
  { ordem: 2, offset_dias: 1, titulo: '1º aviso de atraso', canal: 'whatsapp', ativo: true },
  { ordem: 3, offset_dias: 7, titulo: '2ª cobrança', canal: 'ligacao', ativo: true },
];

describe('agingDe', () => {
  it('sem vencimento (mas com saldo) = sem_prazo', () => {
    expect(agingDe(conta({ vencimento: null, saldo_a_pagar: 14700 }))).toBe('sem_prazo');
  });
  it('vencimento futuro = a_vencer', () => {
    expect(agingDe(conta({ vencimento: '2026-12-01', dias_atraso: -20, saldo_a_pagar: 14700 }))).toBe('a_vencer');
  });
  it('status futuro (vence >30d) ainda entra no aging como a_vencer (não vencido)', () => {
    expect(agingDe(conta({ vencimento: '2026-10-01', dias_atraso: -79, saldo_a_pagar: 14700, status_financeiro: 'futuro' }))).toBe('a_vencer');
  });
  it('faixas por dias de atraso', () => {
    expect(agingDe(conta({ vencimento: '2026-07-01', dias_atraso: 10, saldo_a_pagar: 1 }))).toBe('d1_15');
    expect(agingDe(conta({ vencimento: '2026-07-01', dias_atraso: 25, saldo_a_pagar: 1 }))).toBe('d16_30');
    expect(agingDe(conta({ vencimento: '2026-07-01', dias_atraso: 45, saldo_a_pagar: 1 }))).toBe('d31_60');
    expect(agingDe(conta({ vencimento: '2026-07-01', dias_atraso: 90, saldo_a_pagar: 1 }))).toBe('d60_plus');
  });
  it('quitado, morto e saldo zero saem do aging', () => {
    expect(agingDe(conta({ status_financeiro: 'quitado' }))).toBeNull();
    expect(agingDe(conta({ status_financeiro: 'cancelado' }))).toBeNull();
    expect(agingDe(conta({ saldo_a_pagar: 0 }))).toBeNull();
  });
});

describe('distribuicaoAging', () => {
  it('soma valor e alunos por faixa, na ordem canônica', () => {
    const d = distribuicaoAging([
      conta({ vencimento: '2026-07-01', dias_atraso: 5, saldo_a_pagar: 100 }),
      conta({ vencimento: '2026-07-01', dias_atraso: 8, saldo_a_pagar: 200 }),
      conta({ vencimento: null, saldo_a_pagar: 900 }),
    ]);
    expect(d[0]).toMatchObject({ bucket: 'd1_15', alunos: 2, valor: 300 });
    expect(d.find((x) => x.bucket === 'sem_prazo')).toMatchObject({ alunos: 1, valor: 900 });
  });
});

describe('proximaAcao', () => {
  const hoje = '2026-07-14';

  it('sem acordo → combinar vencimento (atrasada)', () => {
    const a = proximaAcao(conta({ vencimento: null }), REGUA, hoje);
    expect(a).toMatchObject({ tipo: 'definir_acordo', atrasada: true });
  });
  it('incalculável → calcular o valor', () => {
    const a = proximaAcao(conta({ status_financeiro: 'incalculavel' }), REGUA, hoje);
    expect(a.tipo).toBe('calcular_valor');
  });
  it('quitado/morto → nenhuma ação', () => {
    expect(proximaAcao(conta({ status_financeiro: 'quitado' }), REGUA, hoje).tipo).toBe('nenhuma');
    expect(proximaAcao(conta({ status_financeiro: 'cancelado' }), REGUA, hoje).tipo).toBe('nenhuma');
  });
  it('vencido sem cobrança → cobrar o passo devido', () => {
    // vencimento 2026-07-10; +1 = 07-11 já passou, +7 = 07-17 futuro
    const a = proximaAcao(conta({ vencimento: '2026-07-10', dias_atraso: 4, status_financeiro: 'vencido' }), REGUA, hoje);
    expect(a).toMatchObject({ tipo: 'cobrar', titulo: '1º aviso de atraso', atrasada: true });
  });
  it('cobrança recente cobre o passo devido → aguardar o próximo', () => {
    const a = proximaAcao(
      conta({ vencimento: '2026-07-10', dias_atraso: 4, status_financeiro: 'vencido', ultima_cobranca_em: '2026-07-13' }),
      REGUA, hoje,
    );
    expect(a).toMatchObject({ tipo: 'aguardar', titulo: '2ª cobrança', atrasada: false });
  });
  it('a vencer, dentro do pré-lembrete → aguardar', () => {
    const a = proximaAcao(conta({ vencimento: '2026-07-30', dias_atraso: -16, status_financeiro: 'a_vencer' }), REGUA, hoje);
    expect(a.atrasada).toBe(false);
  });
});

describe('precisaAcao', () => {
  it('entra na fila quando há ação atrasada', () => {
    expect(precisaAcao(conta({ vencimento: null }), REGUA, '2026-07-14')).toBe(true);
    expect(precisaAcao(conta({ status_financeiro: 'quitado' }), REGUA, '2026-07-14')).toBe(false);
  });
});

describe('preverRecebimento', () => {
  const hoje = '2026-07-14';
  it('separa próximos 7/30, em risco e sem prazo', () => {
    const f = preverRecebimento([
      conta({ vencimento: '2026-07-18', saldo_a_pagar: 1000, status_financeiro: 'a_vencer' }), // +4d
      conta({ vencimento: '2026-08-05', saldo_a_pagar: 2000, status_financeiro: 'a_vencer' }), // +22d
      conta({ vencimento: '2026-07-10', saldo_a_pagar: 3000, status_financeiro: 'vencido' }),   // vencido
      conta({ vencimento: null, saldo_a_pagar: 4000 }),                                          // sem prazo
    ], hoje);
    expect(f.proximos7).toBe(1000);
    expect(f.proximos30).toBe(3000); // 1000 + 2000
    expect(f.emRisco).toBe(3000);
    expect(f.semPrazo).toBe(4000);
    expect(f.alem30).toBe(0);
  });
  it('vencimento além de 30 dias entra em alem30 (Futuro), fora de proximos30', () => {
    const f = preverRecebimento([
      conta({ vencimento: '2026-07-18', saldo_a_pagar: 1000, status_financeiro: 'a_vencer' }), // +4d
      conta({ vencimento: '2026-10-01', saldo_a_pagar: 5000, status_financeiro: 'futuro' }),   // +79d
    ], hoje);
    expect(f.proximos30).toBe(1000);
    expect(f.alem30).toBe(5000);
  });
  it('ignora quitado e morto', () => {
    const f = preverRecebimento([
      conta({ vencimento: '2026-07-18', saldo_a_pagar: 1000, status_financeiro: 'quitado' }),
      conta({ vencimento: '2026-07-18', saldo_a_pagar: 1000, status_financeiro: 'cancelado' }),
    ], hoje);
    expect(f.proximos7).toBe(0);
  });
});
