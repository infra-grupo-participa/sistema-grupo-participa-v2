'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';

const db = () => createBrowserSupabase();

export interface DepoimentoView {
  depoimento_id: string;
  aluno_id: string;
  aluno_nome: string | null;
  aluno_email: string | null;
  profissao_resolvida: string | null;
  aluno_cidade: string | null;
  aluno_estado: string | null;
  aluno_nivel_resultado: string | null;
  turma_codigo: string | null;
  testimonial_date: string | null;
  video_url: string | null;
  foto_url: string | null;
  social_handle: string | null;
  drive_folder_url: string | null;
  transcript: string | null;
  [k: string]: unknown;
}

export interface Depoimento {
  id: string;
  aluno_id: string;
  foto_url: string | null;
  social_handle: string | null;
  drive_folder_url: string | null;
  drive_folder_id: string | null;
  video_url: string | null;
  transcript: string | null;
  profissao: string | null;
  testimonial_date: string | null;
  highlights: Array<{ texto: string; tipo: string }> | null;
  objecao: string | null;
  antes_depois: { antes: string; depois: string } | null;
  gancho: string | null;
  resumo: string | null;
  highlights_status: string;
  highlights_processado_em: string | null;
  highlights_erro: string | null;
}

export interface Curso { id: string; name: string; slug: string; description: string | null; active: boolean; sort_order: number }
export interface Tag { id: string; label: string; color: string | null }

export async function loadDepoimentosView(): Promise<DepoimentoView[]> {
  const { data } = await db().from('vw_gp_depoimentos_alunos').select('*').order('testimonial_date', { ascending: false, nullsFirst: false });
  return (data as DepoimentoView[]) ?? [];
}

export async function loadDepoimento(id: string): Promise<Depoimento | null> {
  const { data } = await db().from('gp_depoimentos').select('*').eq('id', id).maybeSingle();
  return (data as Depoimento) ?? null;
}

export async function saveDepoimento(id: string, fields: Partial<Depoimento>): Promise<{ ok: boolean; msg?: string }> {
  const { error } = await db().from('gp_depoimentos').update(fields).eq('id', id);
  return error ? { ok: false, msg: error.message } : { ok: true };
}

export async function generateHighlights(id: string): Promise<{ ok: boolean; code?: string; mensagem?: string }> {
  const r = await fetch('/api/depoimentos/highlights', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ depoimento_id: id }),
  });
  const j = await r.json().catch(() => ({}));
  if (r.status === 429) return { ok: false, code: 'LIMITE_DIARIO', mensagem: j?.mensagem };
  return { ok: Boolean(j?.ok), mensagem: j?.error };
}

/** Depoimentos com highlights gerados (para a tela "Para Copy"). */
export async function loadParaCopy(): Promise<Array<Depoimento & { aluno_nome?: string }>> {
  const supabase = db();
  const { data } = await supabase
    .from('gp_depoimentos')
    .select('id, aluno_id, gancho, resumo, objecao, antes_depois, highlights, highlights_status, profissao')
    .eq('highlights_status', 'ok')
    .order('updated_at', { ascending: false });
  const deps = (data as Depoimento[]) ?? [];
  const ids = Array.from(new Set(deps.map((d) => d.aluno_id).filter(Boolean)));
  const nomes: Record<string, string> = {};
  if (ids.length) {
    const { data: alunos } = await supabase.from('thb_alunos').select('id, nome').in('id', ids);
    for (const a of (alunos as Array<{ id: string; nome: string }>) ?? []) nomes[a.id] = a.nome;
  }
  return deps.map((d) => ({ ...d, aluno_nome: nomes[d.aluno_id] }));
}

// ── Transcrição (fila → worker Python) ──
export interface TranscriptionJob {
  id: string;
  status: string;
  transcript: string | null;
  source_audios_count: number;
  audios_succeeded: number;
  audios_failed: number;
  error_message: string | null;
  processing_notes: string | null;
}

export async function enqueueTranscricao(folderUrl: string, ctx: Record<string, string> = {}): Promise<{ ok: boolean; job?: TranscriptionJob; error?: string }> {
  const r = await fetch('/api/depoimentos/transcricao-job', {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ folder_url: folderUrl, transcription_context: ctx }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return { ok: false, error: j?.error || 'Falha ao enfileirar.' };
  return { ok: true, job: j.data as TranscriptionJob };
}

export async function pollTranscricaoJob(jobId: string): Promise<TranscriptionJob | null> {
  const r = await fetch(`/api/depoimentos/transcricao-job?id=${encodeURIComponent(jobId)}`, { credentials: 'include' });
  if (!r.ok) return null;
  const j = await r.json().catch(() => ({}));
  return (j?.data as TranscriptionJob) ?? null;
}

// ── Cursos ──
export async function loadCursos(): Promise<Curso[]> {
  const { data } = await db().from('gp_cursos').select('*').order('sort_order').order('name');
  return (data as Curso[]) ?? [];
}
export async function saveCurso(c: Partial<Curso> & { id?: string }): Promise<boolean> {
  const supabase = db();
  if (c.id) {
    const { error } = await supabase.from('gp_cursos').update({ name: c.name, slug: c.slug, description: c.description, active: c.active, sort_order: c.sort_order }).eq('id', c.id);
    return !error;
  }
  const { error } = await supabase.from('gp_cursos').insert({ name: c.name, slug: c.slug, description: c.description ?? null, active: c.active ?? true, sort_order: c.sort_order ?? 0 });
  return !error;
}
export async function deleteCurso(id: string): Promise<boolean> {
  const { error } = await db().from('gp_cursos').delete().eq('id', id);
  return !error;
}

// ── Tags ──
export async function loadTags(): Promise<Tag[]> {
  const { data } = await db().from('gp_tags').select('*').order('label');
  return (data as Tag[]) ?? [];
}
export async function saveTag(t: Partial<Tag> & { id?: string }): Promise<boolean> {
  const supabase = db();
  if (t.id) {
    const { error } = await supabase.from('gp_tags').update({ label: t.label, color: t.color }).eq('id', t.id);
    return !error;
  }
  const { error } = await supabase.from('gp_tags').insert({ label: t.label, color: t.color ?? null });
  return !error;
}
export async function deleteTag(id: string): Promise<boolean> {
  const { error } = await db().from('gp_tags').delete().eq('id', id);
  return !error;
}
