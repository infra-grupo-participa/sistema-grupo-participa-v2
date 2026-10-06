'use client';

// Adapter Supabase do Tráfego: único lugar que chama as funções public.trafego_* (migration 20261005p). As tabelas
// (schema mkt_trafego) são fechadas; a trava (hoje só admin/dev) mora em cada função (mkt.pode_ver('mkt_trafego')).
// Modo de demonstração (só desenvolvimento): NEXT_PUBLIC_TRAFEGO_DEMO=1 em web/.env.local e `npm run dev`. Em produção
// (NODE_ENV=production) ele nunca liga, mesmo com a variável.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { Campanha, ConfigTrafego, Conta, LinhaResumo, Resposta, VidaProjeto } from '../domain/tipos';
import * as demo from './demo';

export const MODO_DEMO = process.env.NEXT_PUBLIC_TRAFEGO_DEMO === '1' && process.env.NODE_ENV !== 'production';

const db = () => createBrowserSupabase();

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T | null> {
  const { data, error } = await db().rpc(nome, args);
  logQueryError(nome, error);
  return error ? null : (data as T);
}

const falha: Resposta = { ok: false, msg: 'Não foi possível salvar (erro de rede, sem acesso, ou a migration 20261005p ainda não foi aplicada).' };

export const carregarConfig = (): Promise<ConfigTrafego | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoConfig()) : rpc<ConfigTrafego>('trafego_config');

export const carregarResumo = (): Promise<LinhaResumo[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoResumo()) : rpc<LinhaResumo[]>('trafego_resumo');

export const carregarProjeto = (id: number): Promise<VidaProjeto | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoProjeto(id)) : rpc<VidaProjeto>('trafego_projeto', { p_projeto: id });

export const listarContas = (): Promise<Conta[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoContas()) : rpc<Conta[]>('trafego_contas_listar');

export const listarCampanhas = (projeto: number | null, semProjeto: boolean, foraPadrao: boolean): Promise<Campanha[] | null> =>
  MODO_DEMO
    ? Promise.resolve(demo.demoCampanhas(projeto, semProjeto, foraPadrao))
    : rpc<Campanha[]>('trafego_campanhas_listar', { p_projeto: projeto, p_sem_projeto: semProjeto, p_fora_padrao: foraPadrao });

export interface PlanejamentoForm {
  projeto_id: number; status: string; gestor: string; verba_maxima: string; verba_diaria: string;
  meta_leads: string; meta_receita: string; meta_cpl: string; meta_pct_mql: string; obs: string;
}
export async function salvarPlanejamento(p: PlanejamentoForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarPlanejamento({ ...p });
  return (await rpc<Resposta>('trafego_planejamento_salvar', { p })) ?? falha;
}

export interface FaseForm { id?: number; projeto_id: number; fase: string; verba: string; inicio: string; fim: string; obs: string }
export async function salvarFase(p: FaseForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarFase({ ...p });
  return (await rpc<Resposta>('trafego_fase_salvar', { p })) ?? falha;
}

export async function apagarFase(id: number): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoApagarFase(id);
  return (await rpc<Resposta>('trafego_fase_apagar', { p_fase: id })) ?? falha;
}

export interface ContaForm { id?: number; plataforma: string; conta_externa: string; nome: string; dono: string; cliente: string; moeda: string; ativa: boolean; obs: string }
export async function salvarConta(p: ContaForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarConta({ ...p });
  return (await rpc<Resposta>('trafego_conta_salvar', { p })) ?? falha;
}

/** projeto_id nulo = volta a valer o nome da campanha. */
export async function ajustarCampanha(p: { id: number; projeto_id: number | null; fase_id: number | null }): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoAjustarCampanha(p);
  return (await rpc<Resposta>('trafego_campanha_ajustar', { p })) ?? falha;
}

export async function relerCampanhas(): Promise<Resposta> {
  if (MODO_DEMO) return { ok: true, msg: 'Modo de demonstração: nada a reler.' };
  return (await rpc<Resposta>('trafego_campanhas_reler')) ?? falha;
}
