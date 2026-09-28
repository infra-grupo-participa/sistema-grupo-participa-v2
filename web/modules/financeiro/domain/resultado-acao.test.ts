import { describe, expect, it } from 'vitest';
import { resultadoPorAcao, type CardDaAcao } from './resultado-acao';

const c = (x: Partial<CardDaAcao>): CardDaAcao => ({ acaoNome: 'A', acaoData: '2026-07-06', status: 'em_pagamento', pago: 0, saldo: 0, ...x });

describe('resultadoPorAcao', () => {
  it('soma por ação, em ordem de data; morto não entra no a receber', () => {
    const r = resultadoPorAcao([
      c({ acaoNome: 'HT32', acaoData: '2026-09-26', pago: 15000, status: 'quitado' }),
      c({ acaoNome: 'HT ATM', pago: 300, saldo: 14700 }),
      c({ acaoNome: 'HT ATM', pago: 300, saldo: 14700, status: 'reembolsado' }),
      c({ acaoNome: 'HT ATM', pago: 0, saldo: 15000 }),
    ]);
    expect(r.map((x) => x.acao)).toEqual(['HT ATM', 'HT32']);
    expect(r[0]).toMatchObject({ pessoas: 3, pagaram: 2, saidas: 1, recebido: 600, aReceber: 29700 });
    expect(r[1]).toMatchObject({ pessoas: 1, quitados: 1, recebido: 15000, aReceber: 0 });
  });
});
