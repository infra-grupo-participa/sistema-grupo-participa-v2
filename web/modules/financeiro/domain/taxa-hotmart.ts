// Faturamento · Taxa Hotmart (F7, z70; catálogo A.1 R08–R13): "A Hotmart está cobrando o que combinou?"
//
// A regra (acordo por produto, venda < R$ 100 fora, divergência = |real − esperado| > R$ 10, parcelado informativo)
// mora no SQL (fin.taxa_hotmart_vendas → fn_fin_taxa_auditoria / fn_fin_taxa_divergencias). Aqui só se normaliza
// (numeric chega como texto), se separa à vista × parcelado, se soma o resumo do topo e se monta o CSV.
// Nenhum percentual de acordo é escrito no TS.
import { celulaCsv } from './hotmart';
import { JANELA_MAX_DIAS_CAIXA, somarDias } from './caixa-hotmart';

/** Colunas que as RPCs devolvem — o teste de contrato confere contra o RETURNS TABLE da z70. */
export const COLUNAS_TAXA_AUDITORIA = [
  'tipo', 'produto_id', 'produto_nome', 'grupo_acordo', 'sem_acordo_especifico', 'parcelas', 'n_vendas', 'n_sem_taxa',
  'valor_oferta', 'taxa_real_rs', 'taxa_esperada_rs', 'taxa_real_pct', 'taxa_esperada_pct', 'n_divergentes',
  'impacto_rs', 'impacto_divergentes_rs', 'taxa_cliente_pct',
] as const;
export const COLUNAS_TAXA_DIVERGENCIAS = [
  'transacao', 'dia', 'produto_id', 'produto_nome', 'valor_oferta', 'taxa_real', 'taxa_esperada', 'diferenca',
] as const;

/** A RPC de divergências devolve no máximo isto (maior diferença primeiro). */
export const LIMITE_DIVERGENCIAS = 500;
/** Mesma janela da z70 (22023 acima disso). */
export const JANELA_MAX_DIAS_TAXA = JANELA_MAX_DIAS_CAIXA;

/** Uma linha 'a_vista' da auditoria: um produto. Percentuais em % (4.027 = 4,027%). */
export interface TaxaProduto {
  produtoId: string;
  produtoNome: string;
  /** Ex.: "4% + R$ 1,00" (vem do SQL; 2 acordos no período aparecem juntos com " / "). */
  grupoAcordo: string;
  semAcordoEspecifico: boolean;
  nVendas: number;
  nSemTaxa: number;
  valorOferta: number;
  taxaRealRs: number;
  taxaEsperadaRs: number;
  taxaRealPct: number | null;
  taxaEsperadaPct: number | null;
  nDivergentes: number;
  impactoRs: number;
  impactoDivergentesRs: number;
}

/** Uma linha 'parcelado': nº de parcelas 1..12 (informativo; o juro é do cliente). */
export interface TaxaParcela {
  parcelas: number;
  /** Todas as vendas com esse nº de parcelas (com e sem taxa informada). */
  nVendas: number;
  valorOferta: number;
  /** (cobrado − líquido) / oferta, em %. null = nenhuma venda. */
  taxaClientePct: number | null;
}

export interface DivergenciaTaxa {
  transacao: string;
  dia: string;
  produtoId: string;
  produtoNome: string;
  valorOferta: number;
  taxaReal: number;
  taxaEsperada: number;
  /** real − esperado: positivo = cobrou a mais. */
  diferenca: number;
}

export interface ResumoTaxa {
  nVendas: number;
  nSemTaxa: number;
  nDivergentes: number;
  /** Σ (real − esperado) só das divergentes: o que o financeiro contesta. */
  impactoDivergentes: number;
  nProdutos: number;
  nSemAcordoEspecifico: number;
}

export interface AuditoriaTaxa {
  produtos: TaxaProduto[];
  parcelas: TaxaParcela[];
  resumo: ResumoTaxa;
}

const num = (v: unknown) => Number(v ?? 0) || 0;
const numOuNull = (v: unknown) => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const centavos = (v: number) => Math.round(v * 100) / 100;

export function normalizarTaxaProduto(r: Record<string, unknown>): TaxaProduto {
  return {
    produtoId: String(r.produto_id ?? ''),
    produtoNome: String(r.produto_nome ?? '').trim() || String(r.produto_id ?? ''),
    grupoAcordo: String(r.grupo_acordo ?? ''),
    semAcordoEspecifico: r.sem_acordo_especifico === true,
    nVendas: num(r.n_vendas),
    nSemTaxa: num(r.n_sem_taxa),
    valorOferta: num(r.valor_oferta),
    taxaRealRs: num(r.taxa_real_rs),
    taxaEsperadaRs: num(r.taxa_esperada_rs),
    taxaRealPct: numOuNull(r.taxa_real_pct),
    taxaEsperadaPct: numOuNull(r.taxa_esperada_pct),
    nDivergentes: num(r.n_divergentes),
    impactoRs: num(r.impacto_rs),
    impactoDivergentesRs: num(r.impacto_divergentes_rs),
  };
}

export function normalizarTaxaParcela(r: Record<string, unknown>): TaxaParcela {
  const n = num(r.n_vendas) + num(r.n_sem_taxa);
  return {
    parcelas: num(r.parcelas),
    nVendas: n,
    valorOferta: num(r.valor_oferta),
    taxaClientePct: n ? numOuNull(r.taxa_cliente_pct) : null,
  };
}

export function normalizarDivergencia(r: Record<string, unknown>): DivergenciaTaxa {
  return {
    transacao: String(r.transacao ?? ''),
    dia: String(r.dia ?? '').slice(0, 10),
    produtoId: String(r.produto_id ?? ''),
    produtoNome: String(r.produto_nome ?? '').trim() || String(r.produto_id ?? ''),
    valorOferta: num(r.valor_oferta),
    taxaReal: num(r.taxa_real),
    taxaEsperada: num(r.taxa_esperada),
    diferenca: num(r.diferenca),
  };
}

export function resumirTaxa(produtos: TaxaProduto[]): ResumoTaxa {
  let nVendas = 0, nSemTaxa = 0, nDivergentes = 0, impacto = 0, nSem = 0;
  for (const p of produtos) {
    nVendas += p.nVendas;
    nSemTaxa += p.nSemTaxa;
    nDivergentes += p.nDivergentes;
    impacto += p.impactoDivergentesRs;
    if (p.semAcordoEspecifico) nSem++;
  }
  return {
    nVendas, nSemTaxa, nDivergentes, impactoDivergentes: centavos(impacto),
    nProdutos: produtos.length, nSemAcordoEspecifico: nSem,
  };
}

/** Separa as linhas da fn_fin_taxa_auditoria: produtos na ordem do SQL (maior oferta primeiro), parcelas 1..12. */
export function montarAuditoriaTaxa(linhas: Record<string, unknown>[]): AuditoriaTaxa {
  const produtos = linhas.filter((r) => r.tipo === 'a_vista').map(normalizarTaxaProduto);
  const parcelas = linhas.filter((r) => r.tipo === 'parcelado').map(normalizarTaxaParcela)
    .sort((a, b) => a.parcelas - b.parcelas);
  return { produtos, parcelas, resumo: resumirTaxa(produtos) };
}

/** Padrão: 1º de janeiro do ano corrente até hoje (cabe sempre nos 400 dias). */
export function periodoPadraoTaxa(hojeISO: string): { de: string; ate: string } {
  return { de: `${hojeISO.slice(0, 4)}-01-01`, ate: hojeISO };
}

/** Últimos 12 meses (365 dias), dentro da janela. */
export function periodo12MesesTaxa(hojeISO: string): { de: string; ate: string } {
  return { de: somarDias(hojeISO, -364), ate: hojeISO };
}

export function chaveTaxa(de: string, ate: string): string {
  return `${de}|${ate}`;
}

const dec = (v: number) => v.toFixed(2).replace('.', ',');

/** CSV (separador ;, decimal com vírgula) das divergências. Sem nome, e-mail ou documento: a RPC não devolve. */
export function csvDivergencias(linhas: DivergenciaTaxa[]): string {
  const col: [string, (d: DivergenciaTaxa) => unknown][] = [
    ['Transação', (d) => d.transacao], ['Dia', (d) => d.dia], ['Produto', (d) => d.produtoNome],
    ['Valor da oferta', (d) => dec(d.valorOferta)], ['Taxa cobrada', (d) => dec(d.taxaReal)],
    ['Taxa do acordo', (d) => dec(d.taxaEsperada)], ['Diferença', (d) => dec(d.diferenca)],
  ];
  return [col.map(([n]) => n).join(';'), ...linhas.map((d) => col.map(([, g]) => celulaCsv(g(d))).join(';'))].join('\n');
}
