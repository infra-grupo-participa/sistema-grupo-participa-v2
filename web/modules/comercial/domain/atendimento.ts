// Status do atendimento da conversa (migration 20261009153515): aberto | em espera | encerrado.
// Em espera pausa o alerta de SLA; encerrada sai da fila de "esperando resposta" e dos contadores. Mensagem nova do
// contato reabre sozinha (trigger crm.tg_mensagem_reabre no banco). Regras puras.
import type { Conversa } from './types';

export type EstadoAtendimento = 'aberto' | 'espera' | 'encerrado';
export type FiltroAtendimento = EstadoAtendimento;

export const ROTULO_ATENDIMENTO: Record<EstadoAtendimento, string> = { aberto: 'Aberta', espera: 'Em espera', encerrado: 'Encerrada' };
export const ROTULO_FILTRO_ATENDIMENTO: Record<FiltroAtendimento, string> = { aberto: 'Abertas', espera: 'Em espera', encerrado: 'Encerradas' };

/** Estado da conversa (resposta antiga, sem o campo, conta como aberta). */
export function estadoAtendimento(cv: Pick<Conversa, 'atendimento'> | null | undefined): EstadoAtendimento {
  const e = cv?.atendimento;
  return e === 'espera' || e === 'encerrado' ? e : 'aberto';
}

/** Entra na fila de "esperando resposta", no SLA e nos contadores? Só a aberta. */
export function contaNaFila(cv: Pick<Conversa, 'atendimento'>): boolean {
  return estadoAtendimento(cv) === 'aberto';
}

/** Botões que a conversa oferece no estado atual (na ordem em que aparecem). */
export function proximosEstados(atual: EstadoAtendimento): EstadoAtendimento[] {
  if (atual === 'aberto') return ['espera', 'encerrado'];
  if (atual === 'espera') return ['aberto', 'encerrado'];
  return ['aberto'];
}

export const ROTULO_ACAO_ATENDIMENTO: Record<EstadoAtendimento, string> = {
  aberto: 'Reabrir', espera: 'Em espera', encerrado: 'Encerrar atendimento',
};

/** Contagem por estado para o filtro da lista. */
export function contarPorAtendimento(lista: readonly Pick<Conversa, 'atendimento'>[]): Record<EstadoAtendimento, number> {
  const n: Record<EstadoAtendimento, number> = { aberto: 0, espera: 0, encerrado: 0 };
  for (const cv of lista) n[estadoAtendimento(cv)] += 1;
  return n;
}
