'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { HmFilaItem, HmEtapa, TurmaThb } from '../domain/acesso-hm';

const db = () => createBrowserSupabase();

interface FilaRow {
  compra_id: string;
  aluno_id: string | null;
  comprador_id: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  offer_code: string | null;
  oferta_label: string | null;
  categoria: string | null;
  preco: number | null;
  data_compra: string | null;
  bucket: HmFilaItem['bucket'];
  ja_era_aluno_hm: boolean | null;
  sinal_quitado: boolean | null;
  needs_ativacao: boolean | null;
  turma_id: number | null;
  turma_codigo: string | null;
  ativado_em: string | null;
  ativado_por_nome: string | null;
  acesso_em: string | null;
  acesso_por_nome: string | null;
  ignorado_em: string | null;
  obs: string | null;
}

function mapRow(r: FilaRow): HmFilaItem {
  return {
    compraId: r.compra_id,
    alunoId: r.aluno_id,
    compradorId: r.comprador_id,
    nome: r.nome,
    email: r.email,
    telefone: r.telefone,
    offerCode: r.offer_code,
    ofertaLabel: r.oferta_label,
    categoria: r.categoria,
    preco: r.preco == null ? null : Number(r.preco),
    dataCompra: r.data_compra,
    bucket: r.bucket,
    jaEraAlunoHm: !!r.ja_era_aluno_hm,
    sinalQuitado: !!r.sinal_quitado,
    needsAtivacao: !!r.needs_ativacao,
    turmaId: r.turma_id == null ? null : Number(r.turma_id),
    turmaCodigo: r.turma_codigo,
    ativadoEm: r.ativado_em,
    ativadoPorNome: r.ativado_por_nome,
    acessoEm: r.acesso_em,
    acessoPorNome: r.acesso_por_nome,
    ignoradoEm: r.ignorado_em,
    obs: r.obs,
  };
}

/** Fila completa de Acesso HM (todos os buckets), via fn_hm_fila. */
export async function loadHmFila(): Promise<HmFilaItem[]> {
  const { data, error } = await db().rpc('fn_hm_fila');
  logQueryError('loadHmFila', error);
  return ((data as FilaRow[]) ?? []).map(mapRow);
}

/** Contagem leve por bucket (para o badge da aba), via fn_hm_fila_contagem. */
export async function loadHmContagem(): Promise<Record<string, number>> {
  const { data, error } = await db().rpc('fn_hm_fila_contagem');
  logQueryError('loadHmContagem', error);
  const out: Record<string, number> = {};
  for (const r of (data as { bucket: string; total: number }[]) ?? []) out[r.bucket] = Number(r.total);
  return out;
}

/** Turmas THB para o seletor / gestão (id, código, atual). */
export async function loadTurmasThb(): Promise<TurmaThb[]> {
  const { data, error } = await db().from('thb_turmas').select('id, codigo, atual').eq('tipo', 'thb').order('id', { ascending: false });
  logQueryError('loadTurmasThb', error);
  return (data as TurmaThb[]) ?? [];
}

type RpcResult = { ok: boolean; msg?: string };
async function rpc(fn: string, args: Record<string, unknown>): Promise<RpcResult> {
  const { error } = await db().rpc(fn, args);
  if (error) {
    logQueryError(fn, error);
    return { ok: false, msg: error.message };
  }
  return { ok: true };
}

/** Atribui turma ao aluno novo (grava em hm_liberacoes + write-back thb_alunos). */
export const setTurmaHm = (compraId: string, turmaId: number) =>
  rpc('fn_hm_set_turma', { p_compra_id: compraId, p_turma_id: turmaId });

/** Marca/desmarca uma etapa (ativacao | acesso). */
export const marcarEtapa = (compraId: string, etapa: HmEtapa, feito: boolean) =>
  rpc('fn_hm_marcar_etapa', { p_compra_id: compraId, p_etapa: etapa, p_feito: feito });

/** Ignora (ou desfaz) um item da fila. */
export const ignorarHm = (compraId: string, obs?: string, desfazer = false) =>
  rpc('fn_hm_ignorar', { p_compra_id: compraId, p_obs: obs ?? null, p_desfazer: desfazer });

/** Marca sinal como quitado manualmente (move de "Aguardando diferença" para Liberações). */
export const quitarManual = (compraId: string, feito = true) =>
  rpc('fn_hm_quitar_manual', { p_compra_id: compraId, p_feito: feito });

/** Define a turma THB atual (default do seletor de aluno novo). */
export const setTurmaAtual = (turmaId: number) => rpc('fn_turma_set_atual', { p_turma_id: turmaId });

/** Cria nova turma THB (opcionalmente já como atual). */
export const criarTurma = (codigo: string, atual = false) =>
  rpc('fn_turma_criar', { p_codigo: codigo, p_tipo: 'thb', p_atual: atual });
