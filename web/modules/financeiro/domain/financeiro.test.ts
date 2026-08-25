import { describe, it, expect } from 'vitest';
import {
  agrupar, comMetricas, contaMorta, ehReserva, filtrar, FILTROS_VAZIOS, mascararDoc, preencherLacunas, resumir,
  saldoEfetivo, segundaMetadeCondicional, statusLabel,
} from './financeiro';
import type { ContaReceber, DiaFaturamento, StatusFinanceiro } from './types';

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

describe('saldoEfetivo (tolerância de centavos)', () => {
  it('resíduo de arredondamento das 12x (< R$ 1) vale 0', () => {
    expect(saldoEfetivo(conta({ saldo_a_pagar: 0.04 }))).toBe(0);
    expect(saldoEfetivo(conta({ saldo_a_pagar: -0.02 }))).toBe(0);
    expect(saldoEfetivo(conta({ saldo_a_pagar: 0.99 }))).toBe(0);
  });

  it('saldo real passa intacto; null vale 0', () => {
    expect(saldoEfetivo(conta({ saldo_a_pagar: 1 }))).toBe(1);
    expect(saldoEfetivo(conta({ saldo_a_pagar: 14700 }))).toBe(14700);
    expect(saldoEfetivo(conta({ saldo_a_pagar: null }))).toBe(0);
  });

  it('resumir não soma resíduo no a-receber nem no vencido', () => {
    const r = resumir([
      conta({ saldo_a_pagar: 0.04, status_financeiro: 'vencido' }),
      conta({ saldo_a_pagar: 100, status_financeiro: 'vencido' }),
    ]);
    expect(r.aReceber).toBe(100);
    expect(r.vencido).toBe(100);
  });

  it('gaveta a_receber ignora quem só tem resíduo de centavos', () => {
    const b = [conta({ nome: 'Ana', saldo_a_pagar: 0.03 }), conta({ nome: 'Bia', saldo_a_pagar: 500 })];
    expect(filtrar(b, { ...FILTROS_VAZIOS, gaveta: 'a_receber' }).map((c) => c.nome)).toEqual(['Bia']);
  });
});

describe('ehReserva (reserva de vaga)', () => {
  it('só sinal pago e nada do saldo = reserva', () => {
    expect(ehReserva(conta({ sinal_bruto: 300, saldo_pago_bruto: 0 }))).toBe(true);
  });

  it('quem já pagou algo do saldo não é reserva', () => {
    expect(ehReserva(conta({ sinal_bruto: 300, saldo_pago_bruto: 1225 }))).toBe(false);
  });

  it('sem sinal pago não é reserva', () => {
    expect(ehReserva(conta({ sinal_bruto: null, saldo_pago_bruto: 0 }))).toBe(false);
    expect(ehReserva(conta({ sinal_bruto: 0, saldo_pago_bruto: 0 }))).toBe(false);
  });
});

describe('segundaMetadeCondicional', () => {
  it('R$ 15.000 por parceiro ativo que já pagou algo do saldo', () => {
    const r = segundaMetadeCondicional([
      conta({ saldo_pago_bruto: 14700, status_financeiro: 'quitado' }),
      conta({ saldo_pago_bruto: 1225, status_financeiro: 'em_pagamento' }),
      conta({ saldo_pago_bruto: 0 }), // reserva de vaga: fora
    ]);
    expect(r).toEqual({ valor: 30000, parceiros: 2 });
  });

  it('cancelado, reembolsado e cancelamento solicitado ficam fora', () => {
    const r = segundaMetadeCondicional([
      conta({ saldo_pago_bruto: 14700, status_financeiro: 'cancelado' }),
      conta({ saldo_pago_bruto: 14700, status_financeiro: 'reembolsado' }),
      conta({ saldo_pago_bruto: 14700, status_financeiro: 'cancelamento_solicitado' }),
      conta({ saldo_pago_bruto: 14700, status_financeiro: 'quitado' }),
    ]);
    expect(r).toEqual({ valor: 15000, parceiros: 1 });
  });

  it('sem parceiro ativo o valor é 0', () => {
    expect(segundaMetadeCondicional([conta()])).toEqual({ valor: 0, parceiros: 0 });
    expect(segundaMetadeCondicional([])).toEqual({ valor: 0, parceiros: 0 });
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

function dia(over: Partial<DiaFaturamento> & { dia: string; bruto: number }): DiaFaturamento {
  return {
    lancamentos: 1, cliente_pagou: over.bruto, juros: 0, liquido: over.bruto, taxas: 0,
    sinal: null, saldo: null, mensalidade: null, compra_cheia: null, ajuste: null, alunos: 1,
    ...over,
  };
}

describe('preencherLacunas', () => {
  it('mantém a série intacta quando não há buraco', () => {
    const r = preencherLacunas([dia({ dia: '2026-08-05', bruto: 100 }), dia({ dia: '2026-08-06', bruto: 200 })]);
    expect(r.map((d) => [d.dia, d.bruto, d.preenchido])).toEqual([
      ['2026-08-05', 100, false],
      ['2026-08-06', 200, false],
    ]);
  });

  it('preenche dia ausente entre o primeiro e o último com zero explícito (caso real: 04/08 e 08/08 faltando)', () => {
    const r = preencherLacunas([
      dia({ dia: '2026-08-03', bruto: 3820 }),
      dia({ dia: '2026-08-05', bruto: 43676 }),
      dia({ dia: '2026-08-06', bruto: 22150 }),
      dia({ dia: '2026-08-07', bruto: 999 }),
      dia({ dia: '2026-08-09', bruto: 13242 }),
    ]);
    expect(r.map((d) => d.dia)).toEqual([
      '2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07', '2026-08-08', '2026-08-09',
    ]);
    const d04 = r.find((d) => d.dia === '2026-08-04')!;
    expect(d04.preenchido).toBe(true);
    expect(d04.bruto).toBe(0);
    expect(d04.lancamentos).toBe(0);
    const d08 = r.find((d) => d.dia === '2026-08-08')!;
    expect(d08.preenchido).toBe(true);
  });

  it('lista vazia devolve vazia (não inventa dia)', () => {
    expect(preencherLacunas([])).toEqual([]);
  });

  it('entrada fora de ordem é normalizada asc', () => {
    const r = preencherLacunas([dia({ dia: '2026-08-06', bruto: 20 }), dia({ dia: '2026-08-05', bruto: 10 })]);
    expect(r.map((d) => d.dia)).toEqual(['2026-08-05', '2026-08-06']);
  });
});

describe('comMetricas', () => {
  it('dia ausente (preenchido=0) DERRUBA a média móvel de 7 dias — não pode ser ignorado', () => {
    // 7 dias a 100 seguidos por 1 buraco (dia 8, ausente) então dia 9 com 100:
    // média7d do dia 9 deve considerar o zero do dia 8, não pular direto para 100 flat.
    const dias: DiaFaturamento[] = [
      dia({ dia: '2026-08-01', bruto: 100 }),
      dia({ dia: '2026-08-02', bruto: 100 }),
      dia({ dia: '2026-08-03', bruto: 100 }),
      dia({ dia: '2026-08-04', bruto: 100 }),
      dia({ dia: '2026-08-05', bruto: 100 }),
      dia({ dia: '2026-08-06', bruto: 100 }),
      dia({ dia: '2026-08-07', bruto: 100 }),
      // 08/08 ausente — vira 0 explícito
      dia({ dia: '2026-08-09', bruto: 100 }),
    ];
    const r = comMetricas(dias);
    const dia09 = r.find((d) => d.dia === '2026-08-09')!;
    // janela dos 7 dias anteriores ao dia 9: 02..08 = [100,100,100,100,100,100,0] → média = 600/7 ≈ 85,71
    // Se o buraco fosse ignorado (dia 08 nunca existisse na série), a janela seria
    // [100,100,100,100,100,100,100] = média 100 — a diferença de ~14,3 pontos É o preço
    // de deixar a média mentir para cima. O teste prova que o zero explícito entra na conta.
    expect(dia09.media7d).toBeCloseTo(600 / 7, 5);
    expect(dia09.media7d).not.toBeCloseTo(100, 0);
    const dia08Preenchido = r.find((d) => d.dia === '2026-08-08')!;
    expect(dia08Preenchido.preenchido).toBe(true);
    expect(dia08Preenchido.bruto).toBe(0);
    // vsMedia7d do dia 08 (bruto 0) vs média dos 7 dias anteriores (todos 100) deve ser -100%
    expect(dia08Preenchido.vsMedia7d).toBeCloseTo(-100, 5);
  });

  it('variação vs. dia anterior: alta e queda em percentual', () => {
    const r = comMetricas([dia({ dia: '2026-08-01', bruto: 100 }), dia({ dia: '2026-08-02', bruto: 150 }), dia({ dia: '2026-08-03', bruto: 75 })]);
    expect(r[0].variacaoDiaAnterior).toBeNull(); // sem dia anterior
    expect(r[1].variacaoDiaAnterior).toBeCloseTo(50, 5); // 100 → 150 = +50%
    expect(r[2].variacaoDiaAnterior).toBeCloseTo(-50, 5); // 150 → 75 = -50%
  });

  it('acumulado soma do primeiro dia até o dia atual, incluindo dias preenchidos como zero', () => {
    const r = comMetricas([dia({ dia: '2026-08-01', bruto: 100 }), dia({ dia: '2026-08-03', bruto: 50 })]);
    expect(r.map((d) => d.acumulado)).toEqual([100, 100, 150]); // dia 02 preenchido não muda o acumulado
  });

  it('sem histórico suficiente, media7d e vsMedia7d ficam null', () => {
    const r = comMetricas([dia({ dia: '2026-08-01', bruto: 100 })]);
    expect(r[0].media7d).toBeNull();
    expect(r[0].vsMedia7d).toBeNull();
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
