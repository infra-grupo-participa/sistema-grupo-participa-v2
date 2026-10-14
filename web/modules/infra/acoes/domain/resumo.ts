import { METRICAS_RESUMO_ATM, type DashboardAtm, type MetricaAtm } from '@/modules/infra/atm/domain/dashboard';

export type CardResumoAcaoBlack = {
  chave: string;
  rotulo: string;
  formato: 'inteiro' | 'percentual' | 'moeda' | 'multiplicador';
  metrica: MetricaAtm;
  aguardandoOferta: boolean;
};

const CAMPOS_AGUARDANDO_OFERTA = new Set(['vendas', 'cac', 'faturamentoBruto', 'faturamentoLiquido', 'roas']);

/** Mapeia os cards acordados com o contrato. CPL e investimento usam somente custo de disparo. */
export function cardsResumoAcaoBlack(dashboard: DashboardAtm | null, ofertaHotmart: string | null): CardResumoAcaoBlack[] {
  const cards: CardResumoAcaoBlack[] = [{
    chave: 'investimento',
    rotulo: 'Investimento com disparo',
    formato: 'moeda',
    metrica: dashboard?.resumo.custoDisparo ?? { valor: 0, semDado: true },
    aguardandoOferta: false,
  }];

  for (const metrica of METRICAS_RESUMO_ATM) {
    if (metrica.chave === 'custoDisparo') continue;
    const aguardandoOferta = ofertaHotmart === null && CAMPOS_AGUARDANDO_OFERTA.has(metrica.chave);
    cards.push({
      chave: metrica.chave,
      rotulo: metrica.chave === 'conversaoPreCheckout' ? 'Conversão do pré-checkout' : metrica.rotulo,
      formato: metrica.formato,
      metrica: dashboard?.resumo[metrica.chave] ?? { valor: 0, semDado: true },
      aguardandoOferta,
    });
  }
  return cards;
}
