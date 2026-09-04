import { describe, it, expect } from 'vitest';
import { cardBoardParaContaReceber } from './carregar-board';
import type { CardBoard } from '../domain/types';

function cardBoard(over: Partial<CardBoard> = {}): CardBoard {
  return {
    origem: 'HM', contato_hm_id: 'c1', comprador_id: 'p1', aluno_id: null,
    nome: 'Fulano', email: 'f@x.com',
    turma: 'T39', turma_origem: null, canal: 'HT ATM', publico: 'lead_novo',
    produto: 'Holding Masters',
    estagio_chave: null, estagio_nome: null, estagio_aba: null, vendedor: null,
    status_financeiro: 'sem_acordo', faixa: 'sem_tratativa',
    pacote: 15000, total_pago_bruto: 300, total_pago_liquido: 287,
    sinal_bruto: 300, saldo_pago_bruto: 0, saldo_a_pagar: 14700, credito: null, pago_pct: 2,
    vencimento: null, dias_atraso: null, entrou_estagio_em: null, dias_no_estagio: null,
    solicitou_cancelamento: false, cancelamento_em: null, cancelamento_efetivado_em: null,
    quitado_em: null, reembolso_em: null, reembolso_valor: null,
    oferta_codigo: null, oferta_enviada_em: null, ultimo_pagamento_em: null,
    aurum_excecao: null, aurum_excecao_motivo: null, aurum_rotulo_operador: null,
    acao_nome: null, acao_data: null,
    reuniao_resultado: null, intencao_pagamento: null, intencao_pagamento_obs: null,
    reuniao_motivo_tipo: null, reuniao_retomar_em: null,
    pacote_regra: null, divergencia_regra: null,
    ...over,
  };
}

describe('cardBoardParaContaReceber — pacote_regra/divergencia_regra', () => {
  it('repassa pacote_regra/divergencia_regra REAIS da RPC (não mais hardcoded null)', () => {
    const c = cardBoardParaContaReceber(cardBoard({ pacote: 17604.31, pacote_regra: 15000, divergencia_regra: 2604.31 }));
    expect(c.pacote_regra).toBe(15000);
    expect(c.divergencia_regra).toBe(2604.31);
  });

  it('degradação segura: RPC ainda não aplicada em produção → null repassado como null, não crasha', () => {
    const c = cardBoardParaContaReceber(cardBoard({ pacote_regra: null, divergencia_regra: null }));
    expect(c.pacote_regra).toBeNull();
    expect(c.divergencia_regra).toBeNull();
  });
});
