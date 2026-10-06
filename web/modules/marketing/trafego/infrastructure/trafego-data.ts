'use client';

// Adapter Supabase do Tráfego: único lugar que chama as funções public.trafego_* (migration 20261005p). As tabelas
// (schema mkt_trafego) são fechadas; a trava (hoje só admin/dev) mora em cada função (mkt.pode_ver('mkt_trafego')).
// Modo de demonstração (só desenvolvimento): NEXT_PUBLIC_TRAFEGO_DEMO=1 em web/.env.local e `npm run dev`. Em produção
// (NODE_ENV=production) ele nunca liga, mesmo com a variável.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { ListasCadastro, ProjetoCadastro, ProjetoForm } from '../domain/cadastro';
import type {
  Campanha, Checklist, ClickupProjeto, ConfigTrafego, Conta, LinhaResumo, ProdutoHotmart, ProdutoVisto, Resposta, ResumoDia, VidaProjeto,
} from '../domain/tipos';
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
  /** gestores: a lista inteira (substitui a anterior no banco). */
  projeto_id: number; status: string; gestores: string[]; verba_maxima: string; verba_diaria: string;
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

/**
 * Só o que vier é mexido. projeto_id: número = liga à mão; null = volta a valer o nome.
 * fase: código = correção à mão; null = volta a valer o objetivo do nome.
 */
export async function ajustarCampanha(p: { id: number; projeto_id?: number | null; fase?: string | null }): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoAjustarCampanha(p);
  return (await rpc<Resposta>('trafego_campanha_ajustar', { p })) ?? falha;
}

export async function relerCampanhas(): Promise<Resposta> {
  if (MODO_DEMO) return { ok: true, msg: 'Modo de demonstração: nada a reler.' };
  return (await rpc<Resposta>('trafego_campanhas_reler')) ?? falha;
}

// ─── Fase 2 (migration 20261005r) ─────────────────────────────────────────────────────────────────────────────────────
const falhaR: Resposta = { ok: false, msg: 'Não foi possível salvar (erro de rede, sem acesso, ou a migration 20261005r ainda não foi aplicada).' };

/** Resumo do dia ("o que está pegando fogo"). null = sem acesso ou a 20261005r não aplicada. */
export const carregarAlertas = (): Promise<ResumoDia | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoAlertas()) : rpc<ResumoDia>('trafego_alertas');

export const listarProdutos = (projeto: number): Promise<ProdutoHotmart[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoProdutos(projeto)) : rpc<ProdutoHotmart[]>('trafego_produtos_listar', { p_projeto: projeto });

export const listarProdutosVistos = (): Promise<ProdutoVisto[] | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoProdutosVistos()) : rpc<ProdutoVisto[]>('trafego_hotmart_produtos');

export interface ProdutoForm { id?: number; projeto_id: number; produto_id: string; oferta_codigo: string; de: string; ate: string; obs: string }
export async function salvarProduto(p: ProdutoForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarProduto({ ...p });
  return (await rpc<Resposta>('trafego_produto_salvar', { p })) ?? falhaR;
}

export async function apagarProduto(id: number): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoApagarProduto(id);
  return (await rpc<Resposta>('trafego_produto_apagar', { p_id: id })) ?? falhaR;
}

/** Atividades do ClickUp do projeto (espelho pela etiqueta). null = sem acesso ou a 20261005r não aplicada. */
export const carregarClickup = (projeto: number): Promise<ClickupProjeto | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoClickup(projeto)) : rpc<ClickupProjeto>('trafego_clickup', { p_projeto: projeto });

// ─── Cadastro do projeto, pacote e checklist (migration 20261006a) ────────────────────────────────────────────────────
const falhaA: Resposta = { ok: false, msg: 'Não foi possível salvar (erro de rede, sem acesso, ou a migration 20261006a ainda não foi aplicada).' };

/** Listas do cadastro (unidades, tipos de lançamento e regras, especialistas, UTM, pacote, etiquetas, checklist). null = sem a 20261006a. */
export const carregarListasCadastro = (): Promise<ListasCadastro | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoListasCadastro()) : rpc<ListasCadastro>('trafego_cadastro_listas');

export const carregarCadastro = (projeto: number): Promise<ProjetoCadastro | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoCadastro(projeto)) : rpc<ProjetoCadastro>('trafego_projeto_cadastro', { p_projeto: projeto });

export interface RespostaProjeto extends Resposta { tipo_lancamento?: string | null; campanhas_relidas?: number }
export async function salvarProjetoCadastro(f: ProjetoForm): Promise<RespostaProjeto> {
  const p = { ...f, sigla: f.sigla.trim().toUpperCase(), etiqueta_clickup: f.etiqueta_clickup.trim().toLowerCase(), especialista_nome: f.especialista_nome.trim() };
  if (MODO_DEMO) return demo.demoSalvarCadastro(p);
  return (await rpc<RespostaProjeto>('trafego_projeto_salvar', { p })) ?? falhaA;
}

export interface PacoteForm { id?: number; tipo_lancamento: string; fase: string; ordem: string; objetivos: string[]; pct_verba: string; dias: string; obs: string }
export async function salvarPacote(p: PacoteForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarPacote({ ...p });
  return (await rpc<Resposta>('trafego_pacote_salvar', { p })) ?? falhaA;
}
export async function apagarPacote(id: number): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoApagarPacote(id);
  return (await rpc<Resposta>('trafego_pacote_apagar', { p_id: id })) ?? falhaA;
}
export async function aplicarPacote(projeto: number): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoAplicarPacote(projeto);
  return (await rpc<Resposta>('trafego_pacote_aplicar', { p_projeto: projeto })) ?? falhaA;
}

export const carregarChecklist = (projeto: number): Promise<Checklist | null> =>
  MODO_DEMO ? Promise.resolve(demo.demoChecklist(projeto)) : rpc<Checklist>('trafego_checklist', { p_projeto: projeto });

export async function marcarChecklist(projeto: number, item: number, feito: boolean): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoMarcarChecklist(projeto, item, feito);
  return (await rpc<Resposta>('trafego_checklist_marcar', { p_projeto: projeto, p_item: item, p_feito: feito })) ?? falhaA;
}

export interface ItemChecklistForm { id?: number; texto: string; tipo_lancamento: string; ordem: string; ativo: boolean }
export async function salvarItemChecklist(p: ItemChecklistForm): Promise<Resposta> {
  if (MODO_DEMO) return demo.demoSalvarItemChecklist({ ...p });
  return (await rpc<Resposta>('trafego_checklist_item_salvar', { p })) ?? falhaA;
}
