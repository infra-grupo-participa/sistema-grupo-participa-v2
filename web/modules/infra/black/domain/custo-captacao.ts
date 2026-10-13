import { indexar } from './metricas';
import type { Periodo, TrafegoBlack, Valor } from './tipos';

export interface InvestimentoCaptacao {
  meta: Valor;
  google: Valor;
  total: Valor;
  campanhasMeta: string[];
  campanhasGoogle: string[];
  campanhasSemLead: string[];
  campanhasRemarketing: string[];
}

const temLead = (nome: string) => nome.toLocaleUpperCase('pt-BR').includes('LEAD');
const ehRemarketing = (nome: string, fase: string | null) => fase === 'remarketing'
  || nome.toLocaleUpperCase('pt-BR').includes('REMARKETING');

function pertenceACaptacao(c: TrafegoBlack['campanhas'][number]): boolean {
  // Na fonte real, etapa vem do campo mkt_trafego.etapa_black. O fallback atende somente aos fixtures antigos.
  if (c.etapa === 'C2' || c.etapa === 'C3') return true;
  if (c.etapa !== undefined) return false;
  return c.funil === 'consultoria' || c.funil === 'iscas' || c.funil === 'c3';
}

/** Investimento por campanhas com LEAD em C2/C3, separado por plataforma; sem gasto medido fica null. */
export function investimentoCaptacao(trafego: TrafegoBlack, periodo: Periodo): InvestimentoCaptacao {
  const idx = indexar(trafego);
  const elegiveis: typeof trafego.campanhas = [];
  const semLead: typeof trafego.campanhas = [];
  const remarketing: typeof trafego.campanhas = [];
  for (const campanha of trafego.campanhas) {
    if (!pertenceACaptacao(campanha)) continue;
    if (!temLead(campanha.nome)) { semLead.push(campanha); continue; }
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

  const soma = (canal: 'meta' | 'google'): { valor: Valor; nomes: string[] } => {
    const campanhas = elegiveis.filter((c) => c.canal === canal);
    const nomes = campanhas.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR'));
    if (nomes.length === 0 || campanhas.some((c) => !medido.has(c.id))) return { valor: null, nomes };
    const total = campanhas.reduce((s, c) => s + (gastoPorCampanha.get(c.id) ?? 0), 0);
    return { valor: total > 0 ? total : null, nomes };
  };

  const meta = soma('meta'); const google = soma('google');
  // A fonte real atual só entrega Meta. Canal ausente significa sem fonte, não gasto zero.
  const total = meta.valor !== null && google.valor !== null ? meta.valor + google.valor : null;
  return {
    meta: meta.valor, google: google.valor, total,
    campanhasMeta: meta.nomes, campanhasGoogle: google.nomes,
    campanhasSemLead: semLead.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR')),
    campanhasRemarketing: remarketing.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR')),
  };
}
