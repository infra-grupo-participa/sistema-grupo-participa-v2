import { describe, expect, it } from 'vitest';
import {
  descreverFonte, etapasFunil, formatarHistorico, indicadoresEdicao, investimentoTotal, metricaHistorico,
  ordenarEdicoes, periodoEdicao, picosAulas, razao, type EdicaoHistorico,
} from './historico';

// Valores de exemplo do contrato da RPC dados_historico_edicoes (pedido de 09/10/2026), já em reais.
const atm1: EdicaoHistorico = {
  chave: 'atm1', familia: 'seminario-atm', rotulo: 'ATM1 JUL/26', ordem: 1, dataInicio: null, dataFim: null,
  leads: 424, investTrafego: 0, investDisparo: 2039.93, grupo: 345, picoD1: 74, picoD2: 21, picoD3: null,
  vendas: 7, receitaLiquida: 9919.07, preCheckout: 26,
  fontes: { leads: 'debrief JUL', invest_disparo: 'mensageria JUL' }, provisorio: [],
};
const atm2: EdicaoHistorico = {
  chave: 'atm2', familia: 'seminario-atm', rotulo: 'ATM2 SET/26', ordem: 2, dataInicio: '2026-09-01', dataFim: '2026-09-03',
  leads: 911, investTrafego: 0, investDisparo: 2119.48, grupo: 743, picoD1: 127, picoD2: 62, picoD3: 40,
  vendas: 9, receitaLiquida: 12752.91, preCheckout: 33,
  fontes: { pico_d1: 'aba Comparecimento SET', vendas: 'Hotmart' }, provisorio: ['vendas'],
};
const sp = (s: string) => s.replace(/ /g, ' ');

describe('indicadores do histórico', () => {
  const i1 = indicadoresEdicao(atm1, null);
  const i2 = indicadoresEdicao(atm2, atm1);

  it('investimento total = tráfego + disparo', () => {
    expect(i1.investTotal).toBeCloseTo(2039.93, 2);
    expect(i2.investTotal).toBeCloseTo(2119.48, 2);
  });

  it('ROAS = receita líquida ÷ investimento total', () => {
    expect(formatarHistorico(i1.roas, 'multiplicador')).toBe('4,86x');
    expect(formatarHistorico(i2.roas, 'multiplicador')).toBe('6,02x');
  });

  it('CAC = investimento total ÷ vendas', () => {
    expect(sp(formatarHistorico(i1.cac, 'moeda'))).toBe('R$ 291,42');
    expect(sp(formatarHistorico(i2.cac, 'moeda'))).toBe('R$ 235,50');
  });

  it('CPL = investimento total ÷ leads', () => {
    expect(sp(formatarHistorico(i1.cpl, 'moeda'))).toBe('R$ 4,81');
    expect(sp(formatarHistorico(i2.cpl, 'moeda'))).toBe('R$ 2,33');
  });

  it('conversões sobre pré-checkout, grupo e leads', () => {
    expect(formatarHistorico(i1.conversaoPreCheckout, 'percentual')).toBe('26,9%');
    expect(formatarHistorico(i2.conversaoPreCheckout, 'percentual')).toBe('27,3%');
    expect(formatarHistorico(i1.conversaoGrupo, 'percentual')).toBe('2,0%');
    expect(formatarHistorico(i2.conversaoLeads, 'percentual')).toBe('1,0%');
  });

  it('taxa de ingresso no grupo = grupo ÷ leads', () => {
    expect(formatarHistorico(i1.taxaGrupo, 'percentual')).toBe('81,4%');
    expect(formatarHistorico(i2.taxaGrupo, 'percentual')).toBe('81,6%');
  });

  it('retenção dentro da própria edição', () => {
    expect(formatarHistorico(i1.retencaoD2, 'percentual')).toBe('28,4%');
    expect(formatarHistorico(i2.retencaoD2, 'percentual')).toBe('48,8%');
    expect(formatarHistorico(i2.retencaoD3, 'percentual')).toBe('64,5%');
    expect(i1.retencaoD3).toBeNull();
  });

  it('comparativo contra a mesma aula da edição anterior', () => {
    expect(formatarHistorico(i2.comparativoD1, 'percentual')).toBe('171,6%');
    expect(formatarHistorico(i2.comparativoD2, 'percentual')).toBe('295,2%');
    expect(i2.comparativoD3).toBeNull(); // ATM1 não teve dia 3
    expect(i1.comparativoD1).toBeNull(); // primeira edição não tem anterior
  });
});

describe('ausência de dado nunca vira zero', () => {
  it('divisão por zero ou nulo dá null e aparece como "—"', () => {
    expect(razao(7, 0)).toBeNull();
    expect(razao(null, 10)).toBeNull();
    expect(razao(10, null)).toBeNull();
    expect(formatarHistorico(null, 'moeda')).toBe('—');
  });

  it('investimento com parte desconhecida fica desconhecido', () => {
    expect(investimentoTotal({ investTrafego: null, investDisparo: 100 })).toBeNull();
    const semTrafego = indicadoresEdicao({ ...atm1, investTrafego: null }, null);
    expect(semTrafego.cac).toBeNull();
    expect(semTrafego.roas).toBeNull();
  });

  it('investimento zero dá ROAS "—", nunca infinito', () => {
    const i = indicadoresEdicao({ ...atm1, investDisparo: 0 }, null);
    expect(i.investTotal).toBe(0);
    expect(formatarHistorico(i.roas, 'multiplicador')).toBe('—');
    expect(sp(formatarHistorico(i.cac, 'moeda'))).toBe('R$ 0,00');
  });
});

describe('funil e picos', () => {
  it('funil leads → grupo → pico D1 → pré-checkout → vendas com passagem entre etapas', () => {
    const f = etapasFunil(atm2);
    expect(f.map((e) => e.id)).toEqual(['leads', 'grupo', 'pico_d1', 'pre_checkout', 'vendas']);
    expect(f[0].passagem).toBeNull();
    expect(formatarHistorico(f[1].passagem, 'percentual')).toBe('81,6%');
    expect(formatarHistorico(f[2].passagem, 'percentual')).toBe('17,1%');
    expect(formatarHistorico(f[3].passagem, 'percentual')).toBe('26,0%');
    expect(formatarHistorico(f[4].passagem, 'percentual')).toBe('27,3%');
  });

  it('dia 3 ausente aparece como nulo sem quebrar retenção e comparativo', () => {
    const p = picosAulas(atm1, null);
    expect(p[2]).toEqual({ dia: 3, campo: 'pico_d3', valor: null, retencao: null, comparativo: null });
  });
});

describe('ordem, período e fonte', () => {
  it('ordena pela ordem da RPC', () => {
    expect(ordenarEdicoes([atm2, atm1]).map((e) => e.chave)).toEqual(['atm1', 'atm2']);
  });

  it('formata o período da edição', () => {
    expect(periodoEdicao(atm2)).toBe('01/09/2026 a 03/09/2026');
    expect(periodoEdicao(atm1)).toBeNull();
  });

  it('tooltip traz a fonte exata e avisa provisório', () => {
    expect(descreverFonte(metricaHistorico('leads'), atm1, null)).toBe('Fonte: debrief JUL.');
    expect(descreverFonte(metricaHistorico('vendas'), atm2, atm1)).toContain('provisório');
    expect(descreverFonte(metricaHistorico('comparativo_d1'), atm2, atm1)).toContain('ATM2 SET/26: aba Comparecimento SET.');
    expect(descreverFonte(metricaHistorico('comparativo_d1'), atm1, null)).toContain('Sem edição anterior');
    expect(descreverFonte(metricaHistorico('invest_trafego'), atm1, null)).toBe('Fonte: fonte não informada pelo banco.');
  });
});
