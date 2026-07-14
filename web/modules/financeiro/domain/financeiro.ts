// Regras puras do Financeiro: rótulos, agregação e filtro. Sem I/O.
import type { ContaReceber, DiaFaturamento, StatusFinanceiro } from './types';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

export const STATUS_META: Record<StatusFinanceiro, { label: string; tone: Tone }> = {
  reembolsado: { label: 'Reembolsado', tone: 'danger' },
  cancelado: { label: 'Cancelado', tone: 'danger' },
  cancelamento_solicitado: { label: 'Pediu cancelamento', tone: 'warning' },
  quitado: { label: 'Quitado', tone: 'success' },
  em_pagamento: { label: 'Em pagamento', tone: 'info' },
  vencido: { label: 'Vencido', tone: 'danger' },
  a_vencer: { label: 'A vencer', tone: 'accent' },
  incalculavel: { label: 'A calcular', tone: 'warning' },
  oferta_enviada: { label: 'Oferta enviada', tone: 'info' },
  sem_acordo: { label: 'Sem acordo', tone: 'neutral' },
};

export const STATUS_ORDEM: StatusFinanceiro[] = [
  'vencido', 'sem_acordo', 'oferta_enviada', 'incalculavel', 'a_vencer', 'em_pagamento',
  'quitado', 'cancelamento_solicitado', 'cancelado', 'reembolsado',
];

/** Máscara LGPD do documento: mantém os 4 últimos dígitos. Igual a mascarar() do auth. */
export function mascararDoc(doc: string | null, podeVer: boolean): string {
  const s = String(doc ?? '');
  if (podeVer || !s.trim()) return s;
  const dig = s.replace(/\D/g, '');
  return dig.length >= 4 ? '•'.repeat(Math.max(0, s.length - 4)) + dig.slice(-4) : '•'.repeat(s.length);
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
  const aReceber = soma(vivos.map((c) => c.saldo_a_pagar ?? 0));
  const pacoteTotal = soma(vivos.map((c) => c.pacote ?? 0));

  return {
    alunos: contas.length,
    recebidoBruto,
    recebidoLiquido,
    taxas: recebidoBruto - recebidoLiquido,
    aReceber,
    vencido: soma(vivos.filter((c) => c.status_financeiro === 'vencido').map((c) => c.saldo_a_pagar ?? 0)),
    vencidoQtd: qtd('vencido'),
    quitados: contas.filter((c) => c.status_financeiro === 'quitado').length,
    semAcordo: qtd('sem_acordo'),
    incalculavel: qtd('incalculavel'),
    emAtraso: vivos.filter((c) => (c.dias_atraso ?? 0) > 0).length,
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
    if (!contaMorta(c)) f.aReceber += c.saldo_a_pagar ?? 0;
    mapa.set(chave, f);
  }
  return [...mapa.values()].sort((a, b) => b.aReceber - a.aReceber || b.alunos - a.alunos);
}

export type Gaveta = 'todos' | 'vencido' | 'sem_acordo' | 'incalculavel' | 'a_receber' | 'quitado';

export interface Filtros {
  termo: string;
  status: string[];
  canais: string[];
  /** Gaveta clicada nos KPIs. */
  gaveta: Gaveta;
}

export const FILTROS_VAZIOS: Filtros = { termo: '', status: [], canais: [], gaveta: 'todos' };

/** Múltipla seleção: OR dentro de cada filtro, AND entre filtros. */
export function filtrar(contas: ContaReceber[], f: Filtros): ContaReceber[] {
  const termo = f.termo.trim().toLowerCase();
  return contas.filter((c) => {
    if (f.gaveta === 'vencido' && c.status_financeiro !== 'vencido') return false;
    if (f.gaveta === 'sem_acordo' && c.status_financeiro !== 'sem_acordo') return false;
    if (f.gaveta === 'incalculavel' && c.status_financeiro !== 'incalculavel') return false;
    if (f.gaveta === 'quitado' && c.status_financeiro !== 'quitado') return false;
    if (f.gaveta === 'a_receber' && !((c.saldo_a_pagar ?? 0) > 0 && !contaMorta(c))) return false;

    if (f.status.length && !f.status.includes(c.status_financeiro)) return false;
    if (f.canais.length && !f.canais.includes(c.canal)) return false;

    if (termo) {
      const alvo = `${c.nome} ${c.email} ${c.telefone ?? ''} ${c.acordo ?? ''}`.toLowerCase();
      if (!alvo.includes(termo)) return false;
    }
    return true;
  });
}

// ── Faturamento diário ───────────────────────────────────────────────────────

export interface DiaComAcumulado extends DiaFaturamento {
  acumulado: number;
}

/** Adiciona o acumulado corrido (do mais antigo ao mais recente). Entrada vem desc. */
export function comAcumulado(dias: DiaFaturamento[]): DiaComAcumulado[] {
  const asc = [...dias].sort((a, b) => a.dia.localeCompare(b.dia));
  let acc = 0;
  const mapa = new Map<string, number>();
  for (const d of asc) {
    acc += d.bruto;
    mapa.set(d.dia, acc);
  }
  return dias.map((d) => ({ ...d, acumulado: mapa.get(d.dia) ?? 0 }));
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
