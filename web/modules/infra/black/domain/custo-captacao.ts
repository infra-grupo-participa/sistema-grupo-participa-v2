import { campanhaNoFunil, contaNoInvestimentoCaptacao as predicadoCaptacao, linhaNoFunil } from './linha-black';
import { indexar, type FiltroBase } from './metricas';
import { gastoDaParte, ratear } from './rateio';
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
  zerosMeta: { nome: string; coletaEm: string | null }[];
  zerosGoogle: { nome: string; coletaEm: string | null }[];
  semDadoMeta: { nome: string; motivo: string; coletaEm: string | null }[];
  semDadoGoogle: { nome: string; motivo: string; coletaEm: string | null }[];
  /** Dentro das campanhas somadas, as de remarketing da página (linha `remarketing_pagina`): entram na conta (Victor, 16/10/2026). */
  campanhasRemarketing: string[];
}

function coletaComprovaZero(c: TrafegoBlack['campanhas'][number]): boolean {
  // A RPC é a fonte de verdade para a prova de ausência de entrega; não reproduzir sua regra no cliente.
  return c.semEntregaComprovada === true;
}

/**
 * O PREDICADO ÚNICO do investimento em captação, o mesmo de todos os cards de captação (linha-black.ts): linha iscas,
 * consultoria, c2, c3 ou remarketing_pagina. Pré-captação (CPF01, ENTRESAFRA) fica fora. Exportado também para o
 * Histórico somar o dia com a mesma régua da Visão geral.
 */
export const contaNoInvestimentoCaptacao = predicadoCaptacao;

/** Investimento das campanhas de captação (linha do banco), com o remarketing da página, separado por plataforma. */
export function investimentoCaptacao(trafego: TrafegoBlack, _periodo: Periodo, filtro?: FiltroBase): InvestimentoCaptacao {
  // `trafego` já vem filtrado para o período solicitado pela camada de dados.
  void _periodo;
  const elegiveis: typeof trafego.campanhas = [];
  const remarketing: typeof trafego.campanhas = [];
  const divididas = new Set<string>();
  for (const campanha of trafego.campanhas) {
    if (!contaNoInvestimentoCaptacao(campanha)) continue;
    const noFiltro = filtro?.funil ? campanhaNoFunil(filtro.funil, campanha) : 'sim';
    if (noFiltro === 'nao') continue;
    if (filtro?.canal && filtro.canal !== 'todos' && campanha.canal !== filtro.canal) continue;
    if (noFiltro === 'divide') divididas.add(campanha.id);
    elegiveis.push(campanha);
    if (campanha.linha === 'remarketing_pagina' || (campanha.linha === undefined && campanha.fase === 'remarketing')) remarketing.push(campanha);
  }

  const gastoPorCampanha = new Map<string, number>();
  const medido = new Set<string>();
  for (const linha of trafego.gastoCampanhas ?? []) {
    gastoPorCampanha.set(linha.campanhaId, linha.gasto);
    medido.add(linha.campanhaId);
  }
  // Campanha `c2` (iscas + consultoria) diante de Consultoria ou Iscas: só o conjunto separa. O dinheiro continua sendo o da
  // campanha (dias_campanha); o gasto por anúncio só DIVIDE esse total entre Consultoria e Iscas (rateio.ts), então
  // Consultoria + Iscas = gasto da campanha ao centavo. Sem gasto por campanha na fonte, vale o gasto cru por anúncio.
  if (divididas.size > 0 && filtro?.funil) {
    const idx = indexar(trafego);
    const rateio = ratear(trafego.dias, trafego, idx);
    for (const id of divididas) {
      gastoPorCampanha.delete(id); medido.delete(id);
      const g = gastoDaParte(rateio, idx, id, (l) => linhaNoFunil(filtro.funil, l));
      if (g !== null) { gastoPorCampanha.set(id, g); medido.add(id); }
    }
  }

  // Só prova genérica fornecida pelo banco pode converter ausência de linha em zero.
  const zerosValidados = new Map<string, string | null>();
  for (const campanha of elegiveis) {
    if (!medido.has(campanha.id) && coletaComprovaZero(campanha)) {
      medido.add(campanha.id);
      gastoPorCampanha.set(campanha.id, 0);
      zerosValidados.set(campanha.id, campanha.coleta?.ultimaOkEm ?? null);
    }
  }

  const motivoSemDado = (c: typeof elegiveis[number]) => {
    if (divididas.has(c.id)) return 'a consultoria só se separa das iscas pelo anúncio, e não há gasto por anúncio no período';
    if (c.semEntregaComprovada === undefined) return 'metadados de coleta ainda não disponíveis na fonte';
    if (!c.primeiraVistaEm) return 'campanha ainda não vista pelo coletor';
    if (c.semEntregaComprovada && !coletaComprovaZero(c)) return 'fonte sem confirmação de ausência de entrega';
    switch (c.coleta?.estado) {
      case 'falha_recente': return 'última coleta da conta falhou';
      case 'velha': return 'coleta antiga';
      case 'sem_coleta': return 'conta sem coleta registrada';
      case 'atual': return 'coleta atual sem confirmação de ausência de entrega';
      default: return 'coleta sem confirmação';
    }
  };

  const soma = (canal: 'meta' | 'google'): { valor: Valor; medido: Valor; medidas: number; total: number; nomes: string[];
    zeros: { nome: string; coletaEm: string | null }[]; faltantes: { nome: string; motivo: string; coletaEm: string | null }[] } => {
    const campanhas = elegiveis.filter((c) => c.canal === canal);
    const nomes = campanhas.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR'));
    const conhecidas = campanhas.filter((c) => medido.has(c.id));
    const subtotal = conhecidas.reduce((s, c) => s + (gastoPorCampanha.get(c.id) ?? 0), 0);
    const medidoConhecido = campanhas.length === 0 ? 0 : conhecidas.length > 0 ? subtotal : null;
    const valor = campanhas.length === 0 ? 0 : conhecidas.length !== campanhas.length ? null : subtotal;
    return {
      valor, medido: medidoConhecido, medidas: conhecidas.length, total: campanhas.length, nomes,
      zeros: campanhas.filter((c) => zerosValidados.has(c.id)).map((c) => ({ nome: c.nome, coletaEm: zerosValidados.get(c.id) ?? null })),
      faltantes: campanhas.filter((c) => !medido.has(c.id)).map((c) => ({
        nome: c.nome, motivo: motivoSemDado(c),
        coletaEm: c.coleta?.estado === 'falha_recente' ? c.coleta.ultimaFalhaEm : c.coleta?.ultimaOkEm ?? null,
      })),
    };
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
    zerosMeta: meta.zeros, zerosGoogle: google.zeros, semDadoMeta: meta.faltantes, semDadoGoogle: google.faltantes,
    campanhasRemarketing: remarketing.map((c) => c.nome).sort((a, b) => a.localeCompare(b, 'pt-BR')),
  };
}
