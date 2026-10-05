'use client';

// Adapter Supabase da base compartilhada do Marketing: único lugar que chama as funções public.mkt_* do banco.
// As tabelas (schema mkt) são fechadas; a trava (só admin/dev por ora) mora em cada função (mkt.pode_ver).
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { Pagina, Projeto } from '../domain/projetos';
import type { ErroCampanha } from '../domain/campanha';

const db = () => createBrowserSupabase();

export interface Resultado { ok: boolean; msg: string; id?: number }
const ERRO_REDE: Resultado = { ok: false, msg: 'Não foi possível salvar (erro de rede ou sem acesso). Tente de novo.' };

export async function listarProjetos(): Promise<Projeto[] | null> {
  const { data, error } = await db().rpc('mkt_projetos_listar');
  logQueryError('mkt_projetos_listar', error);
  return error ? null : ((data as Projeto[] | null) ?? []);
}

export async function listarPaginas(projetoId: number | null = null): Promise<Pagina[] | null> {
  const { data, error } = await db().rpc('mkt_paginas_listar', { p_projeto: projetoId });
  logQueryError('mkt_paginas_listar', error);
  return error ? null : ((data as Pagina[] | null) ?? []);
}

export type ProjetoForm = Omit<Projeto, 'id' | 'paginas'> & { id?: number };
export async function salvarProjeto(p: ProjetoForm): Promise<Resultado> {
  const { data, error } = await db().rpc('mkt_projeto_salvar', { p });
  logQueryError('mkt_projeto_salvar', error);
  return error ? ERRO_REDE : (data as Resultado);
}

export type PaginaForm = Omit<Pagina, 'id' | 'projeto_sigla' | 'url'> & { id?: number };
export async function salvarPagina(p: PaginaForm): Promise<Resultado> {
  const { data, error } = await db().rpc('mkt_pagina_salvar', { p });
  logQueryError('mkt_pagina_salvar', error);
  return error ? ERRO_REDE : (data as Resultado);
}

/** Tradução feita pelo banco (mkt.campanha_traduzir): mesma regra do domínio, com o cadastro de verdade. */
export interface TraducaoBanco {
  padrao: boolean;
  gestor: string | null;
  projeto: string | null;
  objetivo: string | null;
  descricao: string | null;
  pagina: string | null;
  projeto_id: number | null;
  pagina_id: number | null;
  erros: ErroCampanha[];
  avisos: string[];
  nome_canonico: string | null;
}
export async function traduzirNoBanco(nome: string): Promise<TraducaoBanco | null> {
  const { data, error } = await db().rpc('mkt_campanha_traduzir', { p_nome: nome });
  logQueryError('mkt_campanha_traduzir', error);
  return error ? null : (data as TraducaoBanco);
}
