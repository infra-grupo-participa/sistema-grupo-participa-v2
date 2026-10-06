import { describe, expect, it } from 'vitest';
import { agruparPorLancamento, resumoJornada } from './jornada';
import type { PontoJornada } from './types';

const p = (id: string, em: string, tipo: PontoJornada['tipo'], lancamento: string | null, extra: Partial<PontoJornada> = {}): PontoJornada => ({
  id, contatoId: 'c', tipo, em, titulo: id, detalhe: null, fonte: 'crm', lancamento, produto: null, utm: null, valor: null, negocioId: null, ...extra,
});

describe('jornada', () => {
  const pontos = [
    p('a1', '2026-03-01T10:00:00Z', 'inscricao', 'ht30', { utm: { source: 'metaads', campaign: 'ht30' } }),
    p('a2', '2026-03-05T10:00:00Z', 'compra', 'ht30', { valor: 297 }),
    p('b1', '2026-09-01T10:00:00Z', 'inscricao', 'imersao-set26', { utm: { source: 'ActiveCampaign', campaign: 'imersao-set26' } }),
    p('b2', '2026-09-10T10:00:00Z', 'compra', 'imersao-set26', { valor: 30000 }),
    p('b3', '2026-09-12T10:00:00Z', 'reembolso', 'imersao-set26', { valor: 30000 }),
    p('n1', '2026-09-20T10:00:00Z', 'nota', null),
  ];
  it('agrupa por lançamento, mais recente primeiro, com a UTM de cada entrada', () => {
    const b = agruparPorLancamento(pontos);
    expect(b.map((x) => x.lancamento)).toEqual([null, 'imersao-set26', 'ht30']);
    expect(b[1].entrada?.utm?.source).toBe('ActiveCampaign');
    expect(b[2].entrada?.utm?.source).toBe('metaads');
    expect(b[1].pontos[0].id).toBe('b3');
  });
  it('reembolso desconta do valor pago', () => {
    const b = agruparPorLancamento(pontos);
    expect(b[1].valorPago).toBe(0);
    expect(b[1].reembolsou).toBe(true);
    expect(resumoJornada(pontos)).toMatchObject({ lancamentos: 2, compras: 2, reembolsos: 1, valorPago: 297, desde: '2026-03-01T10:00:00Z' });
  });
});
