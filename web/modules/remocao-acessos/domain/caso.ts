// Regras de apresentação do caso — puras, testáveis.
import type { Tone } from '@/shared/ui/components';
import type { CasoFila, StatusCaso, TipoCaso } from './types';

export const ROTULO_STATUS: Record<StatusCaso, string> = {
  alerta: 'Disputa (alerta)',
  aguardando_triagem: 'Aguardando triagem',
  em_remocao: 'Removendo acessos',
  mantem_acesso: 'Mantém acesso antigo',
  concluido: 'Concluído',
};

export const TOM_STATUS: Record<StatusCaso, Tone> = {
  alerta: 'info',
  aguardando_triagem: 'warning',
  em_remocao: 'accent',
  mantem_acesso: 'neutral',
  concluido: 'success',
};

export const ROTULO_TIPO: Record<TipoCaso, string> = {
  reembolso: 'Reembolso',
  chargeback: 'Chargeback',
  disputa: 'Disputa',
};

export const ABERTOS: StatusCaso[] = ['aguardando_triagem', 'em_remocao'];

export type SituacaoPrazo = 'sem_prazo' | 'no_prazo' | 'vence_hoje' | 'atrasado' | 'encerrado';

/** Situação do prazo de 1 dia útil. Caso encerrado não tem mais prazo correndo. */
export function situacaoPrazo(c: Pick<CasoFila, 'status' | 'prazo_em'>, agora: Date): SituacaoPrazo {
  if (!ABERTOS.includes(c.status)) return 'encerrado';
  if (!c.prazo_em) return 'sem_prazo';
  const prazo = new Date(c.prazo_em);
  if (Number.isNaN(prazo.getTime())) return 'sem_prazo';
  if (prazo.getTime() < agora.getTime()) return 'atrasado';
  const dia = (d: Date) => d.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
  return dia(prazo) === dia(agora) ? 'vence_hoje' : 'no_prazo';
}

export type Filtro = 'abertos' | 'meus' | 'alertas' | 'encerrados' | 'todos';

export function filtrarCasos(casos: CasoFila[], filtro: Filtro): CasoFila[] {
  switch (filtro) {
    case 'abertos': return casos.filter((c) => ABERTOS.includes(c.status));
    case 'meus': return casos.filter((c) => c.meus_pendentes > 0);
    case 'alertas': return casos.filter((c) => c.status === 'alerta');
    case 'encerrados': return casos.filter((c) => c.status === 'concluido' || c.status === 'mantem_acesso');
    default: return casos;
  }
}
