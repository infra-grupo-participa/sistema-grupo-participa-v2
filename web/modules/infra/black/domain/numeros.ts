/** Fonte única das métricas usadas em cards, Histórico, Jornada e Páginas.
 * Cada resultado explicita numerador, denominador e recorte para o componente rotular a conta.
 */
import { investimentoCaptacao, type InvestimentoCaptacao } from './custo-captacao';
import { cardsGrupo } from './grupo';
import {
  connectRate as calcularConnectRate, conversaoPagina as calcularConversaoPagina, ehEntresafraCampanha,
  ehPago, ingressoGrupo as calcularIngressoJanela, ingressoGrupoGeral as calcularIngressoGeral,
  linhasCaptacao, mqlDoRecorte, pessoasUnicas, taxa,
  type FiltroBase, type IndiceTrafego, type Taxa,
} from './metricas';
import type { DesempenhoDia, GrupoResumoBlack, LinhaPerfil, Periodo, TrafegoBlack, Valor } from './tipos';
import { diaDe } from './recorte';

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

/** Pessoas únicas atribuídas a campanhas C2/C3; `captacao` torna o recorte explícito no ponto de uso. */
export function inscricoes(linhas: readonly LinhaPerfil[], opcoes: { captacao: true; idx: IndiceTrafego; filtro?: FiltroBase }): Numero {
  const elegiveis = linhasCaptacao(linhas, opcoes.idx, opcoes.filtro);
  const total = pessoasUnicas(elegiveis);
  return numero(total, total, null, 'pessoas únicas atribuídas a C2/C3 no período');
}

/** Pessoas únicas pagas com campanha de captação elegível. Pagos sem campanha ficam fora. */
export function leadsDoTrafego(linhas: readonly LinhaPerfil[], idx: IndiceTrafego, filtro?: FiltroBase): Numero {
  const elegiveis = linhasCaptacao(linhas, idx, filtro);
  return leadsPagosUnicos(elegiveis, 'pessoas únicas pagas atribuídas a C2/C3 no período');
}

/** Pagadores distintos de linhas atribuídas às campanhas selecionadas pelo chamador. */
export function leadsPagosUnicos(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas pagas atribuídas às campanhas do recorte'): Numero {
  const elegiveis = linhas.filter((linha) => ehPago(linha) && linha.campanhaId !== null);
  const total = pessoasUnicas(elegiveis);
  return numero(total, total, null, recorte);
}

/** Gasto C2/C3 por campanha (dias_campanha), com a cobertura e os zeros validados pela fonte. */
export function investimentoDeCaptacao(trafego: TrafegoBlack, periodo: Periodo, filtro?: FiltroBase): InvestimentoCaptacao {
  return investimentoCaptacao(trafego, periodo, filtro);
}

/** Gasto de uma campanha na fonte por campanha; a ausência de linha só vale zero com prova do banco. */
export function gastoCampanha(trafego: TrafegoBlack, campanhaId: string): Numero {
  const campanha = trafego.campanhas.find((c) => c.id === campanhaId);
  if (!campanha || ehEntresafraCampanha(campanha)) return numero(null, null, null, 'campanha fora do recorte de investimento');
  const linha = trafego.gastoCampanhas?.find((x) => x.campanhaId === campanhaId);
  if (linha) return numero(linha.gasto, linha.gasto, null, 'gasto da campanha, fonte dias_campanha');
  if (campanha.semEntregaComprovada === true) return numero(0, 0, null, 'sem entrega comprovada pelo coletor do Meta');
  return numero(null, null, null, 'sem linha de campanha e sem prova de coleta');
}

/** Gasto total por campanha (dias_campanha), todas as etapas menos Entresafra.
 * Campanha sem linha só vale zero quando a fonte confirma sem_entrega_comprovada.
 */
export function investimentoTrafego(trafego: TrafegoBlack, filtro: FiltroBase = { funil: 'todos', canal: 'todos' }): Numero {
  const elegiveis = trafego.campanhas.filter((c) => {
    if (ehEntresafraCampanha(c)) return false;
    if (filtro.canal !== 'todos' && c.canal !== filtro.canal) return false;
    if (filtro.funil !== 'todos' && c.funil !== filtro.funil) return false;
    return true;
  });
  const resultados = elegiveis.map((c) => gastoCampanha(trafego, c.id));
  const total = elegiveis.length === 0 ? 0
    : resultados.some((x) => x.valor === null) ? null
      : resultados.reduce((soma, x) => soma + x.valor!, 0);
  return numero(total, total, null, 'gasto de campanhas no período, fonte dias_campanha, sem Entresafra');
}

/** CPL de captação: gasto C2/C3 ÷ pessoas pagas e atribuídas às mesmas campanhas. */
export function cplCaptacao(investimento: Valor | Pick<InvestimentoCaptacao, 'total'>, leads: Numero): Numero {
  const gasto = typeof investimento === 'number' || investimento === null ? investimento : investimento.total;
  const resultado = taxa(gasto, leads.valor);
  return taxaNumerica(resultado, 'gasto C2/C3 ÷ pessoas únicas pagas com campanha C2/C3 de captação');
}

/** MQL pela regra do servidor: profissão do envio mais recente que contém profissão. */
export function mql(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas no recorte'): Numero {
  const r = mqlDoRecorte(linhas);
  return numero(r.valor, r.num, r.den, `Regra do servidor; ${recorte}`, r.nota);
}

/** Potencial de MQL sobre pessoas únicas no mesmo recorte. */
export function potencialMql(linhas: readonly LinhaPerfil[], recorte = 'pessoas únicas no recorte'): Numero {
  const resultadoMql = mql(linhas, recorte);
  const denominador = leadsPessoas(linhas).valor;
  const resultado = taxa(resultadoMql.num, denominador);
  return taxaNumerica(resultado, `MQL pela regra do servidor ÷ pessoas únicas; ${recorte}`);
}

/** A mesma função para Connect rate em Visão, Histórico, Jornada e Páginas. */
export function connectRate(dias: readonly DesempenhoDia[], idx: IndiceTrafego): Numero {
  return taxaNumerica(calcularConnectRate(dias, idx), 'LPV ÷ cliques pareados de C2/C3 no período');
}

/** A mesma função para conversão de página em Visão, Histórico, Jornada e Páginas. */
export function conversaoPagina(dias: readonly DesempenhoDia[], linhas: readonly LinhaPerfil[], idx: IndiceTrafego): Numero {
  return taxaNumerica(calcularConversaoPagina(dias, linhas, idx), 'pessoas únicas pagas dos anúncios com LPV ÷ LPV de C2/C3 no período');
}

/** Ingresso MQL: valor consolidado pelo servidor, sobre MQL, nos grupos elegíveis. */
export function ingressoGrupoMql(grupo: GrupoResumoBlack): Numero {
  const r = cardsGrupo(grupo).geral;
  return taxaNumerica(r, 'pessoas únicas nos grupos de Advogados e Contadores ÷ MQL do recorte do servidor');
}

/** Ingresso geral: qualquer pessoa única do recorte que entrou em grupo ÷ todas as pessoas únicas. */
export function ingressoGrupoGeral(linhas: readonly LinhaPerfil[]): Numero {
  return taxaNumerica(calcularIngressoGeral(linhas), 'pessoas únicas que entraram em grupo ÷ pessoas únicas do recorte');
}

/** Ingresso por janela madura (2h, 12h, 24h ou 48h), calculado sobre pessoas únicas. */
export function ingressoGrupoJanela(linhas: readonly LinhaPerfil[], horas: number, agora: Date): Numero {
  return taxaNumerica(calcularIngressoJanela(linhas, horas, agora), `pessoas únicas com janela de ${horas}h fechada`);
}
