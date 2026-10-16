// Recorte da Jornada a partir dos dados da tela. Os nós de funil usam o período SEM o filtro de funil (o filtro
// só apaga os outros caminhos), mas com o filtro de canal; a cadeia comum (Lista em diante) usa os cadastros do
// funil escolhido. Usado pelo mapa e pela gaveta da etapa, para os dois mostrarem o mesmo número.
import { calcularJornada, type MapaMetricas } from '../domain/jornada';
import { filtrarDias, filtrarLinhas } from '../domain/metricas';
import type { DesempenhoDia, LinhaPerfil } from '../domain/tipos';
import type { DadosTela } from './contexto';

export interface DadosJornada { dias: DesempenhoDia[]; linhas: LinhaPerfil[]; metricas: MapaMetricas }

export function dadosJornada(d: DadosTela): DadosJornada {
  const dias = filtrarDias(d.diasPeriodoSemFiltro, d.idx, { funil: 'todos', canal: d.recorte.canal });
  const linhas = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', canal: d.recorte.canal }, d.idx);
  const metricas = calcularJornada({ dias, linhas, linhasDoFunil: d.linhas, idx: d.idx, config: d.config, agora: d.agora, mensageria: d.mensageria });
  return { dias, linhas, metricas };
}
