'use client';

// Adapter Supabase do Comercial: único lugar que chama as funções public.pessoas_* e public.crm_* (migration 20261005o).
// As tabelas (schemas pessoas e crm) são fechadas; a trava (hoje só admin/dev) e a máscara de documento/contato moram
// em cada função, no banco.
// Modo de demonstração (só desenvolvimento): NEXT_PUBLIC_COMERCIAL_DEMO=1 em web/.env.local e `npm run dev`. Em produção
// (NODE_ENV=production) ele nunca liga, mesmo com a variável.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { ConfigCrm, Negocio, StatusNegocio } from '../domain/crm';
import type { Entrada } from '../domain/identidade';
import type { Ficha, ItemBusca, Resposta, RevisaoPendente } from '../domain/pessoas';
import * as demo from './demo';

export const MODO_DEMO = process.env.NEXT_PUBLIC_COMERCIAL_DEMO === '1' && process.env.NODE_ENV !== 'production';

const db = () => createBrowserSupabase();

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T | null> {
  const { data, error } = await db().rpc(nome, args);
  logQueryError(nome, error);
  return error ? null : (data as T);
}

const falha: Resposta = { ok: false, msg: 'Não foi possível salvar (erro de rede, sem acesso, ou a migration 20261005o ainda não foi aplicada).' };

export const carregarConfig = (): Promise<ConfigCrm | null> => (MODO_DEMO ? Promise.resolve(demo.demoConfig()) : rpc<ConfigCrm>('crm_config'));

export const listarNegocios = (pipeline: number, projeto: number | null, responsavel: string | null, status: StatusNegocio | null): Promise<Negocio[] | null> =>
  MODO_DEMO
    ? Promise.resolve(demo.demoListar(pipeline, projeto, responsavel, status))
    : rpc<Negocio[]>('crm_negocios_listar', { p_pipeline: pipeline, p_projeto: projeto, p_responsavel: responsavel, p_status: status });

export async function moverNegocio(id: string, etapa: number, motivo: number | null, motivoObs: string | null): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoMover(id, etapa, motivoObs || (motivo != null ? 'Motivo da lista' : null));
  return (await rpc<Resposta>('crm_negocio_mover', { p_negocio: id, p_etapa: etapa, p_motivo: motivo, p_motivo_obs: motivoObs })) ?? falha;
}

export interface EdicaoNegocio { responsavel_id?: string | null; proximo_passo?: string | null; proximo_passo_em?: string | null; projeto_id?: number | null }

export async function editarNegocio(id: string, p: EdicaoNegocio): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoEditar(id, p);
  return (await rpc<Resposta>('crm_negocio_editar', { p_negocio: id, p })) ?? falha;
}

export async function criarNegocio(p: { pipeline_id: number; pessoa_id: string } & EdicaoNegocio): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoCriar(p);
  return (await rpc<Resposta>('crm_negocio_criar', { p })) ?? falha;
}

export interface LinhaHistorico { quando: string; acao: string; de: string | null; para: string | null; por: string | null }
export const historicoNegocio = (id: string): Promise<LinhaHistorico[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoHistorico(id)) : rpc<LinhaHistorico[]>('crm_negocio_historico', { p_negocio: id });

export const buscarPessoas = (termo: string | null, projeto: number | null): Promise<ItemBusca[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoBuscar(termo, projeto)) : rpc<ItemBusca[]>('pessoas_buscar', { p_termo: termo, p_projeto: projeto });

export const carregarFicha = (id: string): Promise<Ficha | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoFicha(id)) : rpc<Ficha>('pessoas_ficha', { p_pessoa: id });

/** Cadastra (ou acha) a pessoa. Com aluno_id, só traz o aluno para a base (referência). */
export async function cadastrarPessoa(p: Entrada & { aluno_id?: string; projeto?: string | null }): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoCadastrar(p);
  return (await rpc<Resposta>('pessoas_cadastrar', { p })) ?? falha;
}

export const listarRevisoes = (): Promise<RevisaoPendente[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoRevisoes()) : rpc<RevisaoPendente[]>('pessoas_revisao_listar');

export async function decidirRevisao(id: number, decisao: 'mesma' | 'diferente', alvo: string | null): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoDecidir(id, decisao, alvo);
  return (await rpc<Resposta>('pessoas_revisao_decidir', { p_revisao: id, p_decisao: decisao, p_alvo: alvo })) ?? falha;
}
