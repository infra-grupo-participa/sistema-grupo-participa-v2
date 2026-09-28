import { describe, expect, it } from 'vitest';
import { diferencaPct, resumirPorCategoria, valorParaConferencia, vendasParaConferencia, type Funil } from './funis';

const f = (x: Partial<Funil>): Funil => ({
  evento_id: 1, nome: 'E', categoria: 'jornada', setor: 'educacao', inicio: '2022-01-24', fim: '2022-01-28', carrinho_inicio: null,
  venda_ate: '2022-02-01', ingresso_de: '2021-12-01', ingressos: 0, ingressos_bruto: 0, ingressos_liquido: 0, oferta_vendas: 10,
  oferta_compradores: 10, oferta_estornos: 1, oferta_bruto: 1000, oferta_liquido: 900, compradores: 10, bruto: 1000, liquido: 900,
  ref_vendas: null, ref_valor: null, ref_tipo: null, ref_fonte: null, observacao: null, conta_ausente: false, liquido_conferencia: 950, ...x,
});

describe('funis', () => {
  it('resume por categoria com média por evento', () => {
    const r = resumirPorCategoria([f({}), f({ evento_id: 2, bruto: 3000 }), f({ evento_id: 3, categoria: 'clinica', bruto: 500 })]);
    expect(r[0]).toMatchObject({ categoria: 'jornada', eventos: 2, bruto: 4000, mediaPorEvento: 2000 });
    expect(r[1].categoria).toBe('clinica');
  });
  it('conferência: vendas pagas; clínica compara ingressos', () => {
    expect(vendasParaConferencia(f({}))).toBe(10);
    expect(vendasParaConferencia(f({ categoria: 'clinica', ingressos: 88 }))).toBe(88);
  });
  it('conferência de valor: líquido incl. estornos; clínica só o ingresso, pelo tipo registrado', () => {
    expect(valorParaConferencia(f({ ref_tipo: 'comissao' }))).toBe(950);
    expect(valorParaConferencia(f({ ref_tipo: 'bruto' }))).toBe(1000);
    const clin = { categoria: 'clinica', ingressos_bruto: 101017, ingressos_liquido: 95597, bruto: 160000, liquido_conferencia: 150000 };
    expect(valorParaConferencia(f({ ...clin, ref_tipo: 'liquido' }))).toBe(95597);
    expect(valorParaConferencia(f({ ...clin, ref_tipo: 'bruto' }))).toBe(101017);
  });
  it('diferença % contra o registrado', () => {
    expect(diferencaPct(626, 626)).toBe(0);
    expect(diferencaPct(110, 100)).toBeCloseTo(10);
    expect(diferencaPct(5, null)).toBeNull();
  });
});
