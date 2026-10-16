/** Fonte única das métricas usadas em cards, Histórico, Jornada e Páginas.
 * Cada resultado explicita numerador, denominador e recorte para o componente rotular a conta.
 */
import { investimentoCaptacao, type InvestimentoCaptacao } from './custo-captacao';
import { cardsGrupo } from './grupo';
import {
  connectRate as calcularConnectRate, conversaoPagina as calcularConversaoPagina, indexar,
  ehPago, gastoDe, ingressoGrupo as calcularIngressoJanela, ingressoGrupoGeral as calcularIngressoGeral,
  linhasCaptacao, mqlDoRecorte, pessoasUnicas, taxa,
  type FiltroBase, type IndiceTrafego, type Taxa,
} from './metricas';
import type { Campanha, DesempenhoDia, FiltroCanal, FiltroFunil, GrupoResumoBlack, LinhaPerfil, Periodo, TrafegoBlack, Valor } from './tipos';
import { campanhaNoFunil, ehPreCaptacao, linhaNoFunil } from './linha-black';
import { diaDe } from './recorte';
import { gastoDaParte, ratear } from './rateio';

export interface Numero { valor: Valor; num: Valor; den: Valor; recorte: string; nota: string | null }
const numero = (valor: Valor, num: Valor, den: Valor, recorte: string, nota: string | null = null): Numero => ({ valor, num, den, recorte, nota });
const taxaNumerica = (x: Taxa, recorte: string): Numero => numero(x.valor, x.num, x.den, recorte, x.nota);

/** Pessoas distintas por pessoa_id. */
export function leadsPessoas(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas no recorte'): Numero {
  return numero(pessoasUnicas(linhas), pessoasUnicas(linhas), null, recorte);
}

/** Contagem acumulada de pessoas únicas por data de primeiro cadastro, em uma só passagem. */
export function acumuladoLeadsPessoas(linhas: readonly LinhaPerfil[], dias: readonly string[]): number[] {
  const primeiroDia = new Map<string, string>();
  for (const linha of linhas) {
    const dia = diaDe(linha.criadoEm);
    const anterior = primeiroDia.get(linha.pessoaId);
    if (anterior === undefined || dia < anterior) primeiroDia.set(linha.pessoaId, dia);
  }
  const novasPorDia = new Map<string, number>();
  for (const dia of primeiroDia.values()) novasPorDia.set(dia, (novasPorDia.get(dia) ?? 0) + 1);
  const diasOrdenados = [...new Set(dias)].sort();
  const resultado = new Map<string, number>();
  const diasNovosOrdenados = [...novasPorDia.keys()].sort();
  let acumulado = 0;
  let i = 0;
  for (const dia of diasOrdenados) {
    while (i < diasNovosOrdenados.length && diasNovosOrdenados[i] <= dia) {
      acumulado += novasPorDia.get(diasNovosOrdenados[i]) ?? 0;
      i += 1;
    }
    resultado.set(dia, acumulado);
  }
  return dias.map((dia) => resultado.get(dia) ?? 0);
}

/** Pessoas únicas atribuídas a campanhas de captação (iscas, consultoria, C3 e remarketing da página); `captacao` torna o recorte explícito no ponto de uso. */
export function inscricoes(linhas: readonly LinhaPerfil[], opcoes: { captacao: true; idx: IndiceTrafego; filtro?: FiltroBase }): Numero {
  const elegiveis = linhasCaptacao(linhas, opcoes.idx, opcoes.filtro);
  const total = pessoasUnicas(elegiveis);
  return numero(total, total, null, 'pessoas únicas atribuídas a campanhas de captação no período');
}

/** Pessoas únicas pagas com campanha de captação elegível. Pagos sem campanha ficam fora. */
export function leadsDoTrafego(linhas: readonly LinhaPerfil[], idx: IndiceTrafego, filtro?: FiltroBase): Numero {
  const elegiveis = linhasCaptacao(linhas, idx, filtro);
  return leadsPagosUnicos(elegiveis, 'pessoas únicas pagas atribuídas a campanhas de captação no período');
}

/** Pagadores distintos de linhas atribuídas às campanhas selecionadas pelo chamador. */
export function leadsPagosUnicos(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas pagas atribuídas às campanhas do recorte'): Numero {
  const elegiveis = linhas.filter((linha) => ehPago(linha) && linha.campanhaId !== null);
  const total = pessoasUnicas(elegiveis);
  return numero(total, total, null, recorte);
}

/** Gasto de captação por campanha (dias_campanha; campanha mista por anúncio), com a cobertura e os zeros validados pela fonte. */
export function investimentoDeCaptacao(trafego: TrafegoBlack, periodo: Periodo, filtro?: FiltroBase): InvestimentoCaptacao {
  return investimentoCaptacao(trafego, periodo, filtro);
}

/** Gasto de uma campanha na fonte por campanha; a ausência de linha só vale zero com prova do banco. */
export function gastoCampanha(trafego: TrafegoBlack, campanhaId: string): Numero {
  const campanha = trafego.campanhas.find((c) => c.id === campanhaId);
  if (!campanha || ehPreCaptacao(campanha)) return numero(null, null, null, 'campanha fora do recorte de investimento');
  const linha = trafego.gastoCampanhas?.find((x) => x.campanhaId === campanhaId);
  if (linha) return numero(linha.gasto, linha.gasto, null, 'gasto da campanha, fonte dias_campanha');
  if (campanha.semEntregaComprovada === true) return numero(0, 0, null, 'sem entrega comprovada pelo coletor do Meta');
  return numero(null, null, null, 'sem linha de campanha e sem prova de coleta');
}

/** Gasto total por campanha (dias_campanha), todas as linhas menos a pré-captação (CPF01, ENTRESAFRA).
 * Campanha sem linha só vale zero quando a fonte confirma sem_entrega_comprovada. Campanha mista (`c2`) diante de
 * Consultoria ou Iscas entra com a parte do gasto da campanha proporcional aos anúncios do conjunto (rateio.ts).
 */
export function investimentoTrafego(trafego: TrafegoBlack, filtro: FiltroBase = { funil: 'todos', canal: 'todos' }): Numero {
  const idx = filtro.funil === 'consultoria' || filtro.funil === 'iscas' ? indexar(trafego) : null;
  const rateio = idx ? ratear(trafego.dias, trafego, idx) : null;
  const elegiveis: { c: TrafegoBlack['campanhas'][number]; divide: boolean }[] = [];
  for (const c of trafego.campanhas) {
    if (ehPreCaptacao(c)) continue;
    if (filtro.canal !== 'todos' && c.canal !== filtro.canal) continue;
    const r = campanhaNoFunil(filtro.funil, c);
    if (r === 'nao') continue;
    elegiveis.push({ c, divide: r === 'divide' });
  }
  const resultados = elegiveis.map(({ c, divide }) => {
    if (!divide || !idx || !rateio) return gastoCampanha(trafego, c.id);
    const g = gastoDaParte(rateio, idx, c.id, (l) => linhaNoFunil(filtro.funil, l));
    return numero(g, g, null, 'gasto da campanha dividido pelo gasto dos anúncios do conjunto');
  });
  const total = elegiveis.length === 0 ? 0
    : resultados.some((x) => x.valor === null) ? null
      : resultados.reduce((soma, x) => soma + x.valor!, 0);
  return numero(total, total, null, 'gasto de campanhas no período, fonte dias_campanha, sem pré-captação (CPF01 e ENTRESAFRA)');
}

/** CPL de captação: gasto de captação ÷ pessoas pagas e atribuídas às mesmas campanhas. */
export function cplCaptacao(investimento: Valor | Pick<InvestimentoCaptacao, 'total'>, leads: Numero): Numero {
  const gasto = typeof investimento === 'number' || investimento === null ? investimento : investimento.total;
  const resultado = taxa(gasto, leads.valor);
  return taxaNumerica(resultado, 'gasto de captação ÷ pessoas únicas pagas com campanha de captação');
}

/**
 * Recorte de uma linha do modal de um card de custo (CPL): funil e canal e, quando a linha é uma fase ou só o remarketing da
 * página, um predicado de campanha. O gasto do CPL sai das MESMAS campanhas que os leads da linha (soma sobre soma, mesmo
 * período, mesmo recorte); nunca o total do período inteiro sobre os leads de um pedaço.
 */
export interface RecorteGasto { funil?: FiltroFunil; canal?: FiltroCanal; campanha?: (c: Campanha) => boolean }

/** Investimento em captação das campanhas do recorte (mesmo predicado único, mesma cobertura: sem gasto medido de uma campanha, o total é null). */
export function investimentoDoRecorte(trafego: TrafegoBlack, periodo: Periodo, recorte: RecorteGasto): InvestimentoCaptacao {
  const base = recorte.campanha ? { ...trafego, campanhas: trafego.campanhas.filter(recorte.campanha) } : trafego;
  return investimentoCaptacao(base, periodo, { funil: recorte.funil ?? 'todos', canal: recorte.canal ?? 'todos' });
}

/**
 * Investimento em captação de um recorte do modal como VALOR do card: recorte sem campanha de captação (canal Google sem
 * campanha, fase Antecipação, Aquecimento, Remarketing) é "sem dado" (null), nunca R$ 0,00. Com campanha, o total do
 * investimento (null se faltar gasto de alguma).
 */
export function investimentoDoRecorteValor(trafego: TrafegoBlack, periodo: Periodo, recorte: RecorteGasto): Valor {
  const investimento = investimentoDoRecorte(trafego, periodo, recorte);
  return investimento.campanhasMetaTotal + investimento.campanhasGoogleTotal > 0 ? investimento.total : null;
}

/**
 * CPL de um recorte do modal (dias e cadastros JÁ filtrados pelo chamador). Com `recorte` (funil, canal ou fase), o gasto vem
 * das campanhas desse recorte, igual ao card principal quando o recorte é o da tela. Sem `recorte` (dia, criativo), o
 * recorte não é uma campanha inteira: o gasto é a soma dos anúncios de captação dos próprios dias recebidos. Recorte sem
 * campanha de captação ou sem dia de captação é "sem dado", nunca zero.
 */
export function cplDoRecorte(trafego: TrafegoBlack, periodo: Periodo, dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[],
  idx: IndiceTrafego, recorte?: RecorteGasto): Numero {
  if (!recorte) {
    const captacao = dias.filter((x) => idx.anuncioEhCaptacao(x.anuncioId));
    return cplCaptacao(captacao.length ? gastoDe(captacao) : null, leadsDoTrafego(linhas, idx));
  }
  return cplCaptacao(investimentoDoRecorteValor(trafego, periodo, recorte), leadsDoTrafego(linhas, idx, { funil: recorte.funil ?? 'todos', canal: recorte.canal ?? 'todos' }));
}

/** MQL pela regra do servidor: profissão do envio mais recente que contém profissão. */
export function mql(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas no recorte'): Numero {
  const r = mqlDoRecorte(linhas);
  return numero(r.valor, r.num, r.den, `Regra do servidor; ${recorte}`, r.nota);
}

/** % de MQL sobre pessoas únicas no mesmo recorte. */
export function taxaMql(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas no recorte'): Numero {
  const resultadoMql = mql(linhas, recorte);
  const denominador = leadsPessoas(linhas).valor;
  const resultado = taxa(resultadoMql.num, denominador);
  return taxaNumerica(resultado, `MQL pela regra do servidor ÷ pessoas únicas; ${recorte}`);
}

/** A mesma função para Connect rate em Visão, Histórico, Jornada e Páginas. */
export function connectRate(dias: readonly DesempenhoDia[], idx: IndiceTrafego): Numero {
  return taxaNumerica(calcularConnectRate(dias, idx), 'LPV ÷ cliques pareados de campanhas de captação no período');
}

/** A mesma função para conversão de página em Visão, Histórico, Jornada e Páginas. */
export function conversaoPagina(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego): Numero {
  return taxaNumerica(calcularConversaoPagina(dias, linhas, idx), 'pessoas únicas pagas dos anúncios com LPV ÷ LPV de campanhas de captação no período');
}

/** Ingresso MQL: valor consolidado pelo servidor, sobre MQL, nos grupos elegíveis. */
export function ingressoGrupoMql(grupo: GrupoResumoBlack): Numero {
  const r = cardsGrupo(grupo).geral;
  return taxaNumerica(r, 'pessoas únicas nos grupos de Advogados e Contadores ÷ MQL do recorte do servidor');
}

/** Ingresso geral: usa o total agregado da RPC sem cruzamento; recortes continuam calculados por perfil cruzado. */
export function ingressoGrupoGeral(linhas: readonly LinhaPerfil[], grupo?: GrupoResumoBlack | null): Numero {
  if (grupo?.recorte === null && grupo.ingressoGeral !== undefined) {
    const ingresso = grupo.ingressoGeral;
    if (ingresso === null) return numero(null, null, null, 'números únicos que entraram no grupo ÷ leads únicos');
    return numero(ingresso.pct === null ? null : ingresso.pct / 100,
      ingresso.numerosUnicosNoGrupo, ingresso.leadsUnicos,
      'números únicos que entraram no grupo ÷ leads únicos');
  }
  return taxaNumerica(calcularIngressoGeral(linhas), 'pessoas únicas que entraram em grupo ÷ pessoas únicas do recorte');
}

/** Ingresso por janela madura (2h, 12h, 24h ou 48h), calculado sobre pessoas únicas. */
export function ingressoGrupoJanela(linhas: readonly LinhaPerfil[], horas: number, agora: Date): Numero {
  return taxaNumerica(calcularIngressoJanela(linhas, horas, agora), `pessoas únicas com janela de ${horas}h fechada`);
}
