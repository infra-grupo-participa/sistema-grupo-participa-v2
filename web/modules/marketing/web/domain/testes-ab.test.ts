import { describe, expect, it } from 'vitest';
import { amostraNecessaria, gruposAB, lerAB } from './testes-ab';
import type { PaginaMelhorias } from './tipos';

const pg = (pagina_id: number, codigo: string | null, entradas: number, leads: number, dias = 0): PaginaMelhorias => ({
  pagina_id, codigo, nome: codigo ?? 'x', funcao: 'captura', caminho: '/' + codigo + '/', visitas: entradas, sessoes: entradas, leads, mql: 0, dias,
  entradas, rejeicoes: 0, leads_entrada: leads, mql_entrada: 0,
  por_dia: Array.from({ length: dias }, (_, i) => ({ dia: `2026-10-${String(i + 1).padStart(2, '0')}`, entradas: Math.round(entradas / Math.max(1, dias)) })),
});

describe('testes A/B entre variações (testes.ts do Radar)', () => {
  it('agrupa pelo código da casa: ak1 + ak1-b + ak1-c; sem original ou sem variação não é teste', () => {
    const g = gruposAB([pg(1, 'ak1', 10, 1), pg(2, 'ak1-c', 10, 1), pg(3, 'ak1-b', 10, 1), pg(4, 'bl2', 10, 1), pg(5, 'zz9-b', 10, 1), pg(6, null, 10, 1), pg(7, 'bl2-otimizacao', 1, 1)]);
    expect(g).toHaveLength(1);
    expect(g[0].base).toBe('ak1');
    expect(g[0].variacoes.map((v) => v.codigo)).toEqual(['ak1-b', 'ak1-c']);
  });
  it('amostra para 80% de poder: 10% e 20% de diferença = 3.839 por versão', () => {
    expect(amostraNecessaria(0.1, 0.2)).toBe(3839);
    expect(amostraNecessaria(0, 0.2)).toBe(0);
  });
  it('trava até a amostra e 7 dias; depois dá o veredito', () => {
    expect(lerAB(pg(1, 'ak1', 1000, 100, 8), pg(2, 'ak1-b', 1000, 150, 8)).veredito).toBe('aguardando');
    const l = lerAB(pg(1, 'ak1', 5000, 500, 8), pg(2, 'ak1-b', 5000, 650, 8));
    expect(l.amostra).toBe(3839);
    expect(l.veredito).toBe('b_vence');
    expect(lerAB(pg(1, 'ak1', 5000, 500, 8), pg(2, 'ak1-b', 5000, 505, 8)).veredito).toBe('sem_diferenca');
    expect(lerAB(pg(1, 'ak1', 5000, 500, 6), pg(2, 'ak1-b', 5000, 650, 6)).veredito).toBe('aguardando');
  });
  it('divisão desigual e ritmo', () => {
    const l = lerAB(pg(1, 'ak1', 700, 70, 7), pg(2, 'ak1-b', 300, 30, 7), 'lead', 0.2, '2026-10-08');
    expect(l.divisao.desigual).toBe(true);
    expect(l.ritmo).toBeCloseTo(43, 0);
    expect(l.diasFaltam).toBeGreaterThan(0);
  });
});
