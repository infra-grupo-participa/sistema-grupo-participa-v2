import { describe, expect, it } from 'vitest';
import { montarAvisosTesteAtm, rotuloValorResumoLead, type PeriodoAplicadoAtm } from './dashboard';

const base: PeriodoAplicadoAtm = { de: '2026-10-07', ate: '2026-10-14', leadsTeste: 0, grupoTeste: 0, vendasTeste: 0, receitaTesteBruta: 0 };

describe('avisos de registros excluídos por teste', () => {
  it('não cria aviso quando os contadores são zero ou nulos', () => {
    expect(montarAvisosTesteAtm(base)).toEqual([]);
    expect(montarAvisosTesteAtm({ ...base, leadsTeste: null, grupoTeste: null, vendasTeste: null })).toEqual([]);
  });

  it('avisa quantidade e faturamento de venda removida', () => {
    expect(montarAvisosTesteAtm({ ...base, vendasTeste: 1, receitaTesteBruta: 197 })).toEqual([
      { tipo: 'vendas', quantidade: 1, receitaBruta: 197 },
    ]);
  });

  it('lista os outros contadores positivos independentemente das vendas', () => {
    expect(montarAvisosTesteAtm({ ...base, leadsTeste: 2, grupoTeste: 1 })).toEqual([
      { tipo: 'leads', quantidade: 2 }, { tipo: 'grupo', quantidade: 1 },
    ]);
  });
});

describe('rótulos dos valores do resumo de leads', () => {
  it('mostra valores booleanos como Sim e Não', () => {
    expect(rotuloValorResumoLead(true)).toBe('Sim');
    expect(rotuloValorResumoLead(false)).toBe('Não');
  });

  it('preserva os rótulos de texto e o estado sem identificação', () => {
    expect(rotuloValorResumoLead('São Paulo')).toBe('São Paulo');
    expect(rotuloValorResumoLead(null)).toBe('Não identificado');
  });
});
