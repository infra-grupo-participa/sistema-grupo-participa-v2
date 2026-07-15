import { describe, it, expect } from 'vitest';
import { agrupar, contaMorta, filtrar, FILTROS_VAZIOS, mascararDoc, resumir, statusLabel } from './financeiro';
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

describe('contaMorta', () => {
  it('cancelado e reembolsado saem da conta', () => {
    expect(contaMorta(conta({ status_financeiro: 'cancelado' }))).toBe(true);
    expect(contaMorta(conta({ status_financeiro: 'reembolsado' }))).toBe(true);
    expect(contaMorta(conta({ status_financeiro: 'vencido' }))).toBe(false);
  });
});

describe('resumir', () => {
  it('soma bruto, líquido e deriva as taxas da diferença', () => {
    const r = resumir([conta(), conta()]);
    expect(r.recebidoBruto).toBe(600);
    expect(r.recebidoLiquido).toBe(574);
    expect(r.taxas).toBe(26);
  });

  it('não persegue saldo de quem cancelou ou foi reembolsado', () => {
    const r = resumir([
      conta({ saldo_a_pagar: 14700 }),
      conta({ status_financeiro: 'cancelado', saldo_a_pagar: 14700 }),
      conta({ status_financeiro: 'reembolsado', saldo_a_pagar: 14700 }),
    ]);
    expect(r.aReceber).toBe(14700);
    expect(r.alunos).toBe(3);
  });

  it('cobertura = recebido / pacote contratado dos vivos', () => {
    const r = resumir([conta({ total_pago_bruto: 7500, pacote: 15000 })]);
    expect(r.cobertura).toBe(50);
  });

  it('cobertura é 0 quando não há pacote (evita divisão por zero)', () => {
    expect(resumir([conta({ pacote: null })]).cobertura).toBe(0);
    expect(resumir([]).cobertura).toBe(0);
  });

  it('conta em atraso por dias_atraso positivo', () => {
    const r = resumir([conta({ dias_atraso: 5 }), conta({ dias_atraso: -3 }), conta({ dias_atraso: null })]);
    expect(r.emAtraso).toBe(1);
  });

  it('separa pediu cancelamento (perseguível) de cancelado (morto)', () => {
    const r = resumir([
      conta({ solicitou_cancelamento: true, status_financeiro: 'cancelamento_solicitado' }),
      conta({ solicitou_cancelamento: true, status_financeiro: 'cancelado' }), // efetivado: morto, não conta como pediu
      conta({ status_financeiro: 'reembolsado' }),
      conta(),
    ]);
    expect(r.pediuCancelamento).toBe(1);
    expect(r.cancelados).toBe(2);
  });
});

describe('filtrar', () => {
  const base = [
    conta({ nome: 'Ana', status_financeiro: 'vencido', canal: 'HT ATM', saldo_a_pagar: 100 }),
    conta({ nome: 'Bruno', status_financeiro: 'quitado', canal: 'Live Direto ao Ponto', saldo_a_pagar: 0 }),
    conta({ nome: 'Carla', status_financeiro: 'sem_acordo', canal: 'HT ATM', saldo_a_pagar: 14700 }),
    conta({ nome: 'Dino', status_financeiro: 'cancelado', canal: 'HT ATM', saldo_a_pagar: 14700 }),
  ];

  it('sem filtro devolve tudo', () => {
    expect(filtrar(base, FILTROS_VAZIOS)).toHaveLength(4);
  });

  it('gaveta a_receber ignora cancelado mesmo com saldo', () => {
    const r = filtrar(base, { ...FILTROS_VAZIOS, gaveta: 'a_receber' });
    expect(r.map((c) => c.nome)).toEqual(['Ana', 'Carla']);
  });

  it('OR dentro do filtro de status', () => {
    const r = filtrar(base, { ...FILTROS_VAZIOS, status: ['vencido', 'quitado'] });
    expect(r.map((c) => c.nome)).toEqual(['Ana', 'Bruno']);
  });

  it('status futuro é filtrável e entra no a-receber', () => {
    const b = [...base, conta({ nome: 'Zeca', status_financeiro: 'futuro', canal: 'HT ATM', saldo_a_pagar: 14700 })];
    expect(filtrar(b, { ...FILTROS_VAZIOS, status: ['futuro'] }).map((c) => c.nome)).toEqual(['Zeca']);
    expect(filtrar(b, { ...FILTROS_VAZIOS, gaveta: 'a_receber' }).map((c) => c.nome)).toEqual(['Ana', 'Carla', 'Zeca']);
  });

  it('AND entre status e canal', () => {
    const r = filtrar(base, { ...FILTROS_VAZIOS, status: ['vencido', 'quitado'], canais: ['HT ATM'] });
    expect(r.map((c) => c.nome)).toEqual(['Ana']);
  });

  it('busca por nome e e-mail, sem diferenciar caixa', () => {
    expect(filtrar(base, { ...FILTROS_VAZIOS, termo: 'CARL' }).map((c) => c.nome)).toEqual(['Carla']);
    expect(filtrar(base, { ...FILTROS_VAZIOS, termo: 'f@x.com' })).toHaveLength(4);
  });

  it('gaveta pediu_cancelamento pega o kanban e ignora o efetivado', () => {
    const b = [
      conta({ nome: 'Eva', solicitou_cancelamento: true, status_financeiro: 'cancelamento_solicitado' }),
      conta({ nome: 'Igor', solicitou_cancelamento: true, status_financeiro: 'cancelado' }),
      conta({ nome: 'Lia' }),
    ];
    expect(filtrar(b, { ...FILTROS_VAZIOS, gaveta: 'pediu_cancelamento' }).map((c) => c.nome)).toEqual(['Eva']);
  });

  it('gaveta cancelado pega só as contas mortas', () => {
    expect(filtrar(base, { ...FILTROS_VAZIOS, gaveta: 'cancelado' }).map((c) => c.nome)).toEqual(['Dino']);
  });

  it('filtra por produto (OR interno, AND externo)', () => {
    const b = [
      conta({ nome: 'Ana', produto: 'Holding Masters' }),
      conta({ nome: 'Bia', produto: 'Outro Produto' }),
    ];
    expect(filtrar(b, { ...FILTROS_VAZIOS, produtos: ['Outro Produto'] }).map((c) => c.nome)).toEqual(['Bia']);
    expect(filtrar(b, { ...FILTROS_VAZIOS, produtos: ['Holding Masters', 'Outro Produto'] })).toHaveLength(2);
  });
});

describe('agrupar', () => {
  it('agrupa por canal e ordena por a-receber', () => {
    const r = agrupar(
      [
        conta({ canal: 'HT ATM', saldo_a_pagar: 100, total_pago_bruto: 300 }),
        conta({ canal: 'HT ATM', saldo_a_pagar: 200, total_pago_bruto: 300 }),
        conta({ canal: 'Venda direta', saldo_a_pagar: 900, total_pago_bruto: 300 }),
      ],
      (c) => c.canal,
    );
    expect(r[0]).toMatchObject({ chave: 'Venda direta', alunos: 1, aReceber: 900 });
    expect(r[1]).toMatchObject({ chave: 'HT ATM', alunos: 2, aReceber: 300, recebido: 600 });
  });

  it('não soma a-receber de conta morta', () => {
    const r = agrupar([conta({ canal: 'X', status_financeiro: 'cancelado', saldo_a_pagar: 14700 })], (c) => c.canal);
    expect(r[0].aReceber).toBe(0);
    expect(r[0].alunos).toBe(1);
  });
});

describe('statusLabel', () => {
  it('traduz os status conhecidos e devolve o cru nos demais', () => {
    expect(statusLabel('sem_acordo')).toBe('Sem acordo');
    expect(statusLabel('vencido')).toBe('Vencido');
    expect(statusLabel('a_vencer')).toBe('A vencer');
    expect(statusLabel('futuro')).toBe('Futuro');
    expect(statusLabel('xpto')).toBe('xpto');
  });
});

describe('mascararDoc (LGPD)', () => {
  it('mostra o documento cru quando o usuário pode ver', () => {
    expect(mascararDoc('12345678901', true)).toBe('12345678901');
  });

  it('mantém só os 4 últimos dígitos quando não pode', () => {
    expect(mascararDoc('12345678901', false)).toBe('•••••••8901');
  });

  it('lida com vazio e nulo sem quebrar', () => {
    expect(mascararDoc(null, false)).toBe('');
    expect(mascararDoc('', false)).toBe('');
  });

  it('documento curto vira tudo mascarado', () => {
    expect(mascararDoc('12', false)).toBe('••');
  });
});
