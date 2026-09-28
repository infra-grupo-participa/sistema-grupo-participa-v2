import { describe, expect, it } from 'vitest';
import { agruparPorAcao, chaveDaAcao } from './TimelineAcoes';
import type { CardComEfeito } from '../application/carregar-board';

const c = (acaoNome: string | null, acaoData: string | null) => ({ acaoNome, acaoData }) as unknown as CardComEfeito;

describe('agruparPorAcao', () => {
  it('eventos em ordem de data; grupos fora de evento no fim, sem data; sem ação por último', () => {
    const r = agruparPorAcao([
      c('HT30 — 09 e 10/08', '2026-08-09T03:00:00Z'),
      c('Comercial (venda direta)', '2026-09-18T00:00:00Z'),
      c('Lançamento T39', '2026-06-25T03:00:00Z'),
      c('Base antiga (antes de 2026)', '2022-01-01T00:00:00Z'),
      c('Comercial (venda direta)', '2026-05-29T00:00:00Z'),
      c(null, null),
    ]);
    expect(r.map((a) => a.nome)).toEqual([
      'Lançamento T39', 'HT30 — 09 e 10/08', 'Comercial (venda direta)', 'Base antiga (antes de 2026)', 'Sem ação identificada',
    ]);
    expect(r.find((a) => a.nome.startsWith('Comercial'))!.data).toBeNull();
    expect(r.find((a) => a.nome.startsWith('Comercial'))!.total).toBe(2);
  });
  it('um botão por ação, sem agrupar por turma; o rótulo tira o prefixo da turma', () => {
    const r = agruparPorAcao([
      c('T40 · Holding Total HT30 (09–10/08/2026)', '2026-08-09T03:00:00Z'),
      c('T39 · Holding Total ATM (06/07/2026)', '2026-07-06T03:00:00Z'),
      c('T39 · Reunião fechada (25/06/2026)', '2026-06-25T03:00:00Z'),
      c('T39 · Holding Total ATM (06/07/2026)', '2026-07-06T03:00:00Z'),
    ]);
    expect(r.map((a) => [a.nome, a.total])).toEqual([
      ['Reunião fechada (25/06/2026)', 1], ['Holding Total ATM (06/07/2026)', 2], ['Holding Total HT30 (09–10/08/2026)', 1],
    ]);
    expect(r[1].chave).toBe('T39 · Holding Total ATM (06/07/2026)');
    expect(chaveDaAcao('Comercial (venda direta)')).toBe('Comercial (venda direta)');
  });
});
