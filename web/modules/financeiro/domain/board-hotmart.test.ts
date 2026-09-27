import { describe, it, expect } from 'vitest';
import {
  explicarDivergencia, indexarBoardHotmart, rotuloParcelamento, somarHotmart, temDadoHotmart,
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
