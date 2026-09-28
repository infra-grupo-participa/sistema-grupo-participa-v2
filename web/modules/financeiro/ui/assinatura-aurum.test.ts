// Reprovação do João (28/09): pessoa com card AURUM que paga a mensalidade do HM antigo não aparecia em lugar nenhum.
// Renderiza o card e o "Em uma olhada" de um card AURUM (HTML estático, sem navegador) e confere o bloco Assinatura HM.
// Prova conteúdo, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { CardBoardView } from './CardBoard';
import { EmUmaOlhada } from './FichaPagamentos';
import { assinaturaDoCard, indexarAssinaturaHM, resumoAssinaturaCard, type AssinaturaHMBoard } from '../domain/assinatura-hm';
import type { BoardHotmart } from '../domain/hotmart';
import type { CardComEfeito } from '../application/carregar-board';
import type { ContaReceber } from '../domain/types';

const conta = {
  contato_hm_id: 'c-aurum', nome: 'Maria Aurum', email: 'm@x.com', produto: 'Aurum', status_financeiro: 'em_dia',
  total_pago_bruto: 10000, pacote: 58700, saldo_a_pagar: 48700, pago_pct: null, dias_atraso: 0, vencimento: null,
  estagio_nome: null, vendedor: null, reuniao_motivo_tipo: null, reuniao_retomar_em: null, intencao_pagamento: null,
  pacote_regra: null, divergencia_regra: null,
} as unknown as ContaReceber;
const card = {
  conta, origem: 'AURUM', cor: 'azul', urgencia: 0, diasNoEstagio: null, reserva: false, faixaFunil: null, motivoUrgencia: null,
} as unknown as CardComEfeito;
// Linha AURUM de fn_fin_board_hotmart: a CTE `ass` só preenche HM → assinatura_* zerado/nulo.
const hmAurum = {
  contato_hm_id: 'c-aurum', origem: 'AURUM', encontrado: true, pessoa_chave: 'p1', cards_da_pessoa: 1,
  vendas_pagas: 1, pago_bruto: 10000, taxa_hotmart: 0, coproducao: 0, liquido: 9000, cobrado_cliente: 10000, juros: 0,
  parcelas_max: 1, forma_pagamento_principal: null, ultimo_pagamento_em: null, ultimo_pagamento_valor: null,
  parcelas_devidas: 0, valor_devido: 0, devido_antigo: 0, estornos: 0, valor_estornado: 0,
  falta_no_board: 0, valor_falta_no_board: 0, board_sem_hotmart: 0, diverge: null, sincronizado_em: null,
  assinatura_mensalidades: 0, assinatura_valor: 0, assinatura_de: null, assinatura_ate: null, assinatura_ativa: null,
} as BoardHotmart;
const mapa = indexarAssinaturaHM([{
  pessoa_chave: 'p1', mensalidades_pagas: 12, pago: 23964, primeira: '2025-10-03', ultima_paga: '2026-09-03',
  ainda_paga: true, atraso_120d_n: 2, atraso_120d_valor: 3994, turma_origem: 'T29',
} satisfies AssinaturaHMBoard]);

describe('card AURUM com mensalidade do HM antigo', () => {
  it('o card mostra o bloco Assinatura HM e a mensalidade em atraso', () => {
    const html = renderToStaticMarkup(createElement(CardBoardView, {
      card, onOpen: () => {}, hojeISO: '2026-09-28', hotmart: hmAurum, assinatura: assinaturaDoCard(hmAurum, mapa),
    }));
    expect(html).toContain('Assinatura HM: 12 ×');
    expect(html).toContain('mensalidade em atraso: 2');
    expect(html).toContain('AURUM');
  });
  it('sem mensalidade, o card Aurum fica como era (sem bloco)', () => {
    const html = renderToStaticMarkup(createElement(CardBoardView, {
      card, onOpen: () => {}, hojeISO: '2026-09-28', hotmart: hmAurum, assinatura: null,
    }));
    expect(html).not.toContain('Assinatura HM');
  });
  it('a ficha ("Em uma olhada") mostra o atraso da mensalidade sem mexer no devendo', () => {
    const html = renderToStaticMarkup(createElement(EmUmaOlhada, {
      conta, hm: hmAurum, carregando: false, assinatura: resumoAssinaturaCard(hmAurum, assinaturaDoCard(hmAurum, mapa)),
    }));
    expect(html).toContain('Assinatura HM: mensalidade em atraso: 2');
    expect(html).toContain('parcelas em dia');
  });
});
