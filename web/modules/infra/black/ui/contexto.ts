// O que o DashboardBlackClient entrega a cada aba: tudo já lido e recortado, para a aba só desenhar.
import type { FonteDadosBlack } from '../application/ports';
import type { IndiceTrafego } from '../domain/metricas';
import type {
  ConfigBlack, DesempenhoDia, LinhaPerfil, Marcos, MensageriaBlack, Pagina, Periodo, Recorte, TotalPeriodo, TrafegoBlack,
} from '../domain/tipos';

export type AlvoGaveta = { tipo: 'etapa'; id: string } | { tipo: 'criativo'; id: string };

export interface DadosTela {
  chave: string;
  fonte: FonteDadosBlack;
  config: ConfigBlack;
  agora: Date;
  recorte: Recorte;
  periodo: Periodo;
  /** Dias do período escolhido (AAAA-MM-DD). */
  diasPeriodo: string[];
  /** Catálogo (campanhas, conjuntos, anúncios, páginas) e os dias do INÍCIO do projeto até hoje. */
  trafego: TrafegoBlack;
  /** Alcance e frequência do período escolhido (não somam entre dias). */
  totaisPeriodo: TotalPeriodo[];
  idx: IndiceTrafego;
  paginas: ReadonlyMap<string, Pagina>;
  /** Desempenho do início até hoje, sem filtro (Histórico precisa do antes do período). */
  diasTodos: DesempenhoDia[];
  /** Desempenho do período, sem filtro de funil e canal (nós de funil da Jornada, sub-aba Por funil). */
  diasPeriodoSemFiltro: DesempenhoDia[];
  /** Desempenho do período, com funil e canal. */
  dias: DesempenhoDia[];
  /** Cadastros do início até agora, sem os de teste. */
  linhasTodas: LinhaPerfil[];
  linhasPeriodoSemFiltro: LinhaPerfil[];
  /** Cadastros do período, com funil e canal. */
  linhas: LinhaPerfil[];
  mensageria: MensageriaBlack | null;
  mensageriaSemDado: boolean;
  marcos: Marcos | null;
  /** Muda o recorte (e a URL). */
  irPara: (r: Partial<Recorte>) => void;
  abrirGaveta: (alvo: AlvoGaveta) => void;
}
