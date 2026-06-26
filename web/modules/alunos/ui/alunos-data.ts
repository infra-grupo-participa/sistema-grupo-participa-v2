'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import type { Aluno360 } from '../domain/aluno-360';

const db = () => createBrowserSupabase();

export interface Turma {
  id: number;
  codigo: string;
  tipo: string | null;
}

/** Carrega todos os alunos via fn_aluno_360_safe (paginado, igual ao legado PAGE=1000). */
export async function loadAlunos360(): Promise<Aluno360[]> {
  const PAGE = 1000;
  const supabase = db();
  const all: Aluno360[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await supabase.rpc('fn_aluno_360_safe').range(from, from + PAGE - 1);
    if (error || !data || !data.length) break;
    all.push(...(data as Aluno360[]));
    if (data.length < PAGE) break;
    from += PAGE;
  }
  return all;
}

export async function loadTurmas(): Promise<Turma[]> {
  const { data } = await db().from('thb_turmas').select('id, codigo, tipo').order('id');
  return (data as Turma[]) ?? [];
}

/** Write-back em thb_alunos (RLS exige admin ativo). Porta de saveAlunoEdit. */
export async function updateAluno(id: string, fields: Record<string, unknown>): Promise<{ ok: boolean; msg?: string }> {
  const { error } = await db()
    .from('thb_alunos')
    .update({ ...fields, atualizado_em: new Date().toISOString() })
    .eq('id', id);
  return error ? { ok: false, msg: error.message } : { ok: true };
}
