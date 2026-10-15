import { describe, expect, it } from 'vitest';
import { arredondarInteiroRitmo, iscaDoNomeConjunto, projetarRitmo, tipoConteudoC1 } from './ritmo';

describe('régua da captação Black', () => {
  it('calcula catch-up e meta acumulada com semente anterior ao início da captação', () => {
    const r = projetarRitmo({ hoje: '2026-10-15', meta: 15_000, semente: 154, realizados: new Map([
      ['2026-10-12', 18], ['2026-10-13', 60], ['2026-10-14', 36], ['2026-10-15', 17],
    ]) });
    expect(r.diasRestantes).toBe(19);
    expect(r.acumuladoHoje).toBe(285);
    expect(arredondarInteiroRitmo(r.acumuladoHoje)).toBe(285);
    expect(r.necessarioPorDia).toBeCloseTo(774.474, 2);
    expect(arredondarInteiroRitmo(r.necessarioPorDia, 'cima')).toBe(775);
    expect(r.faltaHoje).toBeCloseTo(757.474, 2);
    expect(arredondarInteiroRitmo(r.faltaHoje, 'cima')).toBe(758);
    expect(r.mediaDias).toEqual(['2026-10-12', '2026-10-13', '2026-10-14']);
    expect(r.media).toBe(38);
    expect(r.projecao).toBe(1007);
    expect(arredondarInteiroRitmo(r.media)).toBe(38);
    expect(arredondarInteiroRitmo(r.projecao)).toBe(1007);
    expect(r.pontos.slice(0, 4).map((p) => p.metaDia)).toEqual([expect.closeTo(645.478, 2), expect.closeTo(674, 2), expect.closeTo(703.238, 2), expect.closeTo(736.595, 2)]);
    expect(r.pontos[0].metaAcumulada).toBeCloseTo(799.478, 2);
  });

  it('ignora dia sem gasto na média e calcula investimento contra o orçamento de captação', () => {
    const r = projetarRitmo({ hoje: '2026-10-15', meta: 220_000, realizados: new Map([
      ['2026-10-12', 0], ['2026-10-13', 523.02], ['2026-10-14', 671.07], ['2026-10-15', 349.17],
    ]) });
    expect(r.diasRestantes).toBe(19);
    expect(r.acumuladoHoje).toBeCloseTo(1543.26, 2);
    expect(r.necessarioPorDia).toBeCloseTo(11497.724, 2);
    expect(r.faltaHoje).toBeCloseTo(11148.554, 2);
    expect(r.mediaDias).toEqual(['2026-10-13', '2026-10-14']);
    expect(r.media).toBeCloseTo(597.045, 2);
    expect(r.projecao).toBeCloseTo(12887.115, 2);
  });

  it('classifica C1 e iscas pelo texto da fonte, sem inferir subtipo ausente', () => {
    expect(tipoConteudoC1('CF | TEASER | 01')).toBe('Teaser');
    expect(tipoConteudoC1('manifesto institucional')).toBe('Manifesto');
    expect(tipoConteudoC1('reel de exemplo')).toBe('Reels');
    expect(tipoConteudoC1('texto do post')).toBe('Sem tipo no nome');
    expect(iscaDoNomeConjunto('01 | MIX PQ | CHECKUP')).toBe('Checkup');
    expect(iscaDoNomeConjunto('01 | MIX PQ | CONSULTORIA')).toBeNull();
  });

  it('arredonda pessoas ao inteiro, para cima no necessário e no que falta', () => {
    expect(arredondarInteiroRitmo(287)).toBe(287);
    expect(arredondarInteiroRitmo(774.4, 'cima')).toBe(775);
    expect(arredondarInteiroRitmo(755.4, 'cima')).toBe(756);
    expect(arredondarInteiroRitmo(38.4)).toBe(38);
    expect(arredondarInteiroRitmo(1008.6)).toBe(1009);
    expect(arredondarInteiroRitmo(null, 'cima')).toBeNull();
  });
});
