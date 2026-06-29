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

export interface PlacaHistorico {
  solicitacao: {
    token: string | null;
    status: string | null;
    nivel: string | null;
    faturamento_declarado: number | null;
    auditoria_step: number | null;
    step_index: number | null;
    entrevista_data: string | null;
    entrevista_hora: string | null;
    codigo_rastreio: string | null;
    regularizacao_pendente: boolean | null;
    motivo_retorno: string | null;
    created_at: string | null;
    updated_at: string | null;
  } | null;
  auditoria: {
    step_index: number | null;
    encerrado: boolean | null;
    protocolo: string | null;
    faturamento: number | null;
    dates: Record<string, string> | null;
    obs: string | null;
  } | null;
}

/** Histórico de placas do aluno (solicitação pública + auditoria interna). */
export async function loadPlacaHistorico(alunoId: string, email: string | null): Promise<PlacaHistorico> {
  const supabase = db();
  const e = (email || '').trim().toLowerCase();
  const [solRes, audRes] = await Promise.all([
    supabase
      .from('thb_placas_solicitacoes')
      .select('token, status, nivel, faturamento_declarado, auditoria_step, step_index, entrevista_data, entrevista_hora, codigo_rastreio, regularizacao_pendente, motivo_retorno, created_at, updated_at')
      .or(`aluno_id.eq.${alunoId}${e ? `,email.ilike.${e}` : ''}`)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from('thb_placas_auditoria')
      .select('step_index, encerrado, protocolo, faturamento, dates, obs')
      .eq('aluno_id', alunoId)
      .maybeSingle(),
  ]);
  return {
    solicitacao: (solRes.data as PlacaHistorico['solicitacao']) ?? null,
    auditoria: (audRes.data as PlacaHistorico['auditoria']) ?? null,
  };
}

/** Write-back em thb_alunos (RLS exige admin ativo). Porta de saveAlunoEdit. */
export async function updateAluno(id: string, fields: Record<string, unknown>): Promise<{ ok: boolean; msg?: string }> {
  const { error } = await db()
    .from('thb_alunos')
    .update({ ...fields, atualizado_em: new Date().toISOString() })
    .eq('id', id);
  return error ? { ok: false, msg: error.message } : { ok: true };
}
