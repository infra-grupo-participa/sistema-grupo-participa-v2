'use client';

// Adapter Supabase das Estratégias (migration 20261007150701). Só chama as RPCs crm_estrategia_*: nenhuma exige o
// Comercial, então funciona para quem só pede estratégia. Permissão mora no banco (guarda nas RPCs definer).
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { EstrategiasRepository, ResultadoAcao } from '../application/estrategias-ports';
import type { Resultado } from '../application/ports';
import type {
  AcessoEstrategias, Estrategia, FiltrosPublico, ModeloPublico, NovaSolicitacao, OpcoesFiltro, PreviaPublico, SituacaoEstrategia,
  TipoAcao,
} from '../domain/estrategias';
import { limparFiltros } from '../domain/estrategias';
import type { ProdutoKey } from '../domain/types';
import { mensagemErroRpc, type ErroRpc } from './mapeamento-supabase';
import { mapResultado } from './mapeamento-escrita';
import { argsSalvar, mapAcesso, mapEstrategia, mapEstrategias, mapModelos, mapOpcoes, mapPrevia } from './mapeamento-estrategias';

export class SupabaseEstrategiasRepository implements EstrategiasRepository {
  private cliente: ReturnType<typeof createBrowserSupabase> | null = null;

  private db() {
    if (!this.cliente) this.cliente = createBrowserSupabase();
    return this.cliente;
  }

  private async rpc(fn: string, args?: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.db().rpc(fn, args);
    if (error) {
      logQueryError(fn, error);
      throw new Error(mensagemErroRpc(fn, error as ErroRpc));
    }
    return data;
  }

  /** Escrita: erro de transporte vira {ok:false} com a mensagem (a tela mostra no aviso, não quebra). */
  private async escrita(fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
    const { data, error } = await this.db().rpc(fn, args);
    if (error) {
      logQueryError(fn, error);
      return { ok: false, msg: mensagemErroRpc(fn, error as ErroRpc) };
    }
    return (data ?? { ok: false, msg: 'Resposta vazia do banco.' }) as Record<string, unknown>;
  }

  async acesso(): Promise<AcessoEstrategias> {
    return mapAcesso(await this.rpc('crm_estrategia_acesso'));
  }

  async pedidos(): Promise<Estrategia[]> {
    return mapEstrategias(await this.rpc('crm_estrategias'));
  }

  async pedido(id: string): Promise<Estrategia | null> {
    const d = await this.rpc('crm_estrategia_detalhe', { p_id: id });
    return d === null ? null : mapEstrategia(d, 'crm_estrategia_detalhe');
  }

  async modelos(): Promise<ModeloPublico[]> {
    return mapModelos(await this.rpc('crm_estrategia_modelos'));
  }

  async opcoes(): Promise<OpcoesFiltro> {
    return mapOpcoes(await this.rpc('crm_estrategia_opcoes'));
  }

  async previa(filtros: FiltrosPublico): Promise<Resultado & { previa?: PreviaPublico }> {
    const d = await this.escrita('crm_estrategia_previa', { p_filtros: limparFiltros(filtros) });
    return mapPrevia(d);
  }

  async salvar(s: NovaSolicitacao): Promise<Resultado & { id?: string }> {
    const d = await this.escrita('crm_estrategia_salvar', argsSalvar(s));
    return { ...mapResultado('crm_estrategia_salvar', d), id: typeof d.id === 'string' ? d.id : undefined };
  }

  async mudarSituacao(id: string, situacao: SituacaoEstrategia, nota?: string | null): Promise<Resultado> {
    return mapResultado('crm_estrategia_situacao', await this.escrita('crm_estrategia_situacao', { p_id: id, p_situacao: situacao, p_nota: nota ?? null }));
  }

  async transformar(id: string, tipo: TipoAcao, linha?: ProdutoKey | null, filtros?: FiltrosPublico | null): Promise<ResultadoAcao> {
    const d = await this.escrita('crm_estrategia_transformar', {
      p_id: id, p_tipo: tipo, p_linha: linha ?? null, p_filtros: filtros ? limparFiltros(filtros) : null,
    });
    return {
      ...mapResultado('crm_estrategia_transformar', d),
      filaId: typeof d.filaId === 'string' ? d.filaId : null,
      funilId: typeof d.funilId === 'string' ? d.funilId : null,
      pessoas: typeof d.pessoas === 'number' ? d.pessoas : undefined,
    };
  }
}
