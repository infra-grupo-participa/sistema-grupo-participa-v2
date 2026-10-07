// Caso de uso: carregar a janela de eventos em volta do mês aberto na home.
import { janelaCarga } from '../domain/calendario';
import type { EventoCalendario } from '../domain/calendario';
import type { CalendarioRepository } from './ports';

export interface CargaCalendario {
  janela: { de: string; ate: string };
  eventos: EventoCalendario[];
}

export async function carregarCalendario(repo: CalendarioRepository, ano: number, mes1a12: number): Promise<CargaCalendario> {
  const janela = janelaCarga(ano, mes1a12);
  const eventos = await repo.listarEventos(janela.de, janela.ate);
  return { janela, eventos };
}
