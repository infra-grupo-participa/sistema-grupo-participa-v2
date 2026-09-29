// Reprovação do João (29/09): o mesmo boleto aparecia 2–3 vezes no card; alerta com falso positivo; "Voltou em" sem
// rótulo de data. Renderiza card e ficha (HTML estático, sem navegador) e confere a JUNÇÃO RPC → mapeamento → tela.
// Prova conteúdo, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { CardBoardView } from './CardBoard';
import { FichaDrawer } from './FichaDrawer';
import { cardBoardParaContaReceber, type CardComEfeito } from '../application/carregar-board';
import type { FinanceiroRepository } from '../application/ports';
import type { BoardHotmart, BoletoAberto } from '../domain/hotmart';
import type { CardBoard } from '../domain/types';

const HOJE = '2026-09-29';

function bruto(over: Partial<CardBoard> = {}): CardBoard {
  return {
    origem: 'HM', contato_hm_id: 'c-ht30', comprador_id: 'p1', aluno_id: null,
    nome: 'Fulana HT30', email: 'f@x.com',
    turma: 'T39', turma_origem: null, canal: 'HT', publico: 'lead_novo', produto: 'Holding Masters',
    estagio_chave: null, estagio_nome: null, estagio_aba: null, vendedor: 'Carlos Vendedor',
    status_financeiro: 'sem_acordo', faixa: 'sem_tratativa',
    pacote: 15000, total_pago_bruto: 697, total_pago_liquido: 650,
    sinal_bruto: 697, saldo_pago_bruto: 0, saldo_a_pagar: 14303, credito: null, pago_pct: null,
    vencimento: null, dias_atraso: null, entrou_estagio_em: null, dias_no_estagio: 3,
    solicitou_cancelamento: false, cancelamento_em: null, cancelamento_efetivado_em: null,
    quitado_em: null, reembolso_em: null, reembolso_valor: null,
    oferta_codigo: null, oferta_enviada_em: null, ultimo_pagamento_em: null,
    aurum_excecao: null, aurum_excecao_motivo: null, aurum_rotulo_operador: null,
    acao_nome: 'Holding Total HT30 (09–10/08/2026)', acao_data: null,
    reuniao_resultado: null, intencao_pagamento: null, intencao_pagamento_obs: null,
    reuniao_motivo_tipo: null, reuniao_retomar_em: null,
    pacote_regra: null, divergencia_regra: null,
    voltou_nome: 'Imersão Holding Total HT32 (26–27/09/2026)', voltou_data: '2026-09-26T13:00:00+00:00', voltou_regra: 'janela do evento',
    ...over,
  };
}

function cardDe(b: CardBoard): CardComEfeito {
  return {
    conta: cardBoardParaContaReceber(b), origem: b.origem, faixaFunil: b.faixa, cor: 'azul', urgencia: 0,
    motivoUrgencia: null, reserva: false, acaoNome: b.acao_nome, acaoData: b.acao_data, diasNoEstagio: b.dias_no_estagio,
  } as CardComEfeito;
}

const boletoCheio: BoletoAberto = {
  valor: 15000, categoria: 'compra_cheia', rotulo: 'compra_cheia', oferta_codigo: 'cheio', metodo: 'BILLET', pedido_em: '2026-09-28',
};

function hm(over: Partial<BoardHotmart> = {}): BoardHotmart {
  return {
    contato_hm_id: 'c-ht30', origem: 'HM', encontrado: true, pessoa_chave: 'p1', cards_da_pessoa: 1,
    vendas_pagas: 1, pago_bruto: 697, taxa_hotmart: 50, coproducao: 0, liquido: 647, cobrado_cliente: 697, juros: 0,
    parcelas_max: 1, forma_pagamento_principal: 'PIX', ultimo_pagamento_em: '2026-08-10', ultimo_pagamento_valor: 697,
    parcelas_devidas: 0, valor_devido: 0, devido_antigo: 0, estornos: 0, valor_estornado: 0,
    falta_no_board: 0, valor_falta_no_board: 0, board_sem_hotmart: 0, diverge: false, sincronizado_em: null,
    boleto_aberto_n: 1, boleto_aberto_valor: 15000, boleto_aberto_em: '2026-09-28', boleto_aberto_categoria: 'compra_cheia',
    boleto_aberto_metodo: 'BILLET', boletos_abertos: [boletoCheio],
    ...over,
  };
}

/** Só o texto visível (sem atributos title/aria-label), com o espaço inseparável do Intl normalizado. */
const texto = (html: string) => html.replace(/<[^>]*>/g, ' ').replace(/ /g, ' ').replace(/\s+/g, ' ');
const quantas = (t: string, re: RegExp) => (t.match(re) ?? []).length;

function renderCard(b: CardBoard, h: BoardHotmart | null) {
  return renderToStaticMarkup(createElement(CardBoardView, { card: cardDe(b), onOpen: () => {}, hojeISO: HOJE, hotmart: h }));
}

describe('card HM — boleto, alerta e entrada/volta', () => {
  it('(a) HT30: entrou/voltou, alerta "a mais", "a caminho" UMA vez, sem selo duplicado e sem vendedor', () => {
    const html = renderCard(bruto(), hm());
    const t = texto(html);
    expect(t).toContain('Entrou por Holding Total HT30 (09–10/08/2026)');
    expect(t).toContain('Voltou em Imersão Holding Total HT32 (26–27/09/2026) · 26/09');
    expect(t).toContain('R$ 697 a mais');
    expect(quantas(t, /a caminho/gi)).toBe(1);
    expect(t).toMatch(/a caminho R\$ 15\.000,00 · há 1d/);
    expect(html).not.toContain('em aberto');
    expect(html).not.toContain('Carlos Vendedor');
    expect(t).toContain('parado há 3d');
  });

  it('(b) "Boleto Gerado" (pacote null, pago 0): "A caminho" é o número principal, sem "a mais" nem campos vazios', () => {
    const html = renderCard(
      bruto({ pacote: null, total_pago_bruto: 0, sinal_bruto: null, saldo_a_pagar: null, voltou_nome: null }),
      hm({ vendas_pagas: 0, pago_bruto: 0 }),
    );
    const t = texto(html);
    expect(t).toMatch(/A caminho R\$ 15\.000,00/);
    expect(quantas(t, /a caminho/gi)).toBe(1);
    expect(t).not.toContain('a mais');
    expect(t).not.toContain('Falta pagar');
    expect(t).not.toContain('Sem valor de pacote definido');
    expect(t).not.toContain('Voltou em');
  });

  it('(c) hotmart null não quebra e não inventa "a caminho"', () => {
    const t = texto(renderCard(bruto(), null));
    expect(t).toContain('Falta pagar');
    expect(t).not.toMatch(/caminho/i);
    expect(t).not.toContain('a mais');
  });

  it('RPC anterior à z76 (sem lista): card fica como era — só o selo, sem "a caminho"', () => {
    const t = texto(renderCard(bruto(), hm({ boletos_abertos: undefined })));
    expect(t).toMatch(/Boleto em aberto · R\$ 15\.000/);
    expect(t).not.toMatch(/caminho/i);
  });

  it('falso positivo medido: parcela da compra cheia (pago 2.552,28 + 1.276,14 < 15.000) não acende alerta', () => {
    const t = texto(renderCard(
      bruto({ sinal_bruto: 0, total_pago_bruto: 2552.28, saldo_a_pagar: 12447.72 }),
      hm({ boletos_abertos: [{ ...boletoCheio, valor: 1276.14 }] }),
    ));
    expect(t).not.toContain('a mais');
    expect(t).not.toMatch(/cheio/i); // nenhum selo de alerta, nem na forma sem número
    expect(quantas(t, /a caminho/gi)).toBe(1);
  });
});

describe('ficha HM — alerta completo, boletos e volta', () => {
  it('(d) alerta com texto completo, tabela de boletos e "Voltou em" rotulado como data da ação', () => {
    const b = bruto();
    const html = renderToStaticMarkup(createElement(FichaDrawer, {
      conta: cardBoardParaContaReceber(b), repo: {} as FinanceiroRepository, canEdit: false, canVerDoc: false,
      regua: [], hojeISO: HOJE, onClose: () => {}, onAcordoSalvo: () => {},
      hotmartPorCard: new Map([[b.contato_hm_id, hm()]]),
    }));
    const t = texto(html);
    expect(t).toContain(
      'Boleto do HM cheio não desconta o que já foi pago: se pagar, paga R$ 697,00 a mais. '
      + 'Mande o link do saldo de R$ 14.303,00: peça ao comercial um link do saldo nesse valor.',
    );
    expect(t).toMatch(/A caminho: R\$ 15\.000,00/);
    expect(t).toMatch(/R\$ 15\.000,00 Boleto · compra cheia gerado ontem/);
    expect(t).toContain('Voltou em');
    expect(t).toContain('Imersão Holding Total HT32 (26–27/09/2026) · ação em 26/09');
    expect(t).toContain('A data ao lado é a da ação, não a da compra.');
    expect(t).toContain('Entrou por');
  });
});
