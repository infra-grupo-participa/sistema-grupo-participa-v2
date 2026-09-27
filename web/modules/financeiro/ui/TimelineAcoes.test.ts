import { describe, expect, it } from 'vitest';
import { agruparPorAcao } from './TimelineAcoes';
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
});
