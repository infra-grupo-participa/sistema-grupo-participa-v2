// Recorte da Jornada a partir dos dados da tela. Os nós de funil usam o período SEM o filtro de funil (o filtro
// só apaga os outros caminhos), mas com o filtro de canal; a cadeia comum (Lista em diante) usa os cadastros do
// funil escolhido. Usado pelo mapa e pela gaveta da etapa, para os dois mostrarem o mesmo número.
//
// A CAMPANHA é o dinheiro e o anúncio só divide (domain/rateio.ts): as métricas dos nós saem das linhas com o gasto já
// rateado, para o investimento dos nós fechar com o gasto da campanha. `dias` (devolvido para a lista de criativos da
// gaveta) continua por anúncio, como a aba Criativos: um criativo é um anúncio, não uma campanha.
import { calcularJornada, type MapaMetricas } from '../domain/jornada';
import { linhaDaCampanha } from '../domain/linha-black';
import { filtrarDias, filtrarLinhas } from '../domain/metricas';
import { ratear, semDetalheMista, somaSemDetalhe } from '../domain/rateio';
import type { DesempenhoDia, LinhaBlack, LinhaPerfil } from '../domain/tipos';
import type { DadosTela } from './contexto';

export interface DadosJornada {
  dias: DesempenhoDia[]; linhas: LinhaPerfil[]; metricas: MapaMetricas;
  /** Gasto da campanha mista (Consultoria + Iscas) sem anúncio no período: não pertence a nenhum nó, a tela mostra como nota. */
  semDetalheMista: number;
}

/** Linhas cujo nó recebe o gasto da campanha única sem linha de anúncio. */
const LINHAS_COM_NO: readonly LinhaBlack[] = ['consultoria', 'iscas', 'c3', 'remarketing_pagina'];

export function dadosJornada(d: DadosTela): DadosJornada {
  const canal = d.recorte.canal;
  const dias = filtrarDias(d.diasPeriodoSemFiltro, d.idx, { funil: 'todos', canal });
  const linhas = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', canal }, d.idx);
  const rateio = ratear(d.diasPeriodoSemFiltro, d.trafegoPeriodo, d.idx);
  const diasRateados = filtrarDias(rateio.dias, d.idx, { funil: 'todos', canal });
  const semDetalhe: Partial<Record<LinhaBlack, number>> = {};
  for (const l of LINHAS_COM_NO) {
    semDetalhe[l] = somaSemDetalhe(rateio, d.idx, (c) => linhaDaCampanha(c) === l && (canal === 'todos' || c.canal === canal));
  }
  const metricas = calcularJornada({ dias: diasRateados, linhas, linhasDoFunil: d.linhas, idx: d.idx, config: d.config, agora: d.agora, mensageria: d.mensageria, semDetalhe });
  return { dias, linhas, metricas, semDetalheMista: semDetalheMista(rateio, d.idx, canal) };
}
