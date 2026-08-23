// Domínio do board de cards do financeiro. Sem I/O.
//
// O financeiro não trabalha por etapa de venda (isso é o comercial): trabalha
// por "o que me impede de receber". O estágio comercial (estagio_nome) vira
// metadado exibido no card, nunca posição no board — um card em "Entrevista
// Finalizada" pode estar quitado ou devendo R$ 14.700, e a etapa comercial não
// diferencia os dois casos para quem cobra.
import type { ContaReceber, ReguaPasso } from './types';
import { contaMorta, saldoEfetivo } from './financeiro';
import { proximaAcao } from './cobranca';

// ── Urgência (escalar 0–3) ───────────────────────────────────────────────────
//
// Nenhum sinal isolado serve de gatilho:
//  - dias_atraso é null em 119 contas sem_acordo (o maior bolo do board);
//  - inadimplente é 0 em toda a base (não é fonte confiável);
//  - proximaAcao().atrasada é booleano e acenderia 82% do board (249 de 305
//    cards não têm vencimento) — vermelho generalizado no dia 1 não é sinal,
//    é ruído.
// Por isso a escala combina fatos: prazo estourado > prazo indefinido com
// dinheiro na mesa > nada pendente.
export function urgencia(conta: ContaReceber, regua: ReguaPasso[], hojeISO: string): 0 | 1 | 2 | 3 {
  if (contaMorta(conta) || conta.status_financeiro === 'quitado') return 0;
  const saldo = saldoEfetivo(conta);
  if (saldo <= 0) return 0;

  const diasAtraso = conta.dias_atraso ?? 0;
  const pediuCancelamento = conta.status_financeiro === 'cancelamento_solicitado' || conta.solicitou_cancelamento;

  if (diasAtraso > 30 || pediuCancelamento) return 3;

  // Saldo positivo sem prazo definido (sem_acordo / incalculável): a dor silenciosa —
  // ninguém está "atrasado" porque nunca houve data, mas o dinheiro segue parado.
  // Checa ANTES de proximaAcao().atrasada: sem vencimento, a régua também devolve
  // atrasada=true (tipo 'definir_acordo'/'calcular_valor'), e isso não é a mesma
  // urgência de um prazo que já passou — é a ausência do prazo.
  if (conta.status_financeiro === 'sem_acordo' || conta.status_financeiro === 'incalculavel') return 1;

  const acao = proximaAcao(conta, regua, hojeISO);
  if ((diasAtraso >= 1 && diasAtraso <= 30) || (acao.atrasada && saldo > 0)) return 2;

  return 0;
}

/**
 * Motivo textual da urgência — a mesma lógica de `urgencia()`, em prosa, para
 * canais que não podem depender só de cor (aria-label, title). Deliberadamente
 * ao lado de `urgencia()` no mesmo arquivo para as duas nunca divergirem.
 * Bijeção travada em teste: `motivoUrgencia(c) === null` sse `urgencia(c, ...) === 0`.
 */
export function motivoUrgencia(conta: ContaReceber, regua: ReguaPasso[], hojeISO: string): string | null {
  if (contaMorta(conta) || conta.status_financeiro === 'quitado') return null;
  const saldo = saldoEfetivo(conta);
  if (saldo <= 0) return null;

  const diasAtraso = conta.dias_atraso ?? 0;
  const pediuCancelamento = conta.status_financeiro === 'cancelamento_solicitado' || conta.solicitou_cancelamento;

  if (diasAtraso > 30) return `${diasAtraso} dias em atraso`;
  if (pediuCancelamento) return 'pediu cancelamento';

  if (conta.status_financeiro === 'sem_acordo' || conta.status_financeiro === 'incalculavel') {
    return 'sem prazo definido';
  }

  const acao = proximaAcao(conta, regua, hojeISO);
  if (diasAtraso >= 1 && diasAtraso <= 30) return `${diasAtraso} dias em atraso`;
  if (acao.atrasada && saldo > 0) return 'cobrança atrasada';

  return null;
}
