// Acesso do Laboratório: só as RPCs public.lab_* (schema lab é fechado). Roda no browser, com o JWT do usuário.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import type { Experimento, Pessoa, Res } from '../domain/types';

const sb = () => createBrowserSupabase();

async function rpc<T>(nome: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await sb().rpc(nome, args ?? {});
  if (error) throw new Error(error.code === '42501' ? 'Sem acesso ao Laboratório.' : error.message);
  return data as T;
}

const resposta = async (p: Promise<Res>): Promise<Res> => {
  try { return await p; } catch (e) { return { ok: false, msg: e instanceof Error ? e.message : 'Não foi possível.' }; }
};

export const labRepo = {
  listar: () => rpc<Experimento[]>('lab_listar'),
  obter: (id: string) => rpc<Experimento | null>('lab_obter', { p_id: id }),
  equipe: () => rpc<Pessoa[]>('lab_equipe'),
  salvar: (p: Record<string, unknown>) => resposta(rpc<Res>('lab_salvar', { p })),
  status: (id: string, status: 'rascunho' | 'no_ar' | 'cancelado', motivo?: string) =>
    resposta(rpc<Res>('lab_status', { p_id: id, p_status: status, p_motivo: motivo ?? null })),
  registrarLeitura: (p: Record<string, unknown>) => resposta(rpc<Res>('lab_registrar_leitura', { p })),
  revisar: (id: string, bateu: 'sim' | 'nao' | 'nao_sabe', aprendizado: string) =>
    resposta(rpc<Res>('lab_revisar', { p_id: id, p_bateu: bateu, p_aprendizado: aprendizado })),
  excluir: (id: string) => resposta(rpc<Res>('lab_excluir', { p_id: id })),
};
