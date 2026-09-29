import { describe, it, expect } from 'vitest';
import {
  descreverBoletoAberto, explicarDivergencia, fmtMesAno, indexarBoardHotmart, listarBoletosAbertos, metaACaminho, rotuloParcelamento,
  somarHotmart, temDadoHotmart, valorACaminho,
} from './board-hotmart';
import type { BoardHotmart } from './hotmart';

function linha(over: Partial<BoardHotmart> = {}): BoardHotmart {
  return {
    contato_hm_id: 'c1', origem: 'HM', encontrado: true, pessoa_chave: 'p1', cards_da_pessoa: 1,
    vendas_pagas: 2, pago_bruto: 1000, taxa_hotmart: 100, coproducao: 0, liquido: 900,
    cobrado_cliente: 1100, juros: 100, parcelas_max: 12, forma_pagamento_principal: 'CREDIT_CARD_VISA',
    ultimo_pagamento_em: '2026-09-01', ultimo_pagamento_valor: 500,
    parcelas_devidas: 0, valor_devido: 0, devido_antigo: 0, estornos: 0, valor_estornado: 0,
    falta_no_board: 0, valor_falta_no_board: 0, board_sem_hotmart: 0, diverge: false,
    sincronizado_em: '2026-09-27T10:00:00Z',
    ...over,
  };
}

const fmt = (n: number) => `R$ ${n}`;

describe('indexarBoardHotmart', () => {
  it('converte numeric que chega como string', () => {
    const m = indexarBoardHotmart([linha({ pago_bruto: '1234.5' as unknown as number, parcelas_max: null })]);
    expect(m.get('c1')!.pago_bruto).toBe(1234.5);
    expect(m.get('c1')!.parcelas_max).toBeNull();
  });
});

describe('somarHotmart', () => {
  it('2 cards da mesma pessoa somam UMA vez', () => {
    const m = indexarBoardHotmart([
      linha({ contato_hm_id: 'a', pessoa_chave: 'p1', cards_da_pessoa: 2, valor_devido: 300, parcelas_devidas: 1 }),
      linha({ contato_hm_id: 'b', pessoa_chave: 'p1', cards_da_pessoa: 2, valor_devido: 300, parcelas_devidas: 1 }),
      linha({ contato_hm_id: 'c', pessoa_chave: 'p2', pago_bruto: 500, taxa_hotmart: 50, liquido: 450, juros: 0, cobrado_cliente: 500 }),
    ]);
    const t = somarHotmart(['a', 'b', 'c'], m);
    expect(t.cardsComDado).toBe(3);
    expect(t.pessoas).toBe(2);
    expect(t.bruto).toBe(1500);
    expect(t.taxa).toBe(150);
    expect(t.liquido).toBe(1350);
    expect(t.juros).toBe(100);
    expect(t.devido).toBe(300);
    expect(t.parcelasDevidas).toBe(1);
  });

  it('encontrado=false e card sem linha não entram na soma e contam como sem dado', () => {
    const m = indexarBoardHotmart([
      linha({ contato_hm_id: 'a' }),
      linha({ contato_hm_id: 'x', encontrado: false, pessoa_chave: null, pago_bruto: 999 }),
    ]);
    const t = somarHotmart(['a', 'x', 'sem-linha'], m);
    expect(t.cardsComDado).toBe(1);
    expect(t.cardsSemDado).toBe(2);
    expect(t.bruto).toBe(1000);
  });

  it('mesma pessoa_chave em produtos diferentes são somas separadas', () => {
    const m = indexarBoardHotmart([
      linha({ contato_hm_id: 'a', origem: 'HM' }),
      linha({ contato_hm_id: 'b', origem: 'AURUM', diverge: null }),
    ]);
    expect(somarHotmart(['a', 'b'], m).pessoas).toBe(2);
  });

  it('encontrado sem pessoa_chave usa o próprio card como chave (não funde com outro)', () => {
    const m = indexarBoardHotmart([
      linha({ contato_hm_id: 'a', pessoa_chave: null }),
      linha({ contato_hm_id: 'b', pessoa_chave: null }),
    ]);
    expect(somarHotmart(['a', 'b'], m).bruto).toBe(2000);
  });

  it('conta cards divergentes por card, não por pessoa', () => {
    const m = indexarBoardHotmart([
      linha({ contato_hm_id: 'a', diverge: true }),
      linha({ contato_hm_id: 'b', diverge: true }),
      linha({ contato_hm_id: 'c', pessoa_chave: 'p9', diverge: null }),
    ]);
    expect(somarHotmart(['a', 'b', 'c'], m).cardsDivergentes).toBe(2);
  });

  it('recorte vazio zera tudo', () => {
    expect(somarHotmart([], new Map()).bruto).toBe(0);
  });
});

describe('temDadoHotmart', () => {
  it('só com linha e encontrado=true', () => {
    expect(temDadoHotmart(undefined)).toBe(false);
    expect(temDadoHotmart(linha({ encontrado: false }))).toBe(false);
    expect(temDadoHotmart(linha())).toBe(true);
  });
});

describe('rotuloParcelamento', () => {
  it('à vista, até Nx e sem venda', () => {
    expect(rotuloParcelamento(1)).toBe('à vista');
    expect(rotuloParcelamento(12)).toBe('até 12x');
    expect(rotuloParcelamento(null)).toBeNull();
  });
});

describe('explicarDivergencia', () => {
  it('null quando não diverge ou não se aplica (Aurum)', () => {
    expect(explicarDivergencia(linha({ diverge: false }), fmt)).toBeNull();
    expect(explicarDivergencia(linha({ diverge: null }), fmt)).toBeNull();
  });

  it('explica os dois lados, com singular/plural', () => {
    expect(explicarDivergencia(linha({ diverge: true, falta_no_board: 2, valor_falta_no_board: 800, board_sem_hotmart: 1 }), fmt)).toBe(
      '2 vendas pagas na Hotmart (R$ 800) não estão lançadas no board; 1 lançamento do board não tem par na Hotmart (ou foi estornado lá).',
    );
  });
});

describe('assinatura HM (contrato à parte)', () => {
  it('caso Carlos Roberto: 12 × R$ 1.997 = R$ 23.964 normalizado', () => {
    const m = indexarBoardHotmart([linha({
      assinatura_mensalidades: 12, assinatura_valor: '23964.00' as unknown as number,
      assinatura_de: '2025-10-03', assinatura_ate: '2026-09-03', assinatura_ativa: true,
    })]);
    const h = m.get('c1')!;
    expect(h.assinatura_valor).toBe(23964);
  });
  it('sem assinatura (colunas ausentes da função antiga) → 0', () => {
    const h = indexarBoardHotmart([linha()]).get('c1')!;
    expect(h.assinatura_mensalidades).toBe(0);
  });
  it('fmtMesAno', () => {
    expect(fmtMesAno('2026-09-03')).toBe('09/2026');
    expect(fmtMesAno(null)).toBeNull();
  });
});

describe('descreverBoletoAberto', () => {
  const brl = (n: number) => `R$ ${n}`;
  it('sem boleto → null', () => {
    expect(descreverBoletoAberto({ boleto_aberto_n: 0 } as never, '2026-09-27', brl)).toBeNull();
  });
  it('boleto de saldo gerado há 3 dias', () => {
    const d = descreverBoletoAberto({ boleto_aberto_n: 1, boleto_aberto_valor: 12000, boleto_aberto_em: '2026-09-24',
      boleto_aberto_categoria: 'diferenca', boleto_aberto_metodo: 'BILLET' } as never, '2026-09-27', brl)!;
    expect(d.titulo).toBe('Boleto de saldo em aberto: R$ 12000');
    expect(d.detalhe).toContain('gerado há 3 dias');
    expect(d.detalhe).toContain('não informa o vencimento');
  });
  it('Pix de compra cheia gerado hoje', () => {
    const d = descreverBoletoAberto({ boleto_aberto_n: 2, boleto_aberto_valor: 1300, boleto_aberto_em: '2026-09-27',
      boleto_aberto_categoria: 'compra_cheia', boleto_aberto_metodo: 'PIX' } as never, '2026-09-27', brl)!;
    expect(d.curto).toBe('Pix em aberto · R$ 1300');
    expect(d.titulo).toContain('(2 gerados)');
    expect(d.detalhe).toContain('gerado hoje');
  });
});

describe('valorACaminho / listarBoletosAbertos (z76)', () => {
  const lista = [
    { valor: 15000, categoria: 'compra_cheia', rotulo: 'compra_cheia', oferta_codigo: 'abc', metodo: 'BILLET', pedido_em: '2026-09-26' },
    { valor: 697, categoria: null, rotulo: 'desconhecida', oferta_codigo: null, metodo: 'PIX', pedido_em: '2026-09-29' },
  ];
  it('soma a lista, nunca o pago/saldo', () => {
    expect(valorACaminho(linha({ boletos_abertos: lista, boleto_aberto_n: 2, boleto_aberto_valor: 99 }))).toBe(15697);
  });
  it('sem lista (função anterior à z76) → soma antiga; sem boleto → 0', () => {
    expect(valorACaminho(linha({ boleto_aberto_n: 1, boleto_aberto_valor: 1300 }))).toBe(1300);
    expect(valorACaminho(linha())).toBe(0);
    expect(valorACaminho(null)).toBe(0);
  });
  it('uma linha por boleto: tipo pelo catálogo, meio e há quantos dias (sem vencimento)', () => {
    const l = listarBoletosAbertos(linha({ boletos_abertos: lista }), '2026-09-29');
    expect(l.map((b) => [b.valor, b.tipo, b.meio, b.quando])).toEqual([
      [15000, 'compra cheia', 'Boleto', 'gerado há 3 dias'],
      [697, 'oferta desconhecida', 'Pix', 'gerado hoje'],
    ]);
    expect(listarBoletosAbertos(linha(), '2026-09-29')).toEqual([]);
  });
  it('metaACaminho: dias do 1º da lista (a RPC manda o mais recente primeiro); "Pix" só se todos forem Pix; sem lista → null', () => {
    expect(metaACaminho(linha({ boletos_abertos: lista }), '2026-09-29')).toBe('2 gerados · há 3d');
    expect(metaACaminho(linha({ boletos_abertos: [lista[1]] }), '2026-09-29')).toBe('Pix · hoje');
    expect(metaACaminho(linha({ boleto_aberto_n: 1, boleto_aberto_valor: 1 }), '2026-09-29')).toBeNull();
  });
});
