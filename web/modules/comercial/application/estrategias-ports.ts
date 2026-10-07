// Contrato da tela Estratégias com a fonte de dados (migration 20261007150701). Separado de `ports.ts` de propósito:
// quem só pede estratégia (sem acesso ao CRM) usa só este contrato, e nada aqui chama RPC que exige o Comercial.
import type {
  AcessoEstrategias, Estrategia, FiltrosPublico, ModeloPublico, NovaSolicitacao, OpcoesFiltro, PreviaPublico, SituacaoEstrategia,
  TipoAcao,
} from '../domain/estrategias';
import type { ProdutoKey } from '../domain/types';
import type { Resultado } from './ports';

export interface ResultadoAcao extends Resultado {
  filaId?: string | null;
  funilId?: string | null;
  pessoas?: number;
}

export interface EstrategiasRepository {
  /** O que a pessoa pode: pedir (função comercial.solicitar_estrategia) e executar (gestor comercial). */
  acesso(): Promise<AcessoEstrategias>;
  /** Gestor: todos os pedidos. Solicitante: só os dele. Cada um com o placar da ação. */
  pedidos(): Promise<Estrategia[]>;
  /** Pedido com o histórico de situações. null = não existe ou a pessoa não vê. */
  pedido(id: string): Promise<Estrategia | null>;
  modelos(): Promise<ModeloPublico[]>;
  opcoes(): Promise<OpcoesFiltro>;
  /** Quantas pessoas batem e quem sai por quê. Amostra (mascarada) só para o gestor. */
  previa(filtros: FiltrosPublico): Promise<Resultado & { previa?: PreviaPublico }>;
  salvar(s: NovaSolicitacao): Promise<Resultado & { id?: string }>;
  /** Só o gestor. Recusa exige motivo. */
  mudarSituacao(id: string, situacao: SituacaoEstrategia, nota?: string | null): Promise<Resultado>;
  /** Só o gestor: cria a fila de recuperação ou o funil próprio com o público do pedido. */
  transformar(id: string, tipo: TipoAcao, linha?: ProdutoKey | null, filtros?: FiltrosPublico | null): Promise<ResultadoAcao>;
}
