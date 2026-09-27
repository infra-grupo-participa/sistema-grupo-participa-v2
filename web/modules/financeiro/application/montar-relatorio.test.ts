import { describe, it, expect } from 'vitest';
import { montarRelatorio } from './montar-relatorio';
import type { ContaReceber } from '../domain/types';
import type { BoardHotmart } from '../domain/hotmart';

function conta(over: Partial<ContaReceber> = {}): ContaReceber {
  return {
    contato_hm_id: 'c1', comprador_id: 'p1', aluno_id: null,
    nome: 'Fulano', email: 'f@x.com', telefone: null, documento: null,
    turma: 'T39', turma_origem: null, canal: 'HT ATM', publico: null, tags: null,
    estagio_nome: null, estagio_aba: null, estagio_id: null,
    produto: 'Holding Masters',
    vendedor: null, reuniao_em: null, reuniao_resultado: null, entrevista_em: null, entrevista_resultado: null, obs_comercial: null,
    intencao_pagamento: null, intencao_pagamento_obs: null, reuniao_motivo_tipo: null, reuniao_retomar_em: null,
    solicitou_cancelamento: false,
    sinal_bruto: null, sinal_liquido: null, sinal_taxas: null, sinal_pago_em: null, sinal_metodo: null, sinal_transacao: null,
    saldo_pago_bruto: 0, saldo_pago_liquido: 0, saldo_taxas: 0, saldo_pago_em: null, saldo_metodo: null, saldo_lancamentos: 0,
    total_pago_bruto: 300, total_pago_liquido: 287, pacote: 15000, pacote_regra: null, divergencia_regra: null,
    credito: null, saldo_a_pagar: 14700, pago_pct: 2,
    vencimento: null, acordo: null, pagamento_meio: null, pagamento_forma: null, pagamento_parcelas: null,
    parcelas_pagas: null, parcelas_contratadas: null, valor_parcela: null, dias_atraso: null,
    oferta_codigo: null, oferta_valor: null, oferta_link: null, oferta_recorrente: null, oferta_enviada_em: null,
    cancelamento_em: null, cancelamento_motivo: null, cancelamento_efetivado_em: null, quitado_em: null,
    reembolso_em: null, reembolso_status: null, reembolso_valor: null,
    ultimo_pagamento_em: null, situacao_ativacao: null, status_financeiro: 'sem_acordo',
    ultima_cobranca_em: null, cobrancas_total: 0, remarcacoes: 0,
    ...over,
  };
}

function boardHotmart(over: Partial<BoardHotmart> = {}): BoardHotmart {
  return {
    contato_hm_id: 'c1', origem: 'HM', encontrado: true, pessoa_chave: 'pc1', cards_da_pessoa: 1,
    vendas_pagas: 1, pago_bruto: 300, taxa_hotmart: 13, coproducao: 0, liquido: 287,
    cobrado_cliente: 300, juros: 0, parcelas_max: 3, forma_pagamento_principal: 'CREDIT_CARD_VISA',
    ultimo_pagamento_em: '2026-08-01', ultimo_pagamento_valor: 300,
    parcelas_devidas: 1, valor_devido: 500, devido_antigo: 0,
    estornos: 0, valor_estornado: 0, falta_no_board: 0, valor_falta_no_board: 0, board_sem_hotmart: 0,
    diverge: false, sincronizado_em: '2026-09-27T00:00:00Z',
    ...over,
  };
}

const COLUNAS_HM = [
  'hm_pago_bruto', 'hm_taxa_hotmart', 'hm_liquido', 'hm_juros',
  'hm_parcelamento', 'hm_ultimo_pagamento', 'hm_devido_120', 'hm_diverge',
];

describe('montarRelatorio — colunas da Hotmart (hm_*)', () => {
  it('com hotmartPorCard preenchido, extrai os campos do BoardHotmart', () => {
    const hotmartPorCard = new Map([['c1', boardHotmart()]]);
    const { linhas } = montarRelatorio([conta()], COLUNAS_HM, { canVerDoc: true, hotmartPorCard });
    const v = linhas[0].valores;
    expect(v.hm_pago_bruto).toBe(300);
    expect(v.hm_taxa_hotmart).toBe(13);
    expect(v.hm_liquido).toBe(287);
    expect(v.hm_juros).toBe(0);
    expect(v.hm_parcelamento).toBe('até 3x');
    expect(v.hm_ultimo_pagamento).toBe('2026-08-01');
    expect(v.hm_devido_120).toBe(500);
    expect(v.hm_diverge).toBe('Não');
  });

  it('diverge=true vira "Sim"', () => {
    const hotmartPorCard = new Map([['c1', boardHotmart({ diverge: true })]]);
    const { linhas } = montarRelatorio([conta()], ['hm_diverge'], { canVerDoc: true, hotmartPorCard });
    expect(linhas[0].valores.hm_diverge).toBe('Sim');
  });

  it('diverge=null (sem transação para comparar) fica vazio, não "Não"', () => {
    const hotmartPorCard = new Map([['c1', boardHotmart({ diverge: null })]]);
    const { linhas } = montarRelatorio([conta()], ['hm_diverge'], { canVerDoc: true, hotmartPorCard });
    expect(linhas[0].valores.hm_diverge).toBeNull();
  });

  it('parcelas_max null vira vazio, nunca "até nullx"', () => {
    const hotmartPorCard = new Map([['c1', boardHotmart({ parcelas_max: null })]]);
    const { linhas } = montarRelatorio([conta()], ['hm_parcelamento'], { canVerDoc: true, hotmartPorCard });
    expect(linhas[0].valores.hm_parcelamento).toBeNull();
  });

  it('sem hotmartPorCard (null), todas as colunas hm_* ficam vazias — nunca 0 inventado', () => {
    const { linhas } = montarRelatorio([conta()], COLUNAS_HM, { canVerDoc: true, hotmartPorCard: null });
    for (const k of COLUNAS_HM) expect(linhas[0].valores[k]).toBeNull();
  });

  it('sem entrada da linha no mapa (card não encontrado no espelho), fica vazio', () => {
    const hotmartPorCard = new Map([['outro-card', boardHotmart({ contato_hm_id: 'outro-card' })]]);
    const { linhas } = montarRelatorio([conta({ contato_hm_id: 'c1' })], COLUNAS_HM, { canVerDoc: true, hotmartPorCard });
    for (const k of COLUNAS_HM) expect(linhas[0].valores[k]).toBeNull();
  });
});
