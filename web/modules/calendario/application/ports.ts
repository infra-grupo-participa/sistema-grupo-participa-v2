// Port do calendário da empresa. O caso de uso depende só disto, nunca de Supabase direto.
import type { EventoCalendario } from '../domain/calendario';

export interface CalendarioRepository {
  /** Projetos ativos que tocam a janela [de, ate] + os ativos sem data. Lança erro se o banco recusar. */
  listarEventos(de: string, ate: string): Promise<EventoCalendario[]>;
}
