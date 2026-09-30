// Contratos Holding Familiar (z93, 30/09/2026): ficha do contrato + parcelas por etapa + conciliação com a Hotmart.
// Função PURA, sem I/O. A regra (situação, casamento com a Hotmart, "fecha em", o que conta em cada mês) mora no SQL —
// fn_fin_contratos_hf_mensal / fn_fin_contratos_hf_pagamentos. Aqui só: tipar, normalizar (numeric pode chegar como
// texto), montar a grade contrato × mês com totais, validar o link antes de virar <a href> e montar o jsonb da ficha.
// Contrato: infra/supabase/migrations/20260930z93.explain.md, seção "Contrato para o front".
import { lerDataBR, lerValorBR } from './recebimentos-informados';

export type AssinadoContrato = 'sim' | 'nao' | 'indeterminado';
export const ASSINADOS: readonly AssinadoContrato[] = ['sim', 'nao', 'indeterminado'];

/** Parcela dentro de `parcelas` (jsonb). Na linha de etapa só vêm id, parcela_n, parcela_de, valor, etapa e situacao. */
export interface ParcelaContratoHF {
  id: string;
  parcela_n: number | null;
  parcela_de: number | null;
  valor: number;
  data_prevista: string | null;
  situacao: string;
  baixa_manual_em: string | null;
  /** Preenchido = baixa AUTOMÁTICA pela Hotmart: nenhuma RPC com usuário logado altera (P0001). */
  transacao_hotmart: string | null;
  etapa: string | null;
  etapa_concluida_em: string | null;
}

/** Uma linha de fn_fin_contratos_hf_mensal. `mes` NULL = linha "a receber na etapa X". */
export interface LinhaMensalContratoHF {
  contrato_id: string;
  mes: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  cidade: string | null;
  uf: string | null;
  /** Só com gp_pode_ver_cpf(); senão NULL. */
  cpf_final3: string | null;
  origem: string;
  transacao_sinal: string | null;
  data_assinatura: string | null;
  assinado: string;
  fechado_em: string | null;
  valor_bruto: number | null;
  valor_liquido: number | null;
  desconto_desc: string | null;
  entrada_valor: number | null;
  entrada_pct: number | null;
  link_contrato: string | null;
  observacao: string | null;
  arquivado_em: string | null;
  esperado: number | null;
  caiu_manual: number | null;
  caiu_hotmart: number | null;
  caiu_hotmart_liquido: number | null;
  caiu: number | null;
  a_receber_etapa: number | null;
  situacao: string | null;
  parcelas: ParcelaContratoHF[];
}

/** Uma linha de fn_fin_contratos_hf_pagamentos. sync_* = última sincronização (cron :25), igual em toda linha. */
export interface PagamentoContratoHF {
  transacao: string;
  dia: string | null;
  valor: number | null;
  nome_hotmart: string | null;
  email_hotmart: string | null;
  contrato_id: string | null;
  contrato_nome: string | null;
  situacao: string;
  motivo: string | null;
  informado_id: string | null;
  parcela_n: number | null;
  parcela_de: number | null;
  atualizado_em: string | null;
  sync_ultima_em: string | null;
  sync_erros: number | null;
  sync_mensagem: string | null;
}

/** Colunas que as RPCs devolvem — o teste de contrato confere contra o RETURNS TABLE da z93. */
export const COLUNAS_CONTRATOS_HF_MENSAL: readonly (keyof LinhaMensalContratoHF)[] = [
  'contrato_id', 'mes',
  'nome', 'email', 'telefone', 'cidade', 'uf', 'cpf_final3',
  'origem', 'transacao_sinal', 'data_assinatura', 'assinado', 'fechado_em',
  'valor_bruto', 'valor_liquido', 'desconto_desc', 'entrada_valor', 'entrada_pct',
  'link_contrato', 'observacao', 'arquivado_em',
  'esperado', 'caiu_manual', 'caiu_hotmart', 'caiu_hotmart_liquido', 'caiu',
  'a_receber_etapa', 'situacao', 'parcelas',
];

export const COLUNAS_CONTRATOS_HF_PAGAMENTOS: readonly (keyof PagamentoContratoHF)[] = [
  'transacao', 'dia', 'valor', 'nome_hotmart', 'email_hotmart',
  'contrato_id', 'contrato_nome', 'situacao', 'motivo',
  'informado_id', 'parcela_n', 'parcela_de', 'atualizado_em',
  'sync_ultima_em', 'sync_erros', 'sync_mensagem',
];

// ─── Normalização ──────────────────────────────────────────────────────────
const num = (v: unknown): number | null => (v == null || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);
const int = (v: unknown): number | null => { const n = num(v); return n != null && Number.isInteger(n) ? n : null; };
const txt = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));

function normalizarParcela(r: Record<string, unknown>): ParcelaContratoHF {
  return {
    id: String(r.id ?? ''),
    parcela_n: int(r.parcela_n),
    parcela_de: int(r.parcela_de),
    valor: num(r.valor) ?? 0,
    data_prevista: dia(r.data_prevista),
    situacao: String(r.situacao ?? ''),
    baixa_manual_em: dia(r.baixa_manual_em),
    transacao_hotmart: txt(r.transacao_hotmart),
    etapa: txt(r.etapa),
    etapa_concluida_em: dia(r.etapa_concluida_em),
  };
}

function lerParcelas(v: unknown): ParcelaContratoHF[] {
  let x = v;
  if (typeof x === 'string') { try { x = JSON.parse(x); } catch { return []; } }
  return Array.isArray(x) ? x.filter((p) => p && typeof p === 'object').map((p) => normalizarParcela(p as Record<string, unknown>)) : [];
}

export function normalizarLinhaMensal(r: Record<string, unknown>): LinhaMensalContratoHF {
  return {
    contrato_id: String(r.contrato_id ?? ''),
    mes: dia(r.mes),
    nome: txt(r.nome), email: txt(r.email), telefone: txt(r.telefone), cidade: txt(r.cidade), uf: txt(r.uf),
    cpf_final3: txt(r.cpf_final3),
    origem: String(r.origem ?? ''),
    transacao_sinal: txt(r.transacao_sinal),
    data_assinatura: dia(r.data_assinatura),
    assinado: String(r.assinado ?? 'indeterminado'),
    fechado_em: dia(r.fechado_em),
    valor_bruto: num(r.valor_bruto), valor_liquido: num(r.valor_liquido),
    desconto_desc: txt(r.desconto_desc),
    entrada_valor: num(r.entrada_valor), entrada_pct: num(r.entrada_pct),
    link_contrato: txt(r.link_contrato),
    observacao: txt(r.observacao),
    arquivado_em: txt(r.arquivado_em),
    esperado: num(r.esperado), caiu_manual: num(r.caiu_manual), caiu_hotmart: num(r.caiu_hotmart),
    caiu_hotmart_liquido: num(r.caiu_hotmart_liquido), caiu: num(r.caiu),
    a_receber_etapa: num(r.a_receber_etapa),
    situacao: txt(r.situacao),
    parcelas: lerParcelas(r.parcelas),
  };
}

export function normalizarPagamento(r: Record<string, unknown>): PagamentoContratoHF {
  return {
    transacao: String(r.transacao ?? ''),
    dia: dia(r.dia),
    valor: num(r.valor),
    nome_hotmart: txt(r.nome_hotmart), email_hotmart: txt(r.email_hotmart),
    contrato_id: txt(r.contrato_id), contrato_nome: txt(r.contrato_nome),
    situacao: String(r.situacao ?? ''),
    motivo: txt(r.motivo),
    informado_id: txt(r.informado_id),
    parcela_n: int(r.parcela_n), parcela_de: int(r.parcela_de),
    atualizado_em: txt(r.atualizado_em),
    sync_ultima_em: txt(r.sync_ultima_em),
    sync_erros: int(r.sync_erros),
    sync_mensagem: txt(r.sync_mensagem),
  };
}

// ─── Grade contrato × mês ──────────────────────────────────────────────────
/** Dados da ficha (iguais em todas as linhas do mesmo contrato). */
export type FichaContratoHF = Omit<LinhaMensalContratoHF,
  'mes' | 'esperado' | 'caiu_manual' | 'caiu_hotmart' | 'caiu_hotmart_liquido' | 'caiu' | 'a_receber_etapa' | 'situacao' | 'parcelas'>
  & { id: string };

export interface SomaMes { esperado: number; caiu_manual: number; caiu_hotmart: number; caiu: number }
export interface CelulaMesContrato extends SomaMes { situacao: string | null; parcelas: ParcelaContratoHF[] }
export interface ContratoNaGrade {
  ficha: FichaContratoHF;
  meses: Record<string, CelulaMesContrato>;
  /** Linha "a receber na etapa X" (parcelas sem data); null = o contrato não tem parcela por etapa pendente. */
  etapa: { total: number; parcelas: ParcelaContratoHF[] } | null;
  total: SomaMes;
}
export interface GradeContratosHF {
  meses: string[];
  contratos: ContratoNaGrade[];
  totalMes: Record<string, SomaMes>;
  totalEtapa: number;
  total: SomaMes;
}

const zero = (): SomaMes => ({ esperado: 0, caiu_manual: 0, caiu_hotmart: 0, caiu: 0 });
/** Soma em centavos: 0,1 + 0,2 não pode virar 0,30000000000000004 no rodapé. */
const mais = (a: number, b: number | null) => Math.round(a * 100 + Math.round((b ?? 0) * 100)) / 100;
function acumular(s: SomaMes, c: SomaMes) {
  s.esperado = mais(s.esperado, c.esperado);
  s.caiu_manual = mais(s.caiu_manual, c.caiu_manual);
  s.caiu_hotmart = mais(s.caiu_hotmart, c.caiu_hotmart);
  s.caiu = mais(s.caiu, c.caiu);
}

function fichaDa(l: LinhaMensalContratoHF): FichaContratoHF {
  return {
    id: l.contrato_id, contrato_id: l.contrato_id,
    nome: l.nome, email: l.email, telefone: l.telefone, cidade: l.cidade, uf: l.uf, cpf_final3: l.cpf_final3,
    origem: l.origem, transacao_sinal: l.transacao_sinal, data_assinatura: l.data_assinatura, assinado: l.assinado,
    fechado_em: l.fechado_em, valor_bruto: l.valor_bruto, valor_liquido: l.valor_liquido, desconto_desc: l.desconto_desc,
    entrada_valor: l.entrada_valor, entrada_pct: l.entrada_pct, link_contrato: l.link_contrato, observacao: l.observacao,
    arquivado_em: l.arquivado_em,
  };
}

/**
 * Linhas da RPC (já em ordem nome, contrato, mês nulls last) → grade. A ordem dos contratos é a do SQL; os meses são
 * todos os que vieram, em ordem (a grade do SQL é densa: todo contrato tem todos os meses do período).
 */
export function montarGradeContratos(linhas: LinhaMensalContratoHF[]): GradeContratosHF {
  const porId = new Map<string, ContratoNaGrade>();
  const meses = new Set<string>();
  for (const l of linhas) {
    let c = porId.get(l.contrato_id);
    if (!c) { c = { ficha: fichaDa(l), meses: {}, etapa: null, total: zero() }; porId.set(l.contrato_id, c); }
    if (l.mes == null) {
      c.etapa = { total: l.a_receber_etapa ?? 0, parcelas: l.parcelas };
      continue;
    }
    meses.add(l.mes);
    const cel: CelulaMesContrato = {
      esperado: l.esperado ?? 0, caiu_manual: l.caiu_manual ?? 0, caiu_hotmart: l.caiu_hotmart ?? 0, caiu: l.caiu ?? 0,
      situacao: l.situacao, parcelas: l.parcelas,
    };
    c.meses[l.mes] = cel;
    acumular(c.total, cel);
  }
  const ms = [...meses].sort();
  const totalMes: Record<string, SomaMes> = Object.fromEntries(ms.map((m) => [m, zero()]));
  const total = zero();
  let totalEtapa = 0;
  const contratos = [...porId.values()];
  for (const c of contratos) {
    for (const m of ms) if (c.meses[m]) acumular(totalMes[m], c.meses[m]);
    acumular(total, c.total);
    totalEtapa = mais(totalEtapa, c.etapa?.total ?? 0);
  }
  return { meses: ms, contratos, totalMes, totalEtapa, total };
}

/** Todas as parcelas do contrato que vieram no período (meses + etapa), sem repetir, na ordem da parcela. */
export function parcelasDoContrato(c: ContratoNaGrade): ParcelaContratoHF[] {
  const vistas = new Map<string, ParcelaContratoHF>();
  for (const cel of Object.values(c.meses)) for (const p of cel.parcelas) vistas.set(p.id, p);
  for (const p of c.etapa?.parcelas ?? []) if (!vistas.has(p.id)) vistas.set(p.id, p);
  return [...vistas.values()].sort((a, b) => (a.parcela_n ?? 999) - (b.parcela_n ?? 999)
    || (a.data_prevista ?? '9999').localeCompare(b.data_prevista ?? '9999') || a.id.localeCompare(b.id));
}

// ─── Link do contrato ──────────────────────────────────────────────────────
/** MESMA regex do banco (fn_fin_contrato_hf_salvar): https, só Google Docs/Drive, só ASCII seguro, até 500. */
const LINK_OK = /^https:\/\/(docs|drive)\.google\.com\/[A-Za-z0-9/_?=&.%#-]*$/;

/** O link só vira <a href> se passar na validação do banco; fora disso a tela mostra como texto. */
export function linkContratoSeguro(v: string | null | undefined): string | null {
  return typeof v === 'string' && v.length <= 500 && LINK_OK.test(v) ? v : null;
}

// ─── Fila de conferência ───────────────────────────────────────────────────
/** Prefixo estável do motivo (antes de ":") → rótulo curto. A frase depois do ":" já vem em português do banco. */
export const ROTULO_MOTIVO_FILA: Record<string, string> = {
  sem_contrato: 'Sem contrato',
  mais_de_um_contrato: 'Mais de um contrato',
  contrato_sem_parcelas: 'Contrato sem parcelas',
  fora_da_janela: 'Fora da janela',
  parcela_ja_baixada: 'Parcela já baixada',
  valor_nao_bate: 'Valor não bate',
};

/** "valor_nao_bate: nenhuma parcela…" → { rotulo: 'Valor não bate', frase: 'nenhuma parcela…' }. Prefixo desconhecido: cru. */
export function lerMotivoFila(motivo: string | null): { rotulo: string; frase: string | null } {
  if (!motivo) return { rotulo: '—', frase: null };
  const i = motivo.indexOf(':');
  const cod = i > 0 ? motivo.slice(0, i).trim() : motivo.trim();
  const frase = i > 0 ? motivo.slice(i + 1).trim() || null : null;
  const rotulo = ROTULO_MOTIVO_FILA[cod];
  return rotulo ? { rotulo, frase } : { rotulo: motivo, frase: null };
}

/** Status da sincronização (repetido em toda linha): a 1ª linha basta. Sem linha = sem informação. */
export function statusSync(pags: PagamentoContratoHF[]): { ultima_em: string | null; erros: number; mensagem: string | null } | null {
  const p = pags[0];
  if (!p) return null;
  return { ultima_em: p.sync_ultima_em, erros: p.sync_erros ?? 0, mensagem: p.sync_mensagem };
}

// ─── Ficha: formulário → jsonb de fn_fin_contrato_hf_salvar ────────────────
export interface FormFichaContrato {
  valor_bruto: string;
  valor_liquido: string;
  link_contrato: string;
  assinado: AssinadoContrato;
  data_assinatura: string;
}

const valorForm = (v: number | null) => (v == null ? '' : v.toFixed(2).replace('.', ','));

export function formDaFicha(f: FichaContratoHF): FormFichaContrato {
  return {
    valor_bruto: valorForm(f.valor_bruto),
    valor_liquido: valorForm(f.valor_liquido),
    link_contrato: f.link_contrato ?? '',
    assinado: (ASSINADOS as readonly string[]).includes(f.assinado) ? (f.assinado as AssinadoContrato) : 'indeterminado',
    data_assinatura: f.data_assinatura ?? '',
  };
}

/** Teto do banco: ^[0-9]{1,8}(\.[0-9]{1,2})?$. */
const VALOR_MAX = 99_999_999.99;

/**
 * Formulário → p. Só vão as chaves que MUDARAM (chave ausente = o banco mantém). Checagem mínima para não mandar lixo;
 * a regra de verdade é do SQL. Valor vai como texto "44640.00" (o banco recusa número com vírgula).
 */
export function payloadFicha(form: FormFichaContrato, ficha: FichaContratoHF): { p: Record<string, string | null> | null; erros: string[] } {
  const erros: string[] = [];
  const p: Record<string, string | null> = { id: ficha.id };
  const valor = (k: 'valor_bruto' | 'valor_liquido', rotulo: string) => {
    const v = lerValorBR(form[k]);
    if (v === undefined) { erros.push(`${rotulo}: valor inválido.`); return; }
    if (v != null && (v <= 0 || v > VALOR_MAX)) { erros.push(`${rotulo}: maior que zero (ou vazio).`); return; }
    if (v !== ficha[k]) p[k] = v == null ? null : v.toFixed(2);
  };
  valor('valor_bruto', 'Valor cheio');
  valor('valor_liquido', 'Valor líquido');
  const link = form.link_contrato.trim();
  if (link && !linkContratoSeguro(link)) erros.push('Link do contrato: use o link https do Google Docs ou do Drive.');
  else if ((link || null) !== ficha.link_contrato) p.link_contrato = link || null;
  if (!(ASSINADOS as readonly string[]).includes(form.assinado)) erros.push('Assinado: sim, não ou indeterminado.');
  else if (form.assinado !== ficha.assinado) p.assinado = form.assinado;
  const data = lerDataBR(form.data_assinatura);
  if (data === undefined) erros.push('Data de assinatura inválida.');
  else if (data !== ficha.data_assinatura) p.data_assinatura = data;
  if (erros.length) return { p: null, erros };
  if (Object.keys(p).length === 1) return { p: null, erros: ['Nada mudou.'] };
  return { p, erros };
}

/** Motivo de arquivar / desfundir: 3 a 500 caracteres (mesma faixa do banco). */
export const motivoValido = (m: string) => m.trim().length >= 3 && m.trim().length <= 500;

/** Desfundir só existe na ficha que NÃO nasceu do sinal e tem um sinal fundido (o banco recusa o resto). */
export const podeDesfundir = (f: FichaContratoHF) => !f.arquivado_em && f.origem !== 'hotmart_sinal' && !!f.transacao_sinal;

/** Parcela baixada pela Hotmart: nenhuma ação manual (o banco recusa com P0001). */
export const baixaPelaHotmart = (p: { transacao_hotmart: string | null }) => !!p.transacao_hotmart;

/**
 * Colagem da planilha dentro da ficha: as linhas vão ligadas A ESTE contrato (contrato_id). Uma colagem com mais de um
 * cliente ligaria parcelas de outra pessoa à ficha — recusada antes de ir ao banco. Devolve a mensagem de recusa ou null.
 */
export function recusaColagemNoContrato(clientes: string[]): string | null {
  const norm = new Set(clientes.map((c) => c.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim()));
  if (norm.size > 1) return `A colagem tem ${norm.size} clientes diferentes: cole só as linhas deste contrato.`;
  return null;
}
