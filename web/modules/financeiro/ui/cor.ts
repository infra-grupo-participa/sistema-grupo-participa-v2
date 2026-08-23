// Projeções de CorStatus para cada superfície de UI. Módulo .ts puro (sem
// React) — mapa de cor não pode morar em componente, senão vira mapa não
// testável (foi assim que os 5 mapas concorrentes divergiram sem ninguém
// perceber). Ver ARCHITECTURE.md: domain não conhece esta camada; esta
// camada não decide cor sozinha — só projeta a decisão de cor-status.ts.
//
// Toda superfície que precisa de cor de status IMPORTA daqui. Zero Record<>
// de cor nasce em CardBoard.tsx, FichaDrawer.tsx, Relatorios.tsx ou qualquer
// outro componente — se a projeção não existe, ela é derivada aqui, nunca
// reinventada no consumidor.
import type { Tone } from '@/shared/ui/components/Badge';
import { corStatus, type CorStatus } from '../domain/cor-status';

export type { Tone };

/** Classe .gp-card--* (globals.css) por cor de status. */
export const CLASSE_CARD: Record<CorStatus, string> = {
  verde: 'gp-card--verde',
  azul: 'gp-card--azul',
  amarelo: 'gp-card--amarelo',
  vermelho: 'gp-card--vermelho',
  neutro: 'gp-card--neutro',
};

/** Tom de Badge (shared/ui/components/Badge.tsx) por cor de status. */
export const TONE_BADGE: Record<CorStatus, Tone> = {
  verde: 'success',
  azul: 'info',
  amarelo: 'warning',
  vermelho: 'danger',
  neutro: 'neutral',
};

/** Tom de ProgressBar (shared/ui/components/Feedback.tsx) por cor de status. */
export const TONE_BARRA: Record<CorStatus, 'green' | 'info' | 'yellow' | 'red' | 'neutral'> = {
  verde: 'green',
  azul: 'info',
  amarelo: 'yellow',
  vermelho: 'red',
  neutro: 'neutral',
};

/** Var CSS crua por cor de status — para texto solto que não passa por Badge/ProgressBar/card. */
export const VAR_COR: Record<CorStatus, string> = {
  verde: 'var(--green)',
  azul: 'var(--info)',
  amarelo: 'var(--yellow)',
  vermelho: 'var(--red)',
  neutro: 'var(--border-strong)',
};

/** Assinatura preservada do antigo domain/financeiro.ts — corpo agora DERIVA
 *  de corStatus() + TONE_BADGE em vez de decidir por conta própria. É o que
 *  torna estruturalmente impossível card e ficha divergirem de novo. */
export function statusTone(s: string): Tone {
  return TONE_BADGE[corStatus(s)];
}

/** Status cru da Hotmart (fn_fin_compras_aluno, `PURCHASE_STATUS` do webhook)
 *  → rótulo pt-BR, para a ficha (FichaDrawer.tsx) não mostrar "APPROVED" cru
 *  na tela. Fallback: devolve o cru — nunca esconde um status que não está
 *  no dicionário. Não é o mesmo eixo de CorStatus (esse dicionário é só
 *  texto); a cor do chip continua vindo de CompraHistorico.pago/pendente/morto
 *  → TONE_BADGE, não daqui. */
const STATUS_COMPRA_LABEL: Record<string, string> = {
  APPROVED: 'Aprovada',
  // A Hotmart manda as duas grafias e o banco guarda as duas: em 23/08/2026,
  // `public.compras` tinha COMPLETE (164) e COMPLETED (171). Faltar uma delas
  // jogava ~10% das compras no fallback e a ficha exibia "COMPLETED" em inglês.
  COMPLETE: 'Concluída',
  COMPLETED: 'Concluída',
  STARTED: 'Iniciada',
  PRE_ORDER: 'Pré-venda',
  WAITING_PAYMENT: 'Aguardando pagamento',
  BILLET_PRINTED: 'Boleto emitido',
  PRINTED_BILLET: 'Boleto emitido',
  // Idem: a documentação usa CANCELLED (dois L), o banco grava CANCELED (um L).
  CANCELLED: 'Cancelada',
  CANCELED: 'Cancelada',
  REFUNDED: 'Reembolsada',
  PARTIALLY_REFUNDED: 'Reembolsada parcialmente',
  CHARGEBACK: 'Chargeback',
  EXPIRED: 'Expirada',
  DELAYED: 'Atrasada',
  PROTESTED: 'Contestada',
};

export function statusCompraLabel(s: string): string {
  return STATUS_COMPRA_LABEL[String(s ?? '').toUpperCase()] ?? s;
}
