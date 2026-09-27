// Regras puras do Financeiro: rótulos, agregação e filtro. Sem I/O.
// Constantes do modelo HM (sinal, metades, marco, tolerância…) vêm de ./hm-modelo,
// a fonte única — não repetir números soltos aqui.
import type { ContaReceber, StatusFinanceiro } from './types';
import { SEGUNDA_METADE, TOLERANCIA_CENTAVOS } from './hm-modelo';

export const STATUS_META: Record<StatusFinanceiro, { label: string }> = {
  reembolsado: { label: 'Reembolsado' },
  cancelado: { label: 'Cancelado' },
  cancelamento_solicitado: { label: 'Pediu cancelamento' },
  quitado: { label: 'Quitado' },
  em_pagamento: { label: 'Em pagamento' },
  vencido: { label: 'Vencido' },
  a_vencer: { label: 'A vencer' },
  futuro: { label: 'Futuro' },
  incalculavel: { label: 'A calcular' },
  oferta_enviada: { label: 'Oferta enviada' },
  sem_acordo: { label: 'Sem acordo' },
};

/** Máscara LGPD do documento: mantém os 4 últimos dígitos. Igual a mascarar() do auth. */
export function mascararDoc(doc: string | null, podeVer: boolean): string {
  const s = String(doc ?? '');
  if (podeVer || !s.trim()) return s;
  const dig = s.replace(/\D/g, '');
  return dig.length >= 4 ? '•'.repeat(Math.max(0, s.length - 4)) + dig.slice(-4) : '•'.repeat(s.length);
}

/** Método de pagamento da Hotmart → rótulo pt-BR. Vem cru em sinal_metodo/saldo_metodo
 *  (PIX, CREDIT_CARD, HOTMART_INSTALLMENTS…). Fonte: cs.hm_pagamentos.metodo_pagamento. */
export function formaPagamentoLabel(metodo: string | null | undefined): string {
  switch (String(metodo ?? '').toUpperCase()) {
    case 'PIX': return 'Pix';
    case 'CREDIT_CARD': return 'Cartão';
    case 'HOTMART_INSTALLMENTS': return 'Parcelado Hotmart';
    case 'BILLET':
    case 'BOLETO': return 'Boleto';
    case 'PAYPAL': return 'PayPal';
    case 'GOOGLE_PAY': return 'Google Pay';
    case 'SAMSUNG_PAY': return 'Samsung Pay';
    case '': return '—';
    default: return metodo as string;
  }
}

export function statusLabel(s: string): string {
  return STATUS_META[s as StatusFinanceiro]?.label ?? s;
}

/**
 * Uma conta está "morta" quando não há mais nada a receber dela: cancelada ou
 * reembolsada. Fica fora de todo total de dinheiro a perseguir — senão o
 * a-receber da turma incha com gente que já saiu.
 */
export function contaMorta(c: ContaReceber): boolean {
  return c.status_financeiro === 'cancelado' || c.status_financeiro === 'reembolsado';
}

/**
 * Tolerância de centavos: o arredondamento das 12x deixa resíduo de
 * R$ 0,01–0,04 no saldo mesmo com o aluno quitado. Para TOTALIZAR ou EXIBIR
 * saldo a receber, |saldo| < R$ 1 vale 0. Não mexe no status_financeiro —
 * o banco continua sendo a fonte do status.
 */
export function saldoEfetivo(c: ContaReceber): number {
  const s = c.saldo_a_pagar ?? 0;
  return Math.abs(s) < TOLERANCIA_CENTAVOS ? 0 : s;
}

/**
 * Reserva de vaga: pagou só o sinal (R$ 300) e nada do saldo — ainda pode não
 * converter em aluno. É diferente de "aluno em pagamento".
 */
export function ehReserva(c: ContaReceber): boolean {
  return (c.saldo_pago_bruto ?? 0) <= 0 && (c.sinal_bruto ?? 0) > 0;
}

/**
 * `pacote_regra` diverge de `pacote` (cravado) além da tolerância de
 * centavos? O cravado SEMPRE prevalece no cálculo (comportamento já
 * existente, não muda) — isto é só SINAL, informação neutra, não alerta de
 * erro nem fila de correção (decisão do Marcio, 2026-09-04).
 *
 * `null` em qualquer um dos dois campos = "não sei" (dado ausente, RPC ainda
 * não aplicada em produção ou card sem régua calculável) — NUNCA "sem
 * divergência". Retorna `false` neste caso por segurança de exibição (não
 * marca o card), mas é um `false` de dado ausente, distinto do `false` de
 * "checado e igual".
 *
 * Mesma TOLERANCIA_CENTAVOS de saldoEfetivo (R$ 1) — uma segunda tolerância
 * faria o card discordar do rodapé sobre o que é "igual".
 */
export function temDivergenciaPacote(c: ContaReceber): boolean {
  if (c.pacote_regra == null || c.divergencia_regra == null) return false;
  return Math.abs(c.divergencia_regra) >= TOLERANCIA_CENTAVOS;
}

/**
 * Sentido da divergência (só tem sentido quando `temDivergenciaPacote` é
 * true): positivo = cravado cobrando A MAIS que a régua; negativo = dinheiro
 * na mesa (régua cobraria mais que o cravado). `null` = sem divergência
 * conhecida (dado ausente ou dentro da tolerância) — companheiro de
 * `temDivergenciaPacote`, nunca usar um sem o outro.
 */
export function direcaoDivergencia(c: ContaReceber): 'a_maior' | 'a_menor' | null {
  if (!temDivergenciaPacote(c)) return null;
  return (c.divergencia_regra as number) > 0 ? 'a_maior' : 'a_menor';
}

/** 2ª metade condicional do honorário do parceiro — R$ 15.000 por parceiro ativo.
 *  Valor vem de ./hm-modelo (fonte única); alias mantido por compatibilidade. */
export const SEGUNDA_METADE_VALOR = SEGUNDA_METADE;

/**
 * Métrica INFORMATIVA da 2ª metade do honorário (R$ 15.000 por parceiro),
 * devida só depois que o parceiro fatura R$ 150.000 em até 1 ano. Não há fonte
 * de dados desse marco ainda, então NUNCA entra nas contas a receber correntes.
 * Parceiro ativo = conta sem cancelamento/reembolso E que já pagou algo do
 * saldo (já é aluno de fato — reserva de vaga não conta).
 */
export function segundaMetadeCondicional(contas: ContaReceber[]): { valor: number; parceiros: number } {
  const fora: StatusFinanceiro[] = ['cancelado', 'reembolsado', 'cancelamento_solicitado'];
  const parceiros = contas.filter(
    (c) => !fora.includes(c.status_financeiro) && (c.saldo_pago_bruto ?? 0) > 0,
  ).length;
  return { valor: parceiros * SEGUNDA_METADE_VALOR, parceiros };
}

export interface Resumo {
  alunos: number;
  recebidoBruto: number;
  recebidoLiquido: number;
  taxas: number;
  aReceber: number;
  vencido: number;
  vencidoQtd: number;
  quitados: number;
  semAcordo: number;
  incalculavel: number;
  emAtraso: number;
  /** Pediu cancelamento (kanban ou timestamp) mas ainda não efetivado — perseguível. */
  pediuCancelamento: number;
  /** Cancelamento efetivado ou reembolso — conta morta. */
  cancelados: number;
  pacoteTotal: number;
  /** % do contratado que já entrou. */
  cobertura: number;
}

export function resumir(contas: ContaReceber[]): Resumo {
  const vivos = contas.filter((c) => !contaMorta(c));
  const soma = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
  const qtd = (s: StatusFinanceiro) => vivos.filter((c) => c.status_financeiro === s).length;

  const recebidoBruto = soma(contas.map((c) => c.total_pago_bruto ?? 0));
  const recebidoLiquido = soma(contas.map((c) => c.total_pago_liquido ?? 0));
  const aReceber = soma(vivos.map(saldoEfetivo));
  const pacoteTotal = soma(vivos.map((c) => c.pacote ?? 0));

  return {
    alunos: contas.length,
    recebidoBruto,
    recebidoLiquido,
    taxas: recebidoBruto - recebidoLiquido,
    aReceber,
    vencido: soma(vivos.filter((c) => c.status_financeiro === 'vencido').map(saldoEfetivo)),
    vencidoQtd: qtd('vencido'),
    quitados: contas.filter((c) => c.status_financeiro === 'quitado').length,
    semAcordo: qtd('sem_acordo'),
    incalculavel: qtd('incalculavel'),
    emAtraso: vivos.filter((c) => (c.dias_atraso ?? 0) > 0).length,
    // Pediu cancelamento mas ainda perseguível (não efetivado): kanban ou timestamp.
    pediuCancelamento: contas.filter((c) => c.solicitou_cancelamento && !contaMorta(c)).length,
    cancelados: contas.filter((c) => contaMorta(c)).length,
    pacoteTotal,
    cobertura: pacoteTotal > 0 ? (recebidoBruto / pacoteTotal) * 100 : 0,
  };
}

export interface Fatia {
  chave: string;
  alunos: number;
  recebido: number;
  aReceber: number;
}

/** Agrupa por uma dimensão (canal, status...). Usado nos gráficos do dashboard. */
export function agrupar(contas: ContaReceber[], por: (c: ContaReceber) => string): Fatia[] {
  const mapa = new Map<string, Fatia>();
  for (const c of contas) {
    const chave = por(c) || '—';
    const f = mapa.get(chave) ?? { chave, alunos: 0, recebido: 0, aReceber: 0 };
    f.alunos += 1;
    f.recebido += c.total_pago_bruto ?? 0;
    if (!contaMorta(c)) f.aReceber += saldoEfetivo(c);
    mapa.set(chave, f);
  }
  return [...mapa.values()].sort((a, b) => b.aReceber - a.aReceber || b.alunos - a.alunos);
}

export type Gaveta =
  | 'todos' | 'vencido' | 'sem_acordo' | 'incalculavel' | 'a_receber' | 'quitado'
  | 'pediu_cancelamento' | 'cancelado';

export interface Filtros {
  termo: string;
  status: string[];
  canais: string[];
  produtos: string[];
  /** Gaveta clicada nos KPIs. */
  gaveta: Gaveta;
}

export const FILTROS_VAZIOS: Filtros = { termo: '', status: [], canais: [], produtos: [], gaveta: 'todos' };

/** Múltipla seleção: OR dentro de cada filtro, AND entre filtros. */
export function filtrar(contas: ContaReceber[], f: Filtros): ContaReceber[] {
  const termo = f.termo.trim().toLowerCase();
  return contas.filter((c) => {
    if (f.gaveta === 'vencido' && c.status_financeiro !== 'vencido') return false;
    if (f.gaveta === 'sem_acordo' && c.status_financeiro !== 'sem_acordo') return false;
    if (f.gaveta === 'incalculavel' && c.status_financeiro !== 'incalculavel') return false;
    if (f.gaveta === 'quitado' && c.status_financeiro !== 'quitado') return false;
    if (f.gaveta === 'a_receber' && !(saldoEfetivo(c) > 0 && !contaMorta(c))) return false;
    // Pediu cancelamento (kanban ou timestamp) e ainda perseguível; cancelado = efetivado/reembolso.
    if (f.gaveta === 'pediu_cancelamento' && !(c.solicitou_cancelamento && !contaMorta(c))) return false;
    if (f.gaveta === 'cancelado' && !contaMorta(c)) return false;

    if (f.status.length && !f.status.includes(c.status_financeiro)) return false;
    if (f.canais.length && !f.canais.includes(c.canal)) return false;
    if (f.produtos.length && !f.produtos.includes(c.produto)) return false;

    if (termo) {
      const alvo = `${c.nome} ${c.email} ${c.telefone ?? ''} ${c.acordo ?? ''}`.toLowerCase();
      if (!alvo.includes(termo)) return false;
    }
    return true;
  });
}
