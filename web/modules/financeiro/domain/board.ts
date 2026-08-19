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

// ── Faixas (colunas do board) ────────────────────────────────────────────────

export type FaixaChave =
  | 'sem_valor' | 'sem_acordo' | 'oferta_enviada' | 'em_cobranca' | 'risco_perda' | 'encerrado';

export interface FaixaMeta {
  chave: FaixaChave;
  rotulo: string;
  descricao: string;
}

/** As 6 faixas do board, na ordem de checagem (primeira que casar vence — igual ao CASE do banco). */
export const FAIXAS: FaixaMeta[] = [
  { chave: 'sem_valor', rotulo: 'Sem valor definido', descricao: 'Ainda não dá para calcular o que a pessoa deve.' },
  { chave: 'sem_acordo', rotulo: 'Sem acordo', descricao: 'Valor calculado, mas sem vencimento combinado.' },
  { chave: 'oferta_enviada', rotulo: 'Oferta enviada', descricao: 'Link de pagamento enviado, aguardando o aluno pagar.' },
  { chave: 'em_cobranca', rotulo: 'Em cobrança', descricao: 'Acordo em andamento — vencido, a vencer, futuro ou parcelando.' },
  { chave: 'risco_perda', rotulo: 'Risco de perda', descricao: 'Pediu cancelamento — ainda perseguível, mas em risco.' },
  { chave: 'encerrado', rotulo: 'Encerrado', descricao: 'Conta morta (cancelada/reembolsada) ou quitada sem saldo residual.' },
];

const EM_COBRANCA_STATUS = new Set(['vencido', 'a_vencer', 'futuro', 'em_pagamento']);

/** Faixa de uma conta. Primeira regra que casar vence, igual ao CASE do banco. */
export function faixaDe(c: ContaReceber): FaixaChave {
  if (c.status_financeiro === 'incalculavel') return 'sem_valor';
  if (c.status_financeiro === 'sem_acordo') return 'sem_acordo';
  if (c.status_financeiro === 'oferta_enviada') return 'oferta_enviada';
  if (EM_COBRANCA_STATUS.has(c.status_financeiro)) return 'em_cobranca';
  if (c.status_financeiro === 'cancelamento_solicitado' || (c.solicitou_cancelamento && !contaMorta(c))) {
    return 'risco_perda';
  }
  // contaMorta (cancelado/reembolsado) ou quitado sem saldo residual (tolerância de centavos).
  return 'encerrado';
}

/** Agrupa as contas nas 6 faixas, ordenadas por saldo_a_pagar desc dentro de cada uma. */
export function agruparPorFaixa(contas: ContaReceber[]): Record<FaixaChave, ContaReceber[]> {
  const grupos = Object.fromEntries(FAIXAS.map((f) => [f.chave, [] as ContaReceber[]])) as Record<
    FaixaChave,
    ContaReceber[]
  >;
  for (const c of contas) grupos[faixaDe(c)].push(c);
  for (const chave of Object.keys(grupos) as FaixaChave[]) {
    grupos[chave].sort((a, b) => (b.saldo_a_pagar ?? 0) - (a.saldo_a_pagar ?? 0));
  }
  return grupos;
}

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

// ── Cor (efeito visual, não semântica de status isolada) ────────────────────

export type CorConta = 'verde' | 'azul' | 'vermelho' | 'neutro';

const VERDE = new Set(['quitado']);
const AZUL = new Set(['em_pagamento', 'a_vencer', 'futuro', 'oferta_enviada']);
// `vencido` entra em vermelho por decisão consciente: é a fila mais urgente do
// financeiro (24 contas, R$ 344 mil), então recebe a cor de alarme junto com
// cancelamento/reembolso. Diferencia-se de conta morta pela FORMA do card
// (ver F3 — halo/borda/dot de urgência), não pela cor: vencido ainda é vivo e
// perseguível, morto não é. Não separar em tom próprio para não fragmentar a
// paleta de status em mais uma variação sem necessidade real de leitura.
const VERMELHO = new Set(['cancelado', 'reembolsado', 'cancelamento_solicitado', 'vencido']);

export function corDe(c: ContaReceber): CorConta {
  if (VERDE.has(c.status_financeiro)) return 'verde';
  if (AZUL.has(c.status_financeiro)) return 'azul';
  if (VERMELHO.has(c.status_financeiro)) return 'vermelho';
  return 'neutro'; // sem_acordo, incalculavel
}
