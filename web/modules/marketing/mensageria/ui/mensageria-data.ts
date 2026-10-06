'use client';

// Adapter Supabase da Mensageria: único lugar que chama as funções public.mkt_msg_* (contrato em
// infra/supabase/migrations/20261005n.explain.md). Cliente do usuário logado (sessão por cookie), nunca service_role.
// As tabelas (schema mkt_mensageria) são fechadas; a trava de acesso mora em cada função (mkt.pode_ver).
// Leitura: devolve null quando falha (rede ou sem acesso), separado de lista vazia.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import type {
  Ferramenta, ItemHistorico, LinhaPlanilha, ListaDisparos, Numero, Resultado, ResultadoImportacao,
} from '../domain/mensageria';

const db = () => createBrowserSupabase();

const ERRO_REDE: Resultado = { ok: false, msg: 'Não foi possível salvar (erro de rede ou sem acesso). Tente de novo.' };

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T | null> {
  const { data, error } = await db().rpc(nome, args);
  logQueryError(nome, error);
  return error ? null : (data as T);
}

export const listarProjetos = async () => rpc<Projeto[]>('mkt_projetos_listar');
export const listarFerramentas = async () => rpc<Ferramenta[]>('mkt_msg_ferramentas_listar');

export async function listarNumeros(): Promise<Numero[] | null> {
  const r = await rpc<{ ok: boolean; numeros: Numero[] }>('mkt_msg_numeros_listar');
  return r?.ok ? r.numeros : null;
}

export interface FiltroDisparos { de: string; ate: string; projeto: string | null; canal: string | null; ferramenta: number | null }
export async function listarDisparos(f: FiltroDisparos): Promise<ListaDisparos | null> {
  return rpc<ListaDisparos>('mkt_msg_disparos_listar', {
    p_de: f.de, p_ate: f.ate, p_projeto: f.projeto, p_canal: f.canal, p_ferramenta: f.ferramenta,
  });
}

/** Campos como o banco espera (valores numéricos crus: o banco valida e devolve a mensagem). */
export type DisparoForm = Record<string, string | number | null>;
export async function salvarDisparo(p: DisparoForm): Promise<Resultado> {
  return (await rpc<Resultado>('mkt_msg_disparo_salvar', { p })) ?? ERRO_REDE;
}

export async function arquivarDisparo(id: number, motivo: string): Promise<Resultado> {
  return (await rpc<Resultado>('mkt_msg_disparo_arquivar', { p_id: id, p_motivo: motivo })) ?? ERRO_REDE;
}

export interface Retorno { entregues: number | null; lidas: number | null; cliques: number | null; falhas: number | null; custo_centavos: number | null }
export async function lancarRetorno(id: number, r: Retorno): Promise<Resultado> {
  return (await rpc<Resultado>('mkt_msg_disparo_lancar_retorno', {
    p_id: id, p_entregues: r.entregues, p_lidas: r.lidas, p_cliques: r.cliques, p_falhas: r.falhas, p_custo_centavos: r.custo_centavos,
  })) ?? ERRO_REDE;
}

export async function importar(linhas: LinhaPlanilha[], confirmar: boolean, arquivo: string | null, aceitarDuplicadas: boolean): Promise<ResultadoImportacao | null> {
  return rpc<ResultadoImportacao>('mkt_msg_importar', {
    p_linhas: linhas, p_confirmar: confirmar, p_arquivo: arquivo, p_aceitar_duplicadas: aceitarDuplicadas,
  });
}

export type NumeroForm = Record<string, string | number | boolean | null>;
export async function salvarNumero(p: NumeroForm): Promise<Resultado> {
  return (await rpc<Resultado>('mkt_msg_numero_salvar', { p })) ?? ERRO_REDE;
}

export type FerramentaForm = Record<string, string | number | boolean | null>;
export async function salvarFerramenta(p: FerramentaForm): Promise<Resultado> {
  return (await rpc<Resultado>('mkt_msg_ferramenta_salvar', { p })) ?? ERRO_REDE;
}

export async function historico(tabela: 'disparos' | 'numeros' | 'ferramentas', id: number): Promise<{ ok: boolean; msg?: string; itens?: ItemHistorico[] } | null> {
  return rpc('mkt_msg_historico', { p_tabela: tabela, p_id: String(id) });
}
