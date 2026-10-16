import { describe, expect, it } from 'vitest';
import { pontosEvolucaoIngresso, resumoEvolucaoIngresso, rotuloDiaCompleto, temFonteDeGrupo } from './evolucao';

describe('pontosEvolucaoIngresso', () => {
  it('acumula entradas e leads e calcula a taxa como soma sobre soma', () => {
    const pontos = pontosEvolucaoIngresso([
      { dia: '2026-10-02', leads: 100, grupo_entradas: 10 },
      { dia: '2026-10-01', leads: 100, grupo_entradas: 50 },
      { dia: '2026-10-03', leads: 200, grupo_entradas: 140 },
    ]);
    expect(pontos.map((p) => p.dia)).toEqual(['2026-10-01', '2026-10-02', '2026-10-03']);
    expect(pontos.map((p) => p.entradasDia)).toEqual([50, 10, 140]);
    expect(pontos.map((p) => p.entradasAcumuladas)).toEqual([50, 60, 200]);
    expect(pontos.map((p) => p.leadsAcumulados)).toEqual([100, 200, 400]);
    // 50%, 30% e 50%: não é a média das taxas diárias (50%, 10%, 70%).
    expect(pontos.map((p) => p.pct)).toEqual([50, 30, 50]);
  });

  it('o último dia bate com o total do período', () => {
    const pontos = pontosEvolucaoIngresso([
      { dia: '2026-10-01', leads: 3, grupo_entradas: 1 },
      { dia: '2026-10-02', leads: 0, grupo_entradas: 1 },
    ]);
    expect(resumoEvolucaoIngresso(pontos)).toEqual({ entradas: 2, leads: 3, pct: (2 / 3) * 100 });
  });

  it('sem fonte de grupo (entrada nula) não vira zero', () => {
    const pontos = pontosEvolucaoIngresso([{ dia: '2026-10-01', leads: 10, grupo_entradas: null }]);
    expect(pontos[0]).toEqual({ dia: '2026-10-01', entradasDia: null, entradasAcumuladas: null, leadsAcumulados: 10, pct: null });
    expect(temFonteDeGrupo(pontos)).toBe(false);
  });

  it('entrada zero medida é zero, e dia sem lead acumulado não tem taxa', () => {
    const pontos = pontosEvolucaoIngresso([
      { dia: '2026-10-01', leads: 0, grupo_entradas: 0 },
      { dia: '2026-10-02', leads: 5, grupo_entradas: 0 },
    ]);
    expect(pontos[0].pct).toBeNull();
    expect(pontos[1].pct).toBe(0);
    expect(temFonteDeGrupo(pontos)).toBe(true);
  });

  it('aceita número em texto e descarta linha sem dia válido', () => {
    const pontos = pontosEvolucaoIngresso([{ dia: '2026-10-01', leads: '4', grupo_entradas: '2' }, { dia: null, leads: 1, grupo_entradas: 1 }, {}]);
    expect(pontos).toHaveLength(1);
    expect(pontos[0].pct).toBe(50);
  });

  it('série vazia dá resumo sem dado', () => {
    expect(resumoEvolucaoIngresso([])).toEqual({ entradas: null, leads: null, pct: null });
    expect(rotuloDiaCompleto('2026-10-16')).toBe('16/10/2026');
  });
});
