'use client';

// Adapter Supabase do calendário: única chamada ao banco do módulo. mkt.projetos é fechado; a leitura passa por
// public.calendario_eventos (SECURITY DEFINER, guarda gp_eh_equipe(), só campos não sensíveis — migration 20261007134045).
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { normalizarEvento, type EventoCalendario } from '../domain/calendario';
import type { CalendarioRepository } from '../application/ports';

export class SupabaseCalendarioRepository implements CalendarioRepository {
  async listarEventos(de: string, ate: string): Promise<EventoCalendario[]> {
    const { data, error } = await createBrowserSupabase().rpc('calendario_eventos', { p_de: de, p_ate: ate });
    if (error) {
      logQueryError('calendario_eventos', error);
      throw new Error(error.message || 'Não foi possível carregar o calendário.');
    }
    return (Array.isArray(data) ? data : []).map(normalizarEvento).filter((e): e is EventoCalendario => e !== null);
  }
}
