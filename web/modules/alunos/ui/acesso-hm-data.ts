'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { HmFilaItem, HmBucket, HmAcao } from '../domain/acesso-hm';

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
  status_compra: string | null;
  bucket: HmBucket;
  ja_era_aluno_hm: boolean | null;
  sinal_quitado: boolean | null;
  baixa_acao: HmAcao | null;
  baixado_em: string | null;
  baixado_por_nome: string | null;
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
    baixaAcao: r.baixa_acao,
    baixadoEm: r.baixado_em,
    baixadoPorNome: r.baixado_por_nome,
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

/** Baixa manual (libera/renova/quita/ignora) — grava em hm_liberacoes via fn_hm_baixar. */
export async function baixarHm(compraId: string, acao: HmAcao, obs?: string): Promise<{ ok: boolean; msg?: string }> {
  const { error } = await db().rpc('fn_hm_baixar', { p_compra_id: compraId, p_acao: acao, p_obs: obs ?? null });
  if (error) {
    logQueryError('baixarHm', error);
    return { ok: false, msg: error.message };
  }
  return { ok: true };
}
