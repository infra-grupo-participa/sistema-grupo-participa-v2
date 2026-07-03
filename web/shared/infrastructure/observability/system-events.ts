// Trilha de eventos técnicos em thb_system_events — alimenta a aba Admin Dev.
// Best-effort por design: observabilidade nunca pode derrubar o fluxo que observa.

import { createAdminSupabase } from '@/shared/infrastructure/supabase/admin-client';

export type SystemEventTipo = 'error' | 'warn' | 'info' | 'business';

export interface SystemEventInput {
  tipo: SystemEventTipo;
  /** Subsistema emissor (ex.: 'zoom', 'mailer', 'agenda_confirm'). */
  fonte: string;
  titulo: string;
  detalhe?: Record<string, unknown>;
  aluno_id?: string | null;
}

/** Corta corpos de resposta HTTP para o jsonb não inflar com HTML de erro. */
export function snippet(value: unknown, max = 400): string {
  const s = typeof value === 'string' ? value : JSON.stringify(value ?? '');
  return s.length > max ? `${s.slice(0, max)}…` : s;
}

export async function logSystemEvent(ev: SystemEventInput): Promise<void> {
  try {
    await createAdminSupabase().from('thb_system_events').insert({
      tipo: ev.tipo,
      fonte: ev.fonte,
      titulo: ev.titulo,
      detalhe: ev.detalhe ?? {},
      aluno_id: ev.aluno_id ?? null,
    });
  } catch {
    // Sem service key (dev) ou banco indisponível — segue sem trilha.
  }
}
