// Regras puras do Financeiro: rótulos, agregação e filtro. Sem I/O.
// Constantes do modelo HM (sinal, metades, marco, tolerância…) vêm de ./hm-modelo,
// a fonte única — não repetir números soltos aqui.
import type { ContaReceber, DiaFaturamento, StatusFinanceiro } from './types';
import { SEGUNDA_METADE, TOLERANCIA_CENTAVOS } from './hm-modelo';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export const STATUS_META: Record<StatusFinanceiro, { label: string; tone: Tone }> = {
  reembolsado: { label: 'Reembolsado', tone: 'danger' },
  cancelado: { label: 'Cancelado', tone: 'danger' },
  cancelamento_solicitado: { label: 'Pediu cancelamento', tone: 'warning' },
  quitado: { label: 'Quitado', tone: 'success' },
  em_pagamento: { label: 'Em pagamento', tone: 'info' },
  vencido: { label: 'Vencido', tone: 'danger' },
  a_vencer: { label: 'A vencer', tone: 'accent' },
  futuro: { label: 'Futuro', tone: 'info' },
  incalculavel: { label: 'A calcular', tone: 'warning' },
  oferta_enviada: { label: 'Oferta enviada', tone: 'info' },
  sem_acordo: { label: 'Sem acordo', tone: 'neutral' },
};

export const STATUS_ORDEM: StatusFinanceiro[] = [
  'vencido', 'sem_acordo', 'oferta_enviada', 'incalculavel', 'a_vencer', 'futuro', 'em_pagamento',
  'quitado', 'cancelamento_solicitado', 'cancelado', 'reembolsado',
];

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
export function statusTone(s: string): Tone {
  return STATUS_META[s as StatusFinanceiro]?.tone ?? 'neutral';
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

// ── Faturamento diário ───────────────────────────────────────────────────────
// comAcumulado() (simples, sem lacunas) foi substituída por comMetricas() —
// único ponto de cálculo do acumulado agora, já sobre a série com lacunas
// preenchidas. Ver decisão em preencherLacunas().

/** 'YYYY-MM-DD' → 'YYYY-MM-DD' do dia seguinte, sem depender de fuso (aritmética em UTC). */
function proximoDiaISO(ymd: string): string {
  const [y, m, d] = ymd.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + 1));
  return dt.toISOString().slice(0, 10);
}

export interface DiaFaturamentoPreenchido extends DiaFaturamento {
  /** true = dia sem lançamento algum na RPC (fn_fin_faturamento_diario só
   *  devolve dias COM lançamento) — preenchido aqui como zero explícito.
   *  Distingue "não faturou" de "não sabemos" na UI (nunca confundir com dado ausente). */
  preenchido: boolean;
}

/**
 * fn_fin_faturamento_diario só retorna dias com pelo menos 1 lançamento —
 * dias sem faturamento simplesmente não aparecem na série (medido: 04/08 e
 * 08/08 ausentes no período de referência). Se a média/gráfico ignorasse o
 * buraco, a média móvel de 7 dias mentiria pra cima (soma dos dias que
 * faturaram dividida por menos dias do que realmente existem na janela).
 *
 * Decisão: preencher cada dia ausente entre o primeiro e o último dia da
 * série com um registro zerado explícito (`preenchido: true`). A UI usa essa
 * flag para sinalizar a lacuna (não é "zero real e mudo", é "sem lançamento,
 * mostrado às claras") e os cálculos de média passam a contar o dia certo.
 */
export function preencherLacunas(dias: DiaFaturamento[]): DiaFaturamentoPreenchido[] {
  if (!dias.length) return [];
  const asc = [...dias].sort((a, b) => a.dia.localeCompare(b.dia));
  const porDia = new Map(asc.map((d) => [d.dia, d]));
  const resultado: DiaFaturamentoPreenchido[] = [];
  let cursor = asc[0].dia;
  const ultimo = asc[asc.length - 1].dia;
  while (cursor <= ultimo) {
    const real = porDia.get(cursor);
    if (real) {
      resultado.push({ ...real, preenchido: false });
    } else {
      resultado.push({
        dia: cursor, lancamentos: 0, cliente_pagou: 0, juros: 0, bruto: 0, liquido: 0, taxas: 0,
        sinal: 0, saldo: 0, mensalidade: 0, compra_cheia: 0, ajuste: 0, alunos: 0, preenchido: true,
      });
    }
    cursor = proximoDiaISO(cursor);
  }
  return resultado;
}

export interface DiaComMetricas extends DiaFaturamentoPreenchido {
  acumulado: number;
  /** Variação percentual de `bruto` vs. o dia anterior na série (null = sem dia anterior). */
  variacaoDiaAnterior: number | null;
  /** Média móvel dos 7 dias anteriores a este (exclui o próprio dia; null = menos de 1 dia de histórico). */
  media7d: number | null;
  /** (bruto − media7d) / media7d — posição vs. a média móvel. Null = sem média7d ainda. */
  vsMedia7d: number | null;
}

/**
 * Série completa (lacunas preenchidas) + acumulado + variação dia-a-dia +
 * posição vs. média móvel de 7 dias — tudo puro, sobre o array já ordenado
 * asc. `dias` de entrada pode vir em qualquer ordem (a RPC devolve desc).
 */
export function comMetricas(diasBrutos: DiaFaturamento[]): DiaComMetricas[] {
  const asc = preencherLacunas(diasBrutos);
  let acc = 0;
  return asc.map((d, i) => {
    acc += d.bruto;
    const anterior = i > 0 ? asc[i - 1] : null;
    const variacaoDiaAnterior = anterior && anterior.bruto > 0 ? ((d.bruto - anterior.bruto) / anterior.bruto) * 100 : null;

    const janela = asc.slice(Math.max(0, i - 7), i); // 7 dias ANTERIORES a este, sem incluir hoje
    const media7d = janela.length ? janela.reduce((a, x) => a + x.bruto, 0) / janela.length : null;
    const vsMedia7d = media7d && media7d > 0 ? ((d.bruto - media7d) / media7d) * 100 : null;

    return { ...d, acumulado: acc, variacaoDiaAnterior, media7d, vsMedia7d };
  });
}

export interface ResumoFaturamento {
  dias: number;
  bruto: number;
  liquido: number;
  taxas: number;
  media: number;
  melhorDia: DiaFaturamento | null;
  hoje: DiaFaturamento | null;
}

export function resumirFaturamento(dias: DiaFaturamento[], hojeISO: string): ResumoFaturamento {
  const bruto = dias.reduce((a, d) => a + d.bruto, 0);
  const liquido = dias.reduce((a, d) => a + d.liquido, 0);
  const melhorDia = dias.reduce<DiaFaturamento | null>((m, d) => (!m || d.bruto > m.bruto ? d : m), null);
  return {
    dias: dias.length,
    bruto,
    liquido,
    taxas: bruto - liquido,
    media: dias.length ? bruto / dias.length : 0,
    melhorDia,
    hoje: dias.find((d) => d.dia === hojeISO) ?? null,
  };
}
