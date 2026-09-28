import { describe, expect, it } from 'vitest';
import {
  agruparContratado, crescimentoReal, dependenciaEventos, mediaMovel, mesesFechados, preverComFaixa, preverModelo,
  quantil, regressao, somarMeses, type FaturamentoAcao, type MesValor,
} from './faturamento-analise';

const meses = (valores: number[], ini = '2024-01'): MesValor[] =>
  valores.map((bruto, i) => ({ chave: somarMeses(ini, i), bruto, vendas: 10 }));

describe('básicos', () => {
  it('média móvel de 3 com início parcial', () => {
    expect(mediaMovel([3, 6, 9, 12], 3)).toEqual([3, 4.5, 6, 9]);
  });
  it('quantil interpola', () => {
    expect(quantil([1, 2, 3, 4, 5], 0.5)).toBe(3);
    expect(quantil([0, 10], 0.1)).toBeCloseTo(1);
  });
  it('somarMeses atravessa o ano', () => {
    expect(somarMeses('2026-11', 3)).toBe('2027-02');
    expect(somarMeses('2026-01', -12)).toBe('2025-01');
  });
  it('regressão: reta perfeita tem R² 1', () => {
    const r = regressao([10, 20, 30, 40])!;
    expect(r.inclinacao).toBeCloseTo(10); expect(r.r2).toBeCloseTo(1);
  });
});

describe('mesesFechados', () => {
  it('exclui o mês corrente e preenche mês sem venda com zero', () => {
    const d = [
      { dia: '2026-06-10', bruto: 100, vendas: 1 }, { dia: '2026-08-02', bruto: 50, vendas: 1 },
      { dia: '2026-09-01', bruto: 999, vendas: 9 },
    ];
    expect(mesesFechados(d, '2026-09-27')).toEqual([
      { chave: '2026-06', bruto: 100, vendas: 1 }, { chave: '2026-07', bruto: 0, vendas: 0 }, { chave: '2026-08', bruto: 50, vendas: 1 },
    ]);
  });
});

describe('previsão com faixa', () => {
  it('sazonal repete o mesmo mês do ano anterior corrigido pelo crescimento', () => {
    const h = [...Array(12).fill(100), ...Array(12).fill(200)];
    h[12] = 400; // jan do 2º ano
    const hist = [...h];
    // último 12 = 200s (com um 400 no início) vs 100s → crescimento travado em 2x
    expect(preverModelo('sazonal', hist, 1)).toBeCloseTo(400 * 2);
    expect(preverModelo('sazonal', hist.slice(0, 20), 1)).toBeNull();
  });
  it('série estável escolhe um modelo com erro ~0 e faixa estreita', () => {
    const p = preverComFaixa(meses(Array(30).fill(1000)), 0)!;
    expect(p.erro).toBeCloseTo(0);
    expect(p.meses).toHaveLength(3);
    expect(p.meses[0].chave).toBe('2026-07');
    expect(p.meses[0].conservador).toBeCloseTo(1000); expect(p.meses[0].otimista).toBeCloseTo(1000);
  });
  it('mês corrente = o que já entrou + o modelo só no que falta do mês', () => {
    const p = preverComFaixa(meses(Array(30).fill(1000)), 5000, 0.75)!;
    expect(p.meses[0].provavel).toBeCloseTo(5250);
    expect(p.meses[0].parcial).toBe(5000);
    expect(p.meses[1].conservador).toBeCloseTo(1000);
  });
  it('histórico curto não prevê', () => {
    expect(preverComFaixa(meses([1, 2, 3, 4, 5]), 0)).toBeNull();
  });
  it('série com picos alarga a faixa', () => {
    const v = Array.from({ length: 30 }, (_, i) => (i % 5 === 0 ? 5000 : 1000));
    const p = preverComFaixa(meses(v), 0)!;
    expect(p.meses[1].otimista).toBeGreaterThan(p.meses[1].conservador * 1.5);
  });
});

describe('dependência de eventos', () => {
  const dias = [
    { dia: '2026-09-01', bruto: 100 }, { dia: '2026-09-02', bruto: 100 }, { dia: '2026-09-03', bruto: 1000 },
    { dia: '2026-09-04', bruto: 1000 }, { dia: '2026-09-05', bruto: 0 },
  ];
  const acao = (x: Partial<FaturamentoAcao>): FaturamentoAcao => ({
    acao: 'A', canal: null, inicio: '2026-09-03', fim: '2026-09-04', dias: 2, vendas: 2, compradores: 2, bruto: 2000, liquido: 1800, ...x,
  });
  it('fração em ação, dia comum e vezes o dia comum', () => {
    const d = dependenciaEventos([{ dia: '2026-08-31', bruto: 7 }, ...dias], [acao({ inicio: '2026-09-01', fim: '2026-09-01', dias: 1, bruto: 100, acao: 'B' }), acao({})], '2026-09-05')!;
    expect(d.de).toBe('2026-09-01');
    expect(d.total).toBe(2200);
    expect(d.emAcao).toBeCloseTo(2100 / 2200);
    expect(d.diasEmAcao).toBeCloseTo(3 / 5);
    expect(d.diaComum).toBeCloseTo(50);
    expect(d.acoes[0].acao).toBe('A');
    expect(d.acoes[0].vezesDiaComum).toBeCloseTo(1000 / 50);
  });
  it('sem ação → null', () => {
    expect(dependenciaEventos(dias, [], '2026-09-05')).toBeNull();
  });
});

describe('crescimento real', () => {
  it('YoY, 12×12, tendência e ticket', () => {
    const hist = meses([...Array(12).fill(100), ...Array.from({ length: 12 }, (_, i) => 200 + i * 10)], '2024-09');
    const c = crescimentoReal(hist, [
      { dia: '2025-09-05', bruto: 50 }, { dia: '2025-09-20', bruto: 999 }, { dia: '2026-09-03', bruto: 80 },
    ], '2026-09-10');
    expect(c.yoy).toEqual({ chave: '2026-08', atual: 310, anterior: 100, pct: 210 });
    expect(c.doze!.pct).toBeCloseTo(((2400 + 660) - 1200) / 1200 * 100);
    expect(c.tendencia!.porMes).toBeCloseTo(10);
    expect(c.tendencia!.r2).toBeCloseTo(1);
    expect(c.mesAteHoje).toEqual({ atual: 80, anterior: 50, pct: 60, dia: 10 });
    expect(c.movel12).toHaveLength(13);
  });
});

describe('contratado', () => {
  it('agrupa fontes por mês', () => {
    const r = agruparContratado([
      { mes: '2026-10-01', fonte: 'parcelado', valor: 100, pessoas: 1, em_risco: 40 },
      { mes: '2026-10-01', fonte: 'assinatura', valor: 50, pessoas: 1, em_risco: 0 },
      { mes: '2026-09-01', fonte: 'parcelado', valor: 10, pessoas: 1, em_risco: 0 },
    ]);
    expect(r.map((m) => m.chave)).toEqual(['2026-09', '2026-10']);
    expect(r[1]).toMatchObject({ parcelado: 100, assinatura: 50, total: 150, emRisco: 40 });
  });
});
