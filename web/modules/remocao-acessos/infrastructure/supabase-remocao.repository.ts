'use client';

// Adapter Supabase do módulo Remoção de Acessos: único lugar que chama .rpc().
// As tabelas ra_* são fechadas; a trava de permissão mora dentro de cada função
// no Postgres (ra_pode_ver / ra_eh_triador / responsável do item).
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { CasoDetalhe, CasoFila, ItemCatalogo, MeuPapel, Resultado, SituacaoItem } from '../domain/types';

const ERRO_REDE: Resultado = { ok: false, msg: 'Não foi possível salvar (erro de rede). Tente de novo.' };

export class SupabaseRemocaoRepository {
  private db() {
    return createBrowserSupabase();
  }

  async meuPapel(): Promise<MeuPapel> {
    const { data, error } = await this.db().rpc('ra_meu_papel');
    logQueryError('ra_meu_papel', error);
    if (error) throw new Error('Não foi possível carregar seu acesso.');
    return data as MeuPapel;
  }

  async fila(): Promise<CasoFila[]> {
    const { data, error } = await this.db().rpc('ra_fila');
    logQueryError('ra_fila', error);
    if (error) throw new Error('Não foi possível carregar os casos.');
    return (data as CasoFila[]) ?? [];
  }

  async caso(id: string): Promise<CasoDetalhe | null> {
    const { data, error } = await this.db().rpc('ra_caso', { p_caso: id });
    logQueryError('ra_caso', error);
    if (error) throw new Error('Não foi possível abrir o caso.');
    return (data as CasoDetalhe | null) ?? null;
  }

  async triar(id: string, decisao: 'manter' | 'remover', obs: string, programa: boolean): Promise<Resultado> {
    const { data, error } = await this.db().rpc('ra_triar', {
      p_caso: id, p_decisao: decisao, p_obs: obs || null, p_programa: programa,
    });
    logQueryError('ra_triar', error);
    if (error) return ERRO_REDE;
    return data as Resultado;
  }

  async marcarItem(itemId: string, situacao: SituacaoItem, obs: string | null): Promise<Resultado> {
    const { data, error } = await this.db().rpc('ra_marcar_item', { p_item: itemId, p_situacao: situacao, p_obs: obs });
    logQueryError('ra_marcar_item', error);
    if (error) return ERRO_REDE;
    return data as Resultado;
  }

  async apagarTeste(id: string): Promise<Resultado> {
    const { data, error } = await this.db().rpc('ra_apagar_teste', { p_caso: id });
    logQueryError('ra_apagar_teste', error);
    if (error) return ERRO_REDE;
    return data as Resultado;
  }

  async responsaveis(): Promise<ItemCatalogo[]> {
    const { data, error } = await this.db().rpc('ra_responsaveis');
    logQueryError('ra_responsaveis', error);
    if (error) throw new Error('Não foi possível carregar os responsáveis.');
    return (data as ItemCatalogo[]) ?? [];
  }

  async definirResponsavel(item: string, perfilId: string): Promise<Resultado> {
    const { data, error } = await this.db().rpc('ra_definir_responsavel', { p_item: item, p_perfil: perfilId });
    logQueryError('ra_definir_responsavel', error);
    if (error) return ERRO_REDE;
    return data as Resultado;
  }
}
