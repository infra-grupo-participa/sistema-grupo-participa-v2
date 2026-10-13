import { indexar } from './metricas';
import type { Periodo, TrafegoBlack, Valor } from './tipos';

export interface InvestimentoCaptacao {
  meta: Valor;
  google: Valor;
  total: Valor;
  /** Soma conhecida por canal; pode ser parcial quando a RPC não trouxe valor para todas as campanhas elegíveis. */
  metaMedido: Valor;
  googleMedido: Valor;
  campanhasMetaMedidas: number;
  campanhasGoogleMedidas: number;
  campanhasMetaTotal: number;
  campanhasGoogleTotal: number;
  campanhasMeta: string[];
  campanhasGoogle: string[];
  campanhasZeroConfirmado: string[];
  campanhasRemarketing: string[];
}

const ehRemarketing = (nome: string, fase: string | null) => fase === 'remarketing'
  || nome.toLocaleUpperCase('pt-BR').includes('REMARKETING');

function pertenceACaptacao(c: TrafegoBlack['campanhas'][number]): boolean {
  // Na fonte real, etapa vem do campo mkt_trafego.etapa_black. O fallback atende somente aos fixtures antigos.
  if (c.etapa === 'C2' || c.etapa === 'C3') return true;
  if (c.etapa !== undefined) return false;
  return c.funil === 'consultoria' || c.funil === 'iscas' || c.funil === 'c3';
}

/** Investimento de campanhas das etapas C2/C3, sem remarketing, separado por plataforma. */
export function investimentoCaptacao(trafego: TrafegoBlack, periodo: Periodo): InvestimentoCaptacao {
  const idx = indexar(trafego);
  const elegiveis: typeof trafego.campanhas = [];
  const remarketing: typeof trafego.campanhas = [];
  for (const campanha of trafego.campanhas) {
    if (!pertenceACaptacao(campanha)) continue;
    if (ehRemarketing(campanha.nome, campanha.fase)) { remarketing.push(campanha); continue; }
    elegiveis.push(campanha);
  }

  const gastoPorCampanha = new Map<string, number>();
  const medido = new Set<string>();
  if (trafego.gastoCampanhas !== undefined) {
    for (const linha of trafego.gastoCampanhas) {
      gastoPorCampanha.set(linha.campanhaId, linha.gasto);
      medido.add(linha.campanhaId);
    }
  } else {
    for (const dia of trafego.dias) {
      if (dia.dia < periodo.de || dia.dia > periodo.ate) continue;
      const campanha = idx.campanhaDoAnuncio(dia.anuncioId);
      if (!campanha) continue;
      gastoPorCampanha.set(campanha.id, (gastoPorCampanha.get(campanha.id) ?? 0) + dia.gasto);
      medido.add(campanha.id);
    }
  }

  const soma = (canal: 'meta' | 'google'): { valor: Valor; medido: Valor; medidas: number; total: number; nomes: string[] } => {
    const campanhas = elegiveis.filter((c) => c.canal === canal);
    const nomes = campanhas.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR'));
    const conhecidas = campanhas.filter((c) => medido.has(c.id) || c.gastoZeroConfirmado === true);
    for (const campanha of conhecidas) {
      if (!medido.has(campanha.id) && campanha.gastoZeroConfirmado) gastoPorCampanha.set(campanha.id, 0);
    }
    const subtotal = conhecidas.reduce((s, c) => s + (gastoPorCampanha.get(c.id) ?? 0), 0);
    const medidoConhecido = campanhas.length === 0 ? 0 : conhecidas.length > 0 ? subtotal : null;
    const valor = campanhas.length === 0 ? 0 : conhecidas.length !== campanhas.length ? null : subtotal;
    return { valor, medido: medidoConhecido, medidas: conhecidas.length, total: campanhas.length, nomes };
  };

  const meta = soma('meta'); const google = soma('google');
  // Canal sem campanha cadastrada é gasto zero. Campanha existente sem medida continua sem dado/parcial.
  const total = meta.valor !== null && google.valor !== null ? meta.valor + google.valor : null;
  return {
    meta: meta.valor, google: google.valor, total,
    metaMedido: meta.medido, googleMedido: google.medido,
    campanhasMetaMedidas: meta.medidas, campanhasGoogleMedidas: google.medidas,
    campanhasMetaTotal: meta.total, campanhasGoogleTotal: google.total,
    campanhasMeta: meta.nomes, campanhasGoogle: google.nomes,
    campanhasZeroConfirmado: elegiveis.filter((c) => c.gastoZeroConfirmado === true && gastoPorCampanha.get(c.id) === 0)
      .map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR')),
    campanhasRemarketing: remarketing.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR')),
  };
}
