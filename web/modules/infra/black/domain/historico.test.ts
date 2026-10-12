import { describe, expect, it } from 'vitest';
import { baseFicticia, PRIMEIRO_DIA, ULTIMO_DIA } from '../infrastructure/fixtures/gerador';
import { CONFIG_BLACK } from '../infrastructure/fixtures/catalogo';
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { diasDeCaptacao, metaAcumuladaAte, serieHistorico } from './historico';

const b = baseFicticia();
const todos: string[] = [];
for (let d = PRIMEIRO_DIA; d <= ULTIMO_DIA; d = deslocarDia(d, 1)) todos.push(d);

describe('histórico', () => {
  it('meta acumulada = 650 × dias desde 12/10 (sem meta antes)', () => {
    expect(metaAcumuladaAte('2026-10-11', CONFIG_BLACK)).toBeNull();
    expect(metaAcumuladaAte('2026-10-12', CONFIG_BLACK)).toBe(650);
    expect(diasDeCaptacao('2026-11-03', '2026-10-12')).toBe(23);
    expect(metaAcumuladaAte('2026-11-03', CONFIG_BLACK)).toBe(23 * 650);
  });
  it('série: gasto e cadastros fecham com o total; pessoas acumuladas = pessoas únicas', () => {
    const s = serieHistorico(b.dias, b.linhas, todos, CONFIG_BLACK);
    expect(s.reduce((x, d) => x + d.gasto, 0)).toBeCloseTo(b.dias.reduce((x, d) => x + d.gasto, 0), 6);
    expect(s.reduce((x, d) => x + d.cadastros, 0)).toBe(b.linhas.length);
    expect(s[s.length - 1].pessoasAcumuladas).toBe(new Set(b.linhas.map((l) => l.pessoaId)).size);
  });
  it('período parcial: o acumulado parte de quem já estava na lista antes', () => {
    const parte = todos.filter((d) => d >= '2026-10-20');
    const s = serieHistorico(b.dias, b.linhas, parte, CONFIG_BLACK);
    const cheia = serieHistorico(b.dias, b.linhas, todos, CONFIG_BLACK);
    expect(s[s.length - 1].pessoasAcumuladas).toBe(cheia[cheia.length - 1].pessoasAcumuladas);
  });
});
