'use client';

// Camada de dados do Financeiro. Tudo passa por RPC SECURITY DEFINER porque o
// schema `cs` (sistema de ativação) não é exposto ao PostgREST — o guard de
// permissão vive dentro de cada função no Postgres.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type {
  Acordo, Cobranca, ContaReceber, DiaFaturamento, Lancamento, Meta, Oferta, ReguaPasso, TurmaFin,
} from '../domain/types';

const db = () => createBrowserSupabase();

export async function loadMetas(): Promise<Meta[]> {
  const { data, error } = await db().rpc('fn_fin_metas');
  logQueryError('loadMetas', error);
  return (data as Meta[]) ?? [];
}

export async function salvarMeta(m: Meta): Promise<{ ok: boolean; msg?: string }> {
  const { data, error } = await db().rpc('fn_fin_meta_salvar', {
    p_turma: m.turma,
    p_meta_arrecadacao: m.meta_arrecadacao,
    p_meta_cobertura_pct: m.meta_cobertura_pct,
    p_prazo_quitacao_dias: m.prazo_quitacao_dias,
    p_data_fechamento: m.data_fechamento,
    p_obs: m.obs,
  });
  logQueryError('salvarMeta', error);
  const r = data as { ok: boolean; erro?: string } | null;
  if (error || !r?.ok) return { ok: false, msg: r?.erro === 'sem_permissao' ? 'Sem permissão para editar metas.' : 'Não foi possível salvar a meta.' };
  return { ok: true, msg: 'Meta salva.' };
}

export async function loadRegua(): Promise<ReguaPasso[]> {
  const { data, error } = await db().rpc('fn_fin_regua');
  logQueryError('loadRegua', error);
  return (data as ReguaPasso[]) ?? [];
}

export async function salvarRegua(passos: ReguaPasso[]): Promise<{ ok: boolean; msg?: string }> {
  const payload = passos.map((p, i) => ({ ordem: i + 1, offset_dias: p.offset_dias, titulo: p.titulo, canal: p.canal, ativo: p.ativo }));
  const { data, error } = await db().rpc('fn_fin_regua_salvar', { p_passos: payload });
  logQueryError('salvarRegua', error);
  const r = data as { ok: boolean; erro?: string } | null;
  if (error || !r?.ok) return { ok: false, msg: r?.erro === 'sem_permissao' ? 'Sem permissão para editar a régua.' : 'Não foi possível salvar a régua.' };
  return { ok: true, msg: 'Régua salva.' };
}

export async function loadCobrancas(contatoHmId: string): Promise<Cobranca[]> {
  const { data, error } = await db().rpc('fn_fin_cobrancas', { p_contato_hm_id: contatoHmId });
  logQueryError('loadCobrancas', error);
  return (data as Cobranca[]) ?? [];
}

export async function registrarCobranca(
  contatoHmId: string, canal: string, resultado: string, obs: string | null,
): Promise<{ ok: boolean; msg?: string }> {
  const { data, error } = await db().rpc('fn_fin_cobranca_registrar', {
    p_contato_hm_id: contatoHmId, p_canal: canal, p_resultado: resultado, p_obs: obs,
  });
  logQueryError('registrarCobranca', error);
  const r = data as { ok: boolean; erro?: string } | null;
  if (error || !r?.ok) return { ok: false, msg: r?.erro === 'sem_permissao' ? 'Sem permissão para registrar cobrança.' : 'Não foi possível registrar.' };
  return { ok: true, msg: 'Cobrança registrada.' };
}

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
