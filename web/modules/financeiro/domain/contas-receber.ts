// Contas a Receber (28/09/2026). Função PURA, sem I/O. Substitui a planilha semanal do financeiro
// ("Contas a Receber Semanal Set-Dez26"), separando o CERTO do ESTIMADO:
//   CERTO
//   bloco 1 — vendas já feitas, dinheiro ainda a cair (90% − 3,89% em D+2 útil; 10% no 1º dia útil ≥ D+30);
//   bloco 2 — assinaturas e parcelas futuras já contratadas;
//   bloco 5 — recebimentos informados (renovações Diamante/Aurum negociadas fora, cadastradas no sistema — 28/09).
//   ESTIMADO (z67, só com a premissa projecao_no_receber ligada)
//   bloco 3 — vendas novas por semana (premissa ou sugestão medida);
//   bloco 4 — evento planejado (tamanho × curva do evento de referência);
//   bloco 6 — reserva de reembolso e chargeback, NEGATIVA, sobre 3 + 4.
//   FORA DA SOMA
//   bloco 8 — informativo: saldos combinados no board (situacao 'informativo'); somar contaria duas vezes com o bloco 3.
// Bloco 7 (Soluções) fica para depois.
//
// Fonte: public.fn_fin_receber_semanal(p_corte, p_ate, p_cenario) — UMA chamada por cenário (NÃO é fn_fin_contas_receber(text), o razão do board); o cálculo de data de caixa (dias úteis,
// feriados) e a baixa do que já se realizou moram no banco. Aqui só: tipar, converter numeric, cortar em semanas e somar.
//
// Esta é a ÚNICA fonte da semana: a tela e o PDF futuro usam `semanas()` e `agregarReceber()` daqui.

export type ComponenteReceber = 'antecipacao' | 'garantia' | 'cheio' | 'reserva';
/**
 * Só `a_receber` soma. `realizada` vem para auditoria; `em_atraso_fora` saiu da projeção; `coberta_informado` é a
 * cobrança do bloco 2 que um recebimento informado (bloco 5) já cobre — o informado prevalece e ela sai da soma com o
 * grupo inalterado (contrato do bloco 5, conflito 6 do plano).
 */
export type SituacaoReceber = 'a_receber' | 'realizada' | 'em_atraso_fora' | 'coberta_informado' | 'sem_base' | 'informativo';
// z67: 'sem_base' = grupo estimado sem premissa e sem sugestão medida (valor e data NULL no banco: "não sei", nunca zero);
// 'informativo' = bloco 8, acordos no board, visível e FORA da soma.

/** Blocos do ESTIMADO (z67). O resto que soma é CERTO. O cenário mexe sobretudo aqui. */
export const BLOCOS_ESTIMADO: readonly number[] = [3, 4, 6];
/** Bloco informativo (acordos combinados no board): aparece, nunca soma. */
export const BLOCO_INFORMATIVO = 8;
export const secaoDoBloco = (bloco: number): 'certo' | 'estimado' => (BLOCOS_ESTIMADO.includes(bloco) ? 'estimado' : 'certo');

/** Blocos 3 e 4 (z67): uma venda projetada do dia que cai nesta data de caixa, e de onde veio o valor. */
export interface VendaProjetada {
  dia: string | null;
  /** Venda do dia (líquido estimado), não o que cai: esse é a linha. */
  valor_venda: number;
  /** 'mediana 12 sem' | 'definido por <nome> em dd/mm/aaaa' | 'curva <evento de referência>'. */
  base: string | null;
}

/** Bloco 1: uma venda do dia que compõe a antecipação/garantia daquele dia. */
export interface VendaDoDia {
  transacao: string;
  produto: string | null;
  nome: string | null;
  /** Líquido da VENDA (não o valor que cai: esse é a linha). */
  liquido: number;
}

/** Bloco 2 (contrato v2, z66): uma transação PAGA do contrato até o corte. Sem e-mail, sem documento, sem nome. */
export interface PagamentoContrato {
  transacao: string;
  /** Nº da recorrência/parcela na Hotmart. */
  n: number | null;
  /** Dia da aprovação (YYYY-MM-DD). */
  dia: string | null;
  liquido: number;
}

/** Cenário da previsão (z66): muda só as premissas que aceitam cenário; sem valor próprio, vale a base. */
export type CenarioReceber = 'base' | 'conservador' | 'otimista';
export const CENARIOS_RECEBER: readonly CenarioReceber[] = ['base', 'conservador', 'otimista'];

/** Uma linha de fn_fin_receber_semanal, já normalizada. */
export interface LinhaReceber {
  bloco: number;
  grupo: string;
  componente: ComponenteReceber;
  /** Dia em que o dinheiro fica disponível (YYYY-MM-DD). É o eixo da grade. NULL em realizada/em_atraso_fora e
   *  quando a premissa de recebimento está desligada no banco — nunca vira data inventada. */
  data_caixa: string | null;
  /** ESPERADO (contrato v2): round(valor_bruto × fator, 2). É o que soma na grade (só em a_receber). Em 'sem_base' o
   *  banco manda NULL e aqui fica 0 — a tela lê a situação e escreve "sem base medida", nunca este número. */
  valor: number;
  situacao: SituacaoReceber;
  /** Bloco 1: dia da venda. Bloco 2: vencimento da cobrança (contrato do victor, 28/09). */
  origem_dia: string | null;
  /** Chave opaca. Bloco 2: UMA POR CONTRATO (e-mail|oferta), não por cobrança. Bloco 5: id do recebimento informado. */
  ref: string | null;
  rotulo: string | null;
  produto: string | null;
  /** Meses à frente (mês do corte = 1). */
  k: number | null;
  /** Bloco 1: vendas do dia. Blocos 2 a 8: [] (o detalhe do bloco 2 e dos blocos 3/4 tem outro formato — ver `pagas`
   *  e `projecao`). */
  detalhe: VendaDoDia[];
  /** Blocos 3 e 4 (z67): vendas projetadas desta data de caixa. Só na linha 'antecipacao' (a 'garantia' é a mesma
   *  venda e vem NULL → []). Outros blocos: []. */
  projecao: VendaProjetada[];
  /** Bloco 2: transações pagas do contrato como vieram NESTA linha. null = a linha não trouxe (o banco manda a lista
   *  UMA vez por contrato, na 1ª linha a_receber; na z66 vinha em todas). Leia sempre por `pagasPorContrato` (ref),
   *  nunca direto daqui. Outros blocos: []. */
  pagas: PagamentoContrato[] | null;
  /** Valor sem perda. Banco na versão antiga (sem a coluna): = valor. */
  valor_bruto: number;
  /** 1, ou (1 − perda)^k. Banco na versão antiga: 1. */
  fator: number;
  /** 'certo' | 'estimado' (reservado). NULL no banco antigo. */
  certeza: string | null;
  centro_custo: string | null;
  /** Porquê da linha, partes separadas por ' · '. NULL no banco antigo ou sem tratamento. */
  tratamento: string | null;
  /** Cenário que o banco devolveu. Banco antigo: 'base'. */
  cenario: string;
}

export const GRUPO_BLOCO_1 = 'Vendas já realizadas';
/** Ordem das linhas do bloco 2 na grade (a mesma da planilha). Grupo desconhecido vai para o fim, nunca some. */
export const GRUPOS_BLOCO_2 = [
  'Assinaturas Serviço Diamante',
  'Assinaturas Holding - Holding Masters',
  'Parcelas a vencer HM',
  'Parcelas a vencer Aurum',
  'Parcelas a vencer outros',
  'Outras assinaturas',
] as const;
/** Ordem das linhas do bloco 5 (recebimentos informados), a do contrato. Grupo desconhecido vai para o fim, nunca some. */
export const GRUPOS_BLOCO_5 = [
  'Renovações Diamante',
  'Renovações Aurum',
  'Serviço Diamante extras',
  'Outros recebimentos informados',
] as const;

/** Ordem das linhas do bloco 3 (vendas novas, z67). O bloco 4 tem um grupo por evento planejado (ordem alfabética). */
export const GRUPOS_BLOCO_3 = ['HM avulso', 'Holding Total', 'Outros produtos'] as const;
export const GRUPO_BLOCO_6 = 'Reserva de reembolso e chargeback';
export const GRUPO_BLOCO_8 = 'Informativo: acordos no board';

const GRUPOS_POR_BLOCO: Record<number, readonly string[]> = {
  1: [GRUPO_BLOCO_1], 2: GRUPOS_BLOCO_2, 3: GRUPOS_BLOCO_3, 5: GRUPOS_BLOCO_5, 6: [GRUPO_BLOCO_6],
};

// ─── Conversão (numeric do PostgREST pode chegar como texto) ────────────────
const num = (v: unknown): number => Number(v ?? 0) || 0;
const numOuNull = (v: unknown): number | null => (v == null || v === '' ? null : Number.isFinite(Number(v)) ? Number(v) : null);
const dia = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));

function lerLista(v: unknown): Record<string, unknown>[] {
  let bruto: unknown = v;
  if (typeof bruto === 'string') {
    try { bruto = JSON.parse(bruto); } catch { return []; }
  }
  if (!Array.isArray(bruto)) return [];
  return bruto.map((x) => (x ?? {}) as Record<string, unknown>);
}

function lerDetalhe(v: unknown): VendaDoDia[] {
  return lerLista(v).map((x) => {
    const o = x;
    return {
      transacao: String(o.transacao ?? ''),
      produto: o.produto == null ? null : String(o.produto),
      nome: o.nome == null ? null : String(o.nome),
      liquido: num(o.liquido),
    };
  });
}

function lerProjecao(v: unknown): VendaProjetada[] {
  return lerLista(v).map((o) => ({
    dia: dia(o.dia),
    valor_venda: num(o.valor_venda),
    base: o.base == null || o.base === '' ? null : String(o.base),
  }));
}

/** `detalhe` NULL (ou ausente) = a linha não trouxe a lista → null; `[]` = o contrato não tem transação paga. */
function lerPagas(v: unknown): PagamentoContrato[] | null {
  if (v == null || v === '') return null;
  return lerLista(v).map((o) => ({
    transacao: String(o.transacao ?? ''),
    n: numOuNull(o.n),
    dia: dia(o.dia),
    liquido: num(o.liquido),
  }));
}

const textoOuNull = (v: unknown): string | null => (v == null || v === '' ? null : String(v));

/**
 * Tolerante à versão do banco: durante o deploy a RPC pode ainda ser a da z63 (sem as 6 colunas do contrato v2).
 * Coluna ausente (chave inexistente ou NULL) → valor_bruto = valor, fator = 1, cenário 'base'. Nada é inventado.
 */
export function normalizarLinhaReceber(r: Record<string, unknown>): LinhaReceber {
  const situacao = String(r.situacao ?? '') as SituacaoReceber;
  const componente = String(r.componente ?? '') as ComponenteReceber;
  const bloco = num(r.bloco);
  const valor = num(r.valor);
  const fator = numOuNull(r.fator);
  return {
    bloco,
    grupo: String(r.grupo ?? ''),
    // Valor fora do contrato é mantido cru e NÃO vira a_receber: não soma e a lista mostra o valor como veio.
    situacao,
    componente,
    data_caixa: dia(r.data_caixa),
    valor,
    origem_dia: dia(r.origem_dia),
    ref: r.ref == null ? null : String(r.ref),
    rotulo: r.rotulo == null ? null : String(r.rotulo),
    produto: r.produto == null ? null : String(r.produto),
    k: numOuNull(r.k),
    detalhe: bloco === 2 || bloco === 3 || bloco === 4 ? [] : lerDetalhe(r.detalhe),
    projecao: bloco === 3 || bloco === 4 ? lerProjecao(r.detalhe) : [],
    pagas: bloco === 2 ? lerPagas(r.detalhe) : [],
    valor_bruto: r.valor_bruto == null || r.valor_bruto === '' ? valor : num(r.valor_bruto),
    fator: fator == null ? 1 : fator,
    certeza: textoOuNull(r.certeza),
    centro_custo: textoOuNull(r.centro_custo),
    tratamento: textoOuNull(r.tratamento),
    cenario: textoOuNull(r.cenario) ?? 'base',
  };
}

/**
 * Transações pagas por contrato (bloco 2, chave = ref). Montado de QUALQUER linha que traga a lista: o banco novo manda
 * só na 1ª linha a_receber do contrato (NULL nas demais); a z66 mandava em todas (a 1ª vence, são iguais). Contrato
 * sem nenhuma linha com a lista não entra no mapa (a tela diz "nenhuma transação paga").
 */
export function pagasPorContrato(linhas: LinhaReceber[]): Map<string, PagamentoContrato[]> {
  const m = new Map<string, PagamentoContrato[]>();
  for (const l of linhas) {
    if (l.bloco !== 2 || l.ref == null || l.pagas == null || m.has(l.ref)) continue;
    m.set(l.ref, l.pagas);
  }
  return m;
}

/** Linha com perda aplicada (fator < 1): a tela mostra bruto e esperado lado a lado. */
export const temPerda = (l: Pick<LinhaReceber, 'fator'>): boolean => l.fator < 1;

// ─── Calendário (UTC puro, sem fuso) ────────────────────────────────────────
const ms = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);
const DIA = 86_400_000;

/** Último dia do mês de `iso` (YYYY-MM-DD). */
export function fimDoMes(d: string): string {
  const [y, m] = d.split('-').map(Number);
  return iso(Date.UTC(y, m, 0));
}

export interface Semana {
  /** 1, 2, 3… na ordem do período. */
  n: number;
  inicio: string;
  fim: string;
  /** YYYY-MM — a semana nunca cruza mês. */
  mes: string;
}

/**
 * Pedaço de semana com MENOS dias que isto é unido à semana vizinha do mesmo mês.
 * Regra da planilha do financeiro (aba Fluxo Semanal): "Semanas de segunda a domingo, cortadas na virada do mês
 * para o resumo mensal fechar (S1 = 24 a 30/09; pedaços de 1 dia foram unidos à semana vizinha)".
 * O limiar 4 reproduz os 15 limites da planilha sem exceção: 28–30/09 (3 dias) entra na S1, 01/11 e 30/11 (1 dia)
 * entram nas vizinhas; 24–27/09, 01–04/10 e 28–31/12 (4 dias) ficam.
 */
export const DIAS_MINIMOS_SEMANA = 4;

const diasEntre = (inicio: string, fim: string) => (ms(fim) - ms(inicio)) / DIA + 1;

/**
 * Semanas de `inicio` a `fim` (inclusive): segunda a domingo, cortadas na virada do mês e nas pontas do período.
 * Depois, dentro de cada mês, o pedaço com menos de DIAS_MINIMOS_SEMANA dias é unido à semana vizinha DO MESMO MÊS:
 * no início do mês, à seguinte; no fim, à anterior. Mês com um pedaço só fica como está. Nenhuma semana cruza mês.
 */
export function semanas(inicio: string, fim: string): Semana[] {
  const a = ms(inicio);
  const b = ms(fim);
  if (!(a <= b)) return [];
  // 1) pedaços seg–dom cortados no mês e no início do período
  const pedacos: { inicio: string; fim: string; mes: string }[] = [];
  for (let t = a; t <= b; t += DIA) {
    const d = new Date(t);
    const dia = iso(t);
    const ultimo = pedacos[pedacos.length - 1];
    if (!ultimo || d.getUTCDay() === 1 || d.getUTCDate() === 1) pedacos.push({ inicio: dia, fim: dia, mes: dia.slice(0, 7) });
    else ultimo.fim = dia;
  }
  // 2) une os pedaços curtos à vizinha do mesmo mês
  const out: { inicio: string; fim: string; mes: string }[] = [];
  for (let i = 0; i < pedacos.length;) {
    let j = i;
    while (j + 1 < pedacos.length && pedacos[j + 1].mes === pedacos[i].mes) j++;
    const doMes = pedacos.slice(i, j + 1).map((x) => ({ ...x }));
    if (doMes.length > 1 && diasEntre(doMes[0].inicio, doMes[0].fim) < DIAS_MINIMOS_SEMANA) {
      doMes[1].inicio = doMes[0].inicio;
      doMes.shift();
    }
    const u = doMes.length - 1;
    if (u > 0 && diasEntre(doMes[u].inicio, doMes[u].fim) < DIAS_MINIMOS_SEMANA) {
      doMes[u - 1].fim = doMes[u].fim;
      doMes.pop();
    }
    out.push(...doMes);
    i = j + 1;
  }
  return out.map((x, i) => ({ n: i + 1, ...x }));
}

/** Índice da semana que contém `d`, ou -1 fora do período. */
export function semanaDe(sems: Semana[], d: string): number {
  for (let i = 0; i < sems.length; i++) if (d >= sems[i].inicio && d <= sems[i].fim) return i;
  return -1;
}

// ─── Agregação semana × bloco × grupo (só a_receber) ────────────────────────
// Soma `valor` (o ESPERADO do contrato v2). O bruto (sem perda) anda junto só para a tela mostrar "bruto × esperado"
// onde houver perda — nunca entra no total.
export interface LinhaGrade {
  bloco: number;
  grupo: string;
  porSemana: number[];
  total: number;
  /** Sem perda (valor_bruto). Igual a porSemana onde o fator é 1. */
  brutoPorSemana: number[];
  brutoTotal: number;
}

export interface MesGrade {
  mes: string;
  /** Índices das semanas do mês (contíguos). */
  semanas: number[];
  total: number;
  brutoTotal: number;
  acumulado: number;
}

export interface GradeReceber {
  semanas: Semana[];
  linhas: LinhaGrade[];
  /** Subtotal por bloco, por semana (bloco 2 tem vários grupos). */
  blocos: { bloco: number; porSemana: number[]; total: number; brutoPorSemana: number[]; brutoTotal: number }[];
  totalPorSemana: number[];
  brutoPorSemana: number[];
  acumuladoPorSemana: number[];
  meses: MesGrade[];
  total: number;
  brutoTotal: number;
  /** a_receber sem data de caixa (cálculo de recebimento desligado): não entra na grade, mas não some em silêncio. */
  semDataCaixa: { linhas: number; valor: number };
  /** a_receber com data_caixa fora do período: não entra na grade, mas não some em silêncio. */
  foraDoPeriodo: { linhas: number; valor: number };
  /** Subtotais das duas seções (a soma dos dois = totalPorSemana). */
  certoPorSemana: number[];
  certoTotal: number;
  estimadoPorSemana: number[];
  estimadoTotal: number;
  /** Grupos estimados sem base (situacao 'sem_base'): aparecem como "sem base medida", fora da soma. */
  semBase: { bloco: number; grupo: string; tratamento: string | null }[];
  /** Bloco 8 (situacao 'informativo'): mesma régua de semanas, FORA de toda soma. NULL = nenhuma linha. */
  informativo: {
    grupo: string; porSemana: number[]; total: number; linhas: number; foraDoPeriodo: { linhas: number; valor: number };
  } | null;
}

/** Soma em centavos: 0,1 + 0,2 não vira 0,30000000000000004 no total da semana. */
const c = (v: number) => Math.round(v * 100);
const r = (centavos: number) => centavos / 100;

/** Posição do grupo dentro do bloco; bloco sem ordem conhecida ou grupo desconhecido: fim (ordem alfabética entre eles). */
function ordemGrupo(bloco: number, grupo: string): number {
  const ordem = GRUPOS_POR_BLOCO[bloco] ?? [];
  const i = ordem.indexOf(grupo);
  return i === -1 ? ordem.length : i;
}

export function agregarReceber(linhas: LinhaReceber[], inicio: string, fim: string): GradeReceber {
  const sems = semanas(inicio, fim);
  const n = sems.length;
  const porGrupo = new Map<string, { bloco: number; grupo: string; cs: number[]; bs: number[] }>();
  let foraN = 0;
  let foraC = 0;
  let semDataN = 0;
  let semDataC = 0;
  const semBase: GradeReceber['semBase'] = [];
  let info: { grupo: string; cs: number[]; n: number; foraN: number; foraC: number } | null = null;
  for (const l of linhas) {
    if (l.situacao === 'sem_base') {
      if (!semBase.some((x) => x.bloco === l.bloco && x.grupo === l.grupo)) semBase.push({ bloco: l.bloco, grupo: l.grupo, tratamento: l.tratamento });
      continue;
    }
    if (l.situacao === 'informativo') {
      if (!info) info = { grupo: l.grupo, cs: new Array(n).fill(0), n: 0, foraN: 0, foraC: 0 };
      info.n += 1;
      const i = l.data_caixa ? semanaDe(sems, l.data_caixa) : -1;
      if (i === -1) { info.foraN += 1; info.foraC += c(l.valor); } else info.cs[i] += c(l.valor);
      continue;
    }
    if (l.situacao !== 'a_receber') continue;
    if (!l.data_caixa) { semDataN += 1; semDataC += c(l.valor); continue; }
    const i = semanaDe(sems, l.data_caixa);
    if (i === -1) { foraN += 1; foraC += c(l.valor); continue; }
    const chave = `${l.bloco}\u0000${l.grupo}`;
    let g = porGrupo.get(chave);
    if (!g) { g = { bloco: l.bloco, grupo: l.grupo, cs: new Array(n).fill(0), bs: new Array(n).fill(0) }; porGrupo.set(chave, g); }
    g.cs[i] += c(l.valor);
    g.bs[i] += c(l.valor_bruto);
  }
  const grupos = [...porGrupo.values()].sort((a, b) =>
    a.bloco - b.bloco || ordemGrupo(a.bloco, a.grupo) - ordemGrupo(b.bloco, b.grupo) || a.grupo.localeCompare(b.grupo, 'pt-BR'));

  const totalC = new Array(n).fill(0);
  const totalB = new Array(n).fill(0);
  const certoC = new Array(n).fill(0);
  const estC = new Array(n).fill(0);
  const porBloco = new Map<number, { cs: number[]; bs: number[] }>();
  for (const g of grupos) {
    let b = porBloco.get(g.bloco);
    if (!b) { b = { cs: new Array(n).fill(0), bs: new Array(n).fill(0) }; porBloco.set(g.bloco, b); }
    const secao = secaoDoBloco(g.bloco) === 'estimado' ? estC : certoC;
    for (let i = 0; i < n; i++) { totalC[i] += g.cs[i]; b.cs[i] += g.cs[i]; totalB[i] += g.bs[i]; b.bs[i] += g.bs[i]; secao[i] += g.cs[i]; }
  }
  const acumC: number[] = [];
  totalC.reduce((s, v, i) => (acumC[i] = s + v), 0);

  const meses: MesGrade[] = [];
  for (let i = 0; i < n; i++) {
    const ultimo = meses[meses.length - 1];
    if (ultimo && ultimo.mes === sems[i].mes) { ultimo.semanas.push(i); ultimo.total += totalC[i]; ultimo.brutoTotal += totalB[i]; }
    else meses.push({ mes: sems[i].mes, semanas: [i], total: totalC[i], brutoTotal: totalB[i], acumulado: 0 });
  }
  let acM = 0;
  for (const m of meses) { acM += m.total; m.acumulado = r(acM); m.total = r(m.total); m.brutoTotal = r(m.brutoTotal); }

  const soma = (xs: number[]) => xs.reduce((s, v) => s + v, 0);
  return {
    semanas: sems,
    linhas: grupos.map((g) => ({
      bloco: g.bloco, grupo: g.grupo, porSemana: g.cs.map(r), total: r(soma(g.cs)), brutoPorSemana: g.bs.map(r), brutoTotal: r(soma(g.bs)),
    })),
    blocos: [...porBloco.entries()].sort((a, b) => a[0] - b[0]).map(([bloco, x]) => ({
      bloco, porSemana: x.cs.map(r), total: r(soma(x.cs)), brutoPorSemana: x.bs.map(r), brutoTotal: r(soma(x.bs)),
    })),
    totalPorSemana: totalC.map(r),
    brutoPorSemana: totalB.map(r),
    acumuladoPorSemana: acumC.map(r),
    meses,
    total: r(soma(totalC)),
    brutoTotal: r(soma(totalB)),
    semDataCaixa: { linhas: semDataN, valor: r(semDataC) },
    foraDoPeriodo: { linhas: foraN, valor: r(foraC) },
    certoPorSemana: certoC.map(r),
    certoTotal: r(soma(certoC)),
    estimadoPorSemana: estC.map(r),
    estimadoTotal: r(soma(estC)),
    semBase: semBase.sort((a, b) => a.bloco - b.bloco || ordemGrupo(a.bloco, a.grupo) - ordemGrupo(b.bloco, b.grupo)),
    informativo: info && {
      grupo: info.grupo, porSemana: info.cs.map(r), total: r(soma(info.cs)), linhas: info.n,
      foraDoPeriodo: { linhas: info.foraN, valor: r(info.foraC) },
    },
  };
}

/**
 * Período da grade: de hoje (ou da 1ª data a receber, se anterior) até o fim do mês da última data a receber.
 * Nada a receber → só o mês corrente.
 */
export function periodoReceber(linhas: LinhaReceber[], hojeISO: string): { inicio: string; fim: string } {
  let min = hojeISO;
  let max = hojeISO;
  for (const l of linhas) {
    if (l.situacao !== 'a_receber' || !l.data_caixa) continue;
    if (l.data_caixa < min) min = l.data_caixa;
    if (l.data_caixa > max) max = l.data_caixa;
  }
  return { inicio: min, fim: fimDoMes(max) };
}

/**
 * Cálculo de recebimento desligado no banco (premissa de recebimento inativa): o bloco 1 vem vazio e as cobranças
 * a receber do bloco 2 vêm sem data de caixa. A grade sairia toda zerada — zero que não é dado. A tela avisa.
 */
export function recebimentoDesligado(linhas: LinhaReceber[]): boolean {
  return !linhas.some((l) => l.bloco === 1)
    && linhas.some((l) => l.bloco === 2 && l.situacao === 'a_receber' && l.data_caixa == null);
}

/** Quem compõe uma célula (grupo × semana), SEM consulta nova: as linhas a_receber daquele grupo naquela semana
 * (no bloco informativo, as linhas 'informativo' — o bloco inteiro é fora da soma). */
export function composicaoDaCelula(
  linhas: LinhaReceber[], sem: Semana | null, bloco: number, grupo: string,
): LinhaReceber[] {
  const situacao: SituacaoReceber = bloco === BLOCO_INFORMATIVO ? 'informativo' : 'a_receber';
  return linhas
    .filter((l) => l.situacao === situacao && l.bloco === bloco && l.grupo === grupo
      && l.data_caixa != null && (sem == null || (l.data_caixa >= sem.inicio && l.data_caixa <= sem.fim)))
    .sort((a, b) => (a.data_caixa ?? '').localeCompare(b.data_caixa ?? '') || (a.rotulo ?? '').localeCompare(b.rotulo ?? '', 'pt-BR'));
}

// ─── Recorrências (bloco 2, todas as situações) ─────────────────────────────
export interface CobrancaRecorrente {
  ref: string | null;
  grupo: string;
  rotulo: string | null;
  produto: string | null;
  /** Vencimento da cobrança (origem_dia; sem ele, a 1ª data de caixa). */
  prevista: string;
  /** Dias em que as partes caem no caixa. Vazio em realizada/em_atraso_fora (componente cheio, data NULL). */
  caixa: string[];
  /** Valor da cobrança SEM perda (soma de valor_bruto das partes). */
  valor: number;
  /** Esperado no cenário (soma de valor das partes). Igual a `valor` sem perda. */
  esperado: number;
  situacao: SituacaoReceber;
  k: number | null;
}

/**
 * Uma cobrança = ref + vencimento (origem_dia) + situação. Contrato do victor (28/09): no bloco 2 a `ref` é UMA POR
 * CONTRATO (e-mail|oferta, opaca) — sozinha juntaria todas as mensalidades do contrato numa linha. As partes da mesma
 * cobrança (antecipação + garantia) somam na mesma linha. Sem ref ou sem vencimento, cada linha é uma cobrança.
 */
export function cobrancasRecorrentes(linhas: LinhaReceber[]): CobrancaRecorrente[] {
  const mapa = new Map<string, CobrancaRecorrente & { cents: number; centsEsp: number }>();
  let semRef = 0;
  for (const l of linhas) {
    if (l.bloco !== 2) continue;
    const chave = l.ref != null && l.origem_dia ? `${l.ref}\u0000${l.origem_dia}\u0000${l.situacao}` : `\u0001${semRef++}`;
    let x = mapa.get(chave);
    if (!x) {
      x = {
        ref: l.ref, grupo: l.grupo, rotulo: l.rotulo, produto: l.produto, prevista: l.origem_dia ?? l.data_caixa ?? '',
        caixa: [], valor: 0, esperado: 0, cents: 0, centsEsp: 0, situacao: l.situacao, k: l.k,
      };
      mapa.set(chave, x);
    }
    x.cents += c(l.valor_bruto);
    x.centsEsp += c(l.valor);
    if (l.data_caixa && !x.caixa.includes(l.data_caixa)) x.caixa.push(l.data_caixa);
    if (!l.origem_dia && l.data_caixa && (!x.prevista || l.data_caixa < x.prevista)) x.prevista = l.data_caixa;
  }
  return [...mapa.values()]
    .map(({ cents, centsEsp, ...x }) => ({ ...x, valor: r(cents), esperado: r(centsEsp), caixa: x.caixa.sort() }))
    .sort((a, b) => a.prevista.localeCompare(b.prevista) || (a.rotulo ?? '').localeCompare(b.rotulo ?? '', 'pt-BR'));
}
