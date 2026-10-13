import { describe, expect, it } from 'vitest';
import { dashboardAtmSemDado, METRICAS_RESUMO_ATM, metricaDoCardAtm, modalDoCardAtm, montarAvisosTesteAtm, rotuloListaOrigem, rotuloValorResumoLead, type PeriodoAplicadoAtm, type ResumoAtm } from './dashboard';

function resumoCom(parcial: Partial<ResumoAtm>): ResumoAtm {
  return { ...dashboardAtmSemDado('atm-fic').resumo, ...parcial };
}

describe('cards do funil', () => {
  it('não tem mais o card Custo com disparo e mantém pré-checkout, vendas e a taxa de conversão', () => {
    const chaves = METRICAS_RESUMO_ATM.map((m) => m.chave);
    expect(chaves).not.toContain('custoDisparo');
    expect(chaves).toEqual(['disparos', 'leads', 'ingressosGrupo', 'percentualIngressoGrupo', 'taxaEvasao', 'cpl', 'preCheckout', 'vendas', 'conversaoPreCheckout', 'cac', 'faturamentoBruto', 'faturamentoLiquido', 'roas']);
  });

  it('só leads, pré-checkout e vendas abrem modal', () => {
    expect(modalDoCardAtm('leads')).toBe('leads');
    expect(modalDoCardAtm('preCheckout')).toBe('preCheckout');
    expect(modalDoCardAtm('vendas')).toBe('vendas');
    expect(modalDoCardAtm('conversaoPreCheckout')).toBeNull();
    expect(modalDoCardAtm('cpl')).toBeNull();
  });
});

describe('metricaDoCardAtm', () => {
  it('resumo ainda não lido fica sem dado', () => {
    expect(metricaDoCardAtm(null, 'vendas')).toEqual({ valor: 0, semDado: true });
    expect(metricaDoCardAtm(undefined, 'preCheckout')).toEqual({ valor: 0, semDado: true });
  });

  it('zero devolvido pelo banco é zero medido, nulo é sem dado', () => {
    const r = resumoCom({ preCheckout: { valor: 1, semDado: false }, vendas: { valor: 0, semDado: false } });
    expect(metricaDoCardAtm(r, 'vendas')).toEqual({ valor: 0, semDado: false });
    expect(metricaDoCardAtm(r, 'preCheckout')).toEqual({ valor: 1, semDado: false });
    expect(metricaDoCardAtm(resumoCom({ vendas: { valor: 0, semDado: true } }), 'vendas')).toEqual({ valor: 0, semDado: true });
  });

  it('a taxa de conversão é a do banco, sem recálculo na tela', () => {
    const r = resumoCom({ preCheckout: { valor: 4, semDado: false }, vendas: { valor: 3, semDado: false }, conversaoPreCheckout: { valor: 50, semDado: false } });
    expect(metricaDoCardAtm(r, 'conversaoPreCheckout')).toEqual({ valor: 50, semDado: false });
    const zero = resumoCom({ preCheckout: { valor: 1, semDado: false }, conversaoPreCheckout: { valor: 0, semDado: false } });
    expect(metricaDoCardAtm(zero, 'conversaoPreCheckout')).toEqual({ valor: 0, semDado: false });
  });

  it('sem denominador (pré-checkout nulo ou zero) a taxa fica sem dado, nunca 0%', () => {
    expect(metricaDoCardAtm(resumoCom({ preCheckout: { valor: 0, semDado: false }, conversaoPreCheckout: { valor: 0, semDado: false } }), 'conversaoPreCheckout')).toEqual({ valor: 0, semDado: true });
    expect(metricaDoCardAtm(resumoCom({ preCheckout: { valor: 0, semDado: true }, conversaoPreCheckout: { valor: 10, semDado: false } }), 'conversaoPreCheckout')).toEqual({ valor: 0, semDado: true });
  });
});

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

describe('rótulo da lista de origem', () => {
  it('mostra descartado como Outros e mantém as demais origens', () => {
    expect(rotuloListaOrigem('descartado')).toBe('Outros');
    expect(rotuloListaOrigem('lista_1')).toBe('lista_1');
    expect(rotuloListaOrigem('fora_das_listas')).toBe('fora_das_listas');
    expect(rotuloListaOrigem(null)).toBeNull();
  });
});
