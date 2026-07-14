'use client';

// Camada de dados do Financeiro. Tudo passa por RPC SECURITY DEFINER porque o
// schema `cs` (sistema de ativação) não é exposto ao PostgREST — o guard de
// permissão vive dentro de cada função no Postgres.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { Acordo, ContaReceber, DiaFaturamento, Lancamento, Oferta, TurmaFin } from '../domain/types';

const db = () => createBrowserSupabase();

export async function loadFaturamento(turma: string | null): Promise<DiaFaturamento[]> {
  const { data, error } = await db().rpc('fn_fin_faturamento_diario', { p_turma: turma });
  logQueryError('loadFaturamento', error);
  return (data as DiaFaturamento[]) ?? [];
}

export async function loadTurmas(): Promise<TurmaFin[]> {
  const { data, error } = await db().rpc('fn_fin_turmas');
  logQueryError('loadTurmas', error);
  return (data as TurmaFin[]) ?? [];
}

export async function loadContas(turma: string | null): Promise<ContaReceber[]> {
  const { data, error } = await db().rpc('fn_fin_contas_receber', { p_turma: turma });
  logQueryError('loadContas', error);
  return (data as ContaReceber[]) ?? [];
}

export async function loadExtrato(compradorId: string): Promise<Lancamento[]> {
  const { data, error } = await db().rpc('fn_fin_extrato', { p_comprador_id: compradorId });
  logQueryError('loadExtrato', error);
  return (data as Lancamento[]) ?? [];
}

export async function loadOfertas(): Promise<Oferta[]> {
  const { data, error } = await db().rpc('fn_fin_ofertas');
  logQueryError('loadOfertas', error);
  return (data as Oferta[]) ?? [];
}

/**
 * Grava o acordo nas MESMAS colunas do card que a ativação lê. Sem tabela
 * paralela: o que o financeiro combina, o comercial enxerga na hora.
 */
export async function salvarAcordo(
  contatoHmId: string,
  a: Acordo,
): Promise<{ ok: boolean; msg?: string }> {
  const { data, error } = await db().rpc('fn_fin_salvar_acordo', {
    p_contato_hm_id: contatoHmId,
    p_vencimento: a.vencimento,
    p_acordo: a.acordo,
    p_meio: a.meio,
    p_forma: a.forma,
    p_parcelas: a.parcelas,
  });
  logQueryError('salvarAcordo', error);
  if (error) return { ok: false, msg: 'Não foi possível salvar o acordo.' };

  const r = data as { ok: boolean; erro?: string } | null;
  if (!r?.ok) {
    const msg = r?.erro === 'sem_permissao'
      ? 'Você não tem permissão para registrar acordos.'
      : 'Não foi possível salvar o acordo.';
    return { ok: false, msg };
  }
  return { ok: true, msg: 'Acordo registrado.' };
}
