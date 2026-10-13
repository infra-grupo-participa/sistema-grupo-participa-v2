import { indexar } from './metricas';
import type { Campanha, Periodo, TrafegoBlack, Valor } from './tipos';

export interface CustoCaptacaoBlack {
  c2: Valor;
  c3: Valor;
  total: Valor;
  campanhasC2: string[];
  campanhasC3: string[];
  campanhasSemLead: string[];
  campanhasRemarketing: string[];
}

function etapa(c: Campanha): 'C1' | 'C2' | 'C3' | null {
  if (c.etapa !== undefined) return c.etapa ?? null;
  // Os fixtures antigos carregam a classificação da fonte diretamente em `funil`.
  if (c.funil === 'c3') return 'C3';
  if (c.funil === 'consultoria' || c.funil === 'iscas') return 'C2';
  return null;
}

const temLead = (nome: string) => nome.toLocaleUpperCase('pt-BR').includes('LEAD');
const ehRemarketing = (c: Campanha) => c.fase === 'remarketing'
  || c.nome.split('|').some((bloco) => bloco.trim().toLocaleUpperCase('pt-BR') === 'REMARKETING');

function gastoDoGrupo(
  ids: ReadonlySet<string>,
  trafego: TrafegoBlack,
  periodo: Periodo,
): Valor {
  if (ids.size === 0) return null;
  let total = 0;
  let medido = false;
  if (trafego.gastoCampanhasPorDia !== undefined) {
    for (const x of trafego.gastoCampanhasPorDia) {
      if (ids.has(x.campanhaId) && x.dia >= periodo.de && x.dia <= periodo.ate) {
        total += x.gasto;
        medido = true;
      }
    }
  } else {
    // Compatibilidade com fixtures antigos sem dias por campanha. A produção usa `dias_campanha`.
    const idx = indexar(trafego);
    for (const x of trafego.dias) {
      if (x.dia < periodo.de || x.dia > periodo.ate) continue;
      const campanha = idx.campanhaDoAnuncio(x.anuncioId);
      if (campanha && ids.has(campanha.id)) { total += x.gasto; medido = true; }
    }
  }
  return medido && total > 0 ? total : null;
}

/** Custo apenas das campanhas LEAD de C2/C3. Etapa vem do banco (ou da classificação do fixture); remarketing sai. */
export function custoCaptacaoBlack(trafego: TrafegoBlack, periodo: Periodo): CustoCaptacaoBlack {
  const campanhasC2: Campanha[] = [];
  const campanhasC3: Campanha[] = [];
  const campanhasSemLead: Campanha[] = [];
  const campanhasRemarketing: Campanha[] = [];

  for (const c of trafego.campanhas) {
    const e = etapa(c);
    if (e !== 'C2' && e !== 'C3') continue;
    if (!temLead(c.nome)) { campanhasSemLead.push(c); continue; }
    if (ehRemarketing(c)) { campanhasRemarketing.push(c); continue; }
    (e === 'C2' ? campanhasC2 : campanhasC3).push(c);
  }

  const c2 = gastoDoGrupo(new Set(campanhasC2.map((c) => c.id)), trafego, periodo);
  const c3 = gastoDoGrupo(new Set(campanhasC3.map((c) => c.id)), trafego, periodo);
  const total = c2 !== null && c3 !== null ? c2 + c3 : null;
  const nomes = (cs: Campanha[]) => cs.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR'));
  return {
    c2, c3, total,
    campanhasC2: nomes(campanhasC2), campanhasC3: nomes(campanhasC3),
    campanhasSemLead: nomes(campanhasSemLead), campanhasRemarketing: nomes(campanhasRemarketing),
  };
}
