import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';
import type { AgendamentoRow } from '../domain/agendamento';

// Gateway de agendamento (público, service_role) — porta de hold-horario.php + confirm-horario.php.

const SOL_SELECT =
  'id,aluno_id,token,nome,email,status,step_index,auditoria_step,entrevista_data,entrevista_hora,agendamento_hold_data,agendamento_hold_hora,agendamento_hold_until';

export interface AgendaSolRow extends AgendamentoRow {
  id?: string;
  aluno_id?: string | null;
  nome?: string | null;
  email?: string | null;
}

export class SupabaseAgenda {
  private db: SupabaseClient;
  constructor(db?: SupabaseClient) {
    this.db = db ?? createAdminSupabase();
  }

  async loadByToken(token: string): Promise<AgendaSolRow | null> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select(SOL_SELECT)
      .eq('token', token)
      .limit(1)
      .maybeSingle();
    return (data as AgendaSolRow) ?? null;
  }

  async slotIsActive(date: string, hora: string): Promise<boolean> {
    const { data } = await this.db
      .from('thb_horarios_disponiveis')
      .select('id')
      .eq('slot_data', date)
      .eq('hora', hora)
      .eq('ativo', true)
      .limit(1)
      .maybeSingle();
    return Boolean(data);
  }

  /** Linhas que ocupam (entrevista) ou reservam (hold) algo na data. */
  async loadBusyRows(date: string): Promise<AgendaSolRow[]> {
    const { data } = await this.db
      .from('thb_placas_solicitacoes')
      .select(SOL_SELECT)
      .or(`entrevista_data.eq.${date},agendamento_hold_data.eq.${date}`);
    return (data as AgendaSolRow[]) ?? [];
  }

  async setHold(id: string, date: string, hora: string, holdUntilIso: string): Promise<boolean> {
    const { error } = await this.db
      .from('thb_placas_solicitacoes')
      .update({ agendamento_hold_data: date, agendamento_hold_hora: hora, agendamento_hold_until: holdUntilIso })
      .eq('id', id);
    return !error;
  }

  /** Confirma a entrevista: auditoria_step/step_index=2, status=docs_aprovados. */
  async confirm(
    id: string,
    fields: { entrevista_data: string; entrevista_hora: string; entrevista_link: string | null; meet_link: string | null },
  ): Promise<{ ok: boolean; conflict: boolean }> {
    const { error } = await this.db
      .from('thb_placas_solicitacoes')
      .update({ ...fields, auditoria_step: 2, step_index: 2, status: 'docs_aprovados' })
      .eq('id', id);
    // 23505 = índice único uq_entrevista_slot: outro candidato confirmou o mesmo slot
    // (garantia do banco para quando o slot-lock em memória não alcança — restart/multi-processo).
    return { ok: !error, conflict: error?.code === '23505' };
  }

  async syncAuditoriaStep(alunoId: string, step: number): Promise<void> {
    await this.db.from('thb_placas_auditoria').update({ step_index: step }).eq('aluno_id', alunoId);
  }

  async log(entry: {
    solicitacao_id?: string | null;
    aluno_id?: string | null;
    token?: string | null;
    origem: string;
    evento: string;
    status: string;
    detalhe?: string | null;
    slot_data?: string | null;
    slot_hora?: string | null;
    payload?: Record<string, unknown>;
  }): Promise<void> {
    await this.db.from('thb_placas_agendamento_logs').insert({ payload: {}, ...entry });
  }
}
