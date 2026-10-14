import { describe, expect, it } from 'vitest';
import { dashboardAtmSemDado } from '@/modules/infra/atm/domain/dashboard';
import { cardsResumoAcaoBlack } from './resumo';

describe('cards do resumo Ações Black', () => {
  it('usa o custo de disparo no investimento da ação', () => {
    const dashboard = dashboardAtmSemDado('black-thb-2026-10');
    dashboard.resumo.custoDisparo = { valor: 321.45, semDado: false };
    dashboard.resumo.investimentoTotal = { valor: 999.99, semDado: false };
    const cards = cardsResumoAcaoBlack(dashboard, null);
    expect(cards[0]).toMatchObject({ rotulo: 'Investimento com disparo', metrica: { valor: 321.45, semDado: false } });
    expect(cards).toHaveLength(14);
    expect(cards.some((card) => card.chave === 'custoDisparo')).toBe(false);
  });

  it('marca vendas, CAC e receitas como aguardando oferta ausente', () => {
    const cards = cardsResumoAcaoBlack(dashboardAtmSemDado('black-thb-2026-10'), null);
    for (const chave of ['vendas', 'cac', 'faturamentoBruto', 'faturamentoLiquido', 'roas']) {
      expect(cards.find((card) => card.chave === chave)?.aguardandoOferta).toBe(true);
    }
  });

  it('não marca dados financeiros como aguardando oferta quando ela está configurada', () => {
    const cards = cardsResumoAcaoBlack(dashboardAtmSemDado('black-thb-2026-10'), 'oferta-configurada');
    expect(cards.find((card) => card.chave === 'vendas')?.aguardandoOferta).toBe(false);
  });
});
