import { describe, it, expect } from 'vitest';
import { contarSituacoes, resumirHotmart, serieHotmart, type DiaHotmart, type PessoaHotmart } from './hotmart';

function dia(over: Partial<DiaHotmart> = {}): DiaHotmart {
  return {
    dia: '2026-09-26', vendas: 0, valor_oferta: 0, cobrado_cliente: 0, juros: 0, taxa_hotmart: 0,
    liquido: 0, liquido_estimado: 0, estornos: 0, valor_estornado: 0, recusadas: 0, boletos_gerados: 0,
    compradores: 0, ...over,
  };
}

describe('resumirHotmart', () => {
  it('soma o dia da Imersão HT como a Hotmart mostra (9 × 15k, líquido 14.399)', () => {
    const r = resumirHotmart([
      dia({ vendas: 9, valor_oferta: 135000, cobrado_cliente: 162408.9, juros: 27408.9, taxa_hotmart: 5409, liquido: 129591, recusadas: 26 }),
    ]);
    expect(r.valorOferta).toBe(135000);
    expect(r.liquido).toBe(129591);
    expect(r.taxa).toBe(5409);
    expect(r.recusadas).toBe(26);
    expect(r.margem).toBeCloseTo(0.9599, 3);
  });

  it('aceita numeric do Postgres vindo como string', () => {
    const r = resumirHotmart([dia({ valor_oferta: '100.50' as unknown as number, liquido: '96.48' as unknown as number })]);
    expect(r.valorOferta).toBe(100.5);
    expect(r.liquido).toBe(96.48);
  });

  it('sem venda, margem é null — nunca 0% inventado', () => {
    expect(resumirHotmart([]).margem).toBeNull();
    expect(resumirHotmart([dia({ recusadas: 3 })]).margem).toBeNull();
  });
});

describe('contarSituacoes', () => {
  it('conta por situação e mantém zero nas que não aparecem', () => {
    const p = (situacao: PessoaHotmart['situacao']) => ({ situacao }) as PessoaHotmart;
    const c = contarSituacoes([p('devendo'), p('devendo'), p('ativo')]);
    expect(c.devendo).toBe(2);
    expect(c.ativo).toBe(1);
    expect(c.reembolsado).toBe(0);
  });
});

describe('serieHotmart (Faturamento Diário)', () => {
  it('preenche o dia sem venda com zero explícito e a variação compara com o dia de verdade anterior', () => {
    const s = serieHotmart([
      dia({ dia: '2026-09-03', vendas: 1, valor_oferta: 50, taxa_hotmart: 3, liquido: 47 }),
      dia({ dia: '2026-09-01', vendas: 2, valor_oferta: 100, taxa_hotmart: 5, liquido: 95 }),
    ]);
    expect(s.map((d) => [d.dia, d.preenchido, d.bruto, d.acumulado])).toEqual([
      ['2026-09-01', false, 100, 100],
      ['2026-09-02', true, 0, 100],
      ['2026-09-03', false, 50, 150],
    ]);
    expect(s[1].variacaoDiaAnterior).toBe(-100);
    expect(s[2].variacaoDiaAnterior).toBeNull(); // dia anterior sem venda: não inventa %
  });

  it('coprodução = oferta − taxa − líquido (Aurum antigo); HM sem repasse fica 0', () => {
    const [aurum] = serieHotmart([dia({ valor_oferta: 21599, taxa_hotmart: 864.96, liquido: 20517.16 })]);
    expect(aurum.repasses).toBeCloseTo(216.88, 2);
    const [hm] = serieHotmart([dia({ valor_oferta: 15000, taxa_hotmart: 601, liquido: 14399 })]);
    expect(hm.repasses).toBe(0);
  });

  it('sem dia, série vazia', () => {
    expect(serieHotmart([])).toEqual([]);
  });
});

describe('resumirHotmart — do bruto ao líquido', () => {
  it('bruto − taxa − repasses = líquido, e a taxa em % do bruto', () => {
    const r = resumirHotmart([dia({ vendas: 1, valor_oferta: 15000, taxa_hotmart: 601, liquido: 14399 })]);
    expect(r.valorOferta - r.taxa - r.repasses).toBeCloseTo(r.liquido, 2);
    expect(r.taxaPct).toBeCloseTo(0.0401, 4);
    expect(resumirHotmart([]).taxaPct).toBeNull();
  });
});
