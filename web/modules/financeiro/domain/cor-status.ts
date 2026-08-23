// Fonte única da cor de status do financeiro. Sem I/O, sem CSS, sem Badge —
// domain não conhece a camada de apresentação (ver ARCHITECTURE.md).
//
// Decisão do João, 2026-08-23 (vinculante, não reinterpretar):
//   verde    = quitado, em_pagamento            (pagamento confirmado / parcela iniciada)
//   azul     = sem_acordo, oferta_enviada, a_vencer, futuro, incalculavel  (em negociação)
//   amarelo  = vencido                          (vencido)
//   vermelho = cancelado, reembolsado, cancelamento_solicitado  (cancelado/reembolsado)
//
// `neutro` NÃO é estado alcançável por nenhum dos 11 status conhecidos — é
// fallback de status desconhecido vindo do banco (drift schema↔front). Um card
// neutro na tela é sinal de alarme, não uma 5ª cor de negócio.
import type { StatusFinanceiro } from './types';

export type CorStatus = 'verde' | 'azul' | 'amarelo' | 'vermelho' | 'neutro';

/** Mapa exaustivo: o Record<> força o compilador a travar se um status nascer sem cor. */
export const COR_POR_STATUS: Record<StatusFinanceiro, CorStatus> = {
  quitado: 'verde',
  em_pagamento: 'verde',

  sem_acordo: 'azul',
  oferta_enviada: 'azul',
  a_vencer: 'azul',
  futuro: 'azul',
  incalculavel: 'azul',

  vencido: 'amarelo',

  cancelado: 'vermelho',
  reembolsado: 'vermelho',
  cancelamento_solicitado: 'vermelho',
};

/** Cor de um status. `neutro` só sai daqui quando `s` não é um StatusFinanceiro conhecido. */
export function corStatus(s: string): CorStatus {
  return COR_POR_STATUS[s as StatusFinanceiro] ?? 'neutro';
}

/** Texto da legenda de cores. Copy de produto mora no domínio, igual a STATUS_META.label. */
export const ROTULO_COR: Record<CorStatus, string> = {
  verde: 'Pagamento confirmado ou parcela iniciada',
  azul: 'Em negociação',
  amarelo: 'Vencido',
  vermelho: 'Cancelado ou reembolsado',
  neutro: 'Sem classificação',
};
