'use client';

// Adapter Supabase da área Web: único lugar que chama as funções public.mkt_web_* (migration 20261005n). As tabelas
// (schema mkt_web) são fechadas; a trava (só admin/dev por ora) mora em cada função (mkt.pode_ver('mkt_web')).
// Modo de demonstração (só desenvolvimento): NEXT_PUBLIC_WEB_DEMO=1 em web/.env.local e `npm run dev`. Em produção
// (NODE_ENV=production) ele nunca liga, mesmo com a variável.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { Formulario, Funil, Instalacao, Leitura, LinhaPagina, Origem, Problemas, Velocidade, Visao } from '../domain/tipos';
import * as demo from './demo';

export const MODO_DEMO = process.env.NEXT_PUBLIC_WEB_DEMO === '1' && process.env.NODE_ENV !== 'production';

const db = () => createBrowserSupabase();

export interface ProjetoWeb { id: number; sigla: string; nome: string }
export interface PaginaWeb { id: number; projeto_id: number; codigo: string | null; nome: string; dominio: string; caminho: string; funcao: string }

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T | null> {
  const { data, error } = await db().rpc(nome, args);
  logQueryError(nome, error);
  return error ? null : (data as T);
}

export async function listarProjetos(): Promise<ProjetoWeb[] | null> {
  if (MODO_DEMO) return demo.DEMO_PROJETOS;
  return rpc<ProjetoWeb[]>('mkt_projetos_listar');
}

export async function listarPaginas(projeto: number): Promise<PaginaWeb[] | null> {
  if (MODO_DEMO) return demo.DEMO_PAGINAS.filter((p) => p.projeto_id === projeto);
  return rpc<PaginaWeb[]>('mkt_paginas_listar', { p_projeto: projeto });
}

const periodo = (projeto: number, de: string, ate: string) => ({ p_projeto: projeto, p_de: de, p_ate: ate });

export const carregar = {
  visao: (p: number, de: string, ate: string) => (MODO_DEMO ? Promise.resolve(demo.demoVisao(de, ate)) : rpc<Visao>('mkt_web_visao', periodo(p, de, ate))),
  paginas: (p: number, de: string, ate: string) => (MODO_DEMO ? Promise.resolve(demo.demoPaginas(de, ate)) : rpc<LinhaPagina[]>('mkt_web_paginas', periodo(p, de, ate))),
  funil: (p: number, de: string, ate: string) => (MODO_DEMO ? Promise.resolve(demo.demoFunil(de, ate)) : rpc<Funil[]>('mkt_web_funil', periodo(p, de, ate))),
  origem: (p: number, de: string, ate: string) => (MODO_DEMO ? Promise.resolve(demo.demoOrigem(de, ate)) : rpc<Origem>('mkt_web_origem', periodo(p, de, ate))),
  velocidade: (p: number, de: string, ate: string) => (MODO_DEMO ? Promise.resolve(demo.demoVelocidade(de, ate)) : rpc<Velocidade>('mkt_web_velocidade', periodo(p, de, ate))),
  leitura: (p: number, pagina: number, de: string, ate: string) =>
    (MODO_DEMO ? Promise.resolve(demo.demoLeitura()) : rpc<Leitura>('mkt_web_leitura', { ...periodo(p, de, ate), p_pagina: pagina })),
  problemas: (p: number, pagina: number | null, de: string, ate: string) =>
    (MODO_DEMO ? Promise.resolve(demo.demoProblemas()) : rpc<Problemas>('mkt_web_problemas', { ...periodo(p, de, ate), p_pagina: pagina })),
  formulario: (p: number, pagina: number, de: string, ate: string) =>
    (MODO_DEMO ? Promise.resolve(demo.demoFormulario()) : rpc<Formulario>('mkt_web_formulario', { ...periodo(p, de, ate), p_pagina: pagina })),
  instalacao: () => (MODO_DEMO ? Promise.resolve(demo.demoInstalacao()) : rpc<Instalacao>('mkt_web_instalacao')),
};

export async function ligarColeta(projeto: number, ligada: boolean): Promise<{ ok: boolean; msg: string }> {
  if (MODO_DEMO) return { ok: false, msg: 'Modo de demonstração: nada é gravado.' };
  const r = await rpc<{ ok: boolean; msg: string }>('mkt_web_coleta_ligar', { p_projeto: projeto, p_ligada: ligada });
  return r ?? { ok: false, msg: 'Não foi possível salvar (erro de rede ou sem acesso).' };
}
