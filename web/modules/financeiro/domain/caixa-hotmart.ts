// Faturamento · Caixa Hotmart (F6, z68): quanto já caiu, quanto está retido, quanto custou antecipar.
//
// Os valores e as DATAS vêm do SQL (fn_fin_caixa_hotmart → fin.recebimento sobre o calendário de caixa com feriados).
// Aqui só se normaliza (numeric chega como texto), se valida o período antes de consultar e se soma o que o banco
// não devolve pronto (o que do D+2 já caiu). Nenhuma regra de antecipação é recalculada no TS.

/** Situação do D+2 contra hoje (SQL: entra_em <= hoje). */
export type SituacaoD2 = 'recebido' | 'a_receber';
/** Situação do retido contra hoje (SQL: libera_em <= hoje). */
export type SituacaoRetido = 'liberado' | 'em_garantia';

export interface LinhaCaixaHotmart {
  dia: string;
  nVendas: number;
  liquido: number;
  retido: number;
  custoAntecipacao: number;
  entraRapido: number;
  /** null = sem premissa ativa para o dia (fin.recebimento sem linha). */
  entraEm: string | null;
  retidoALiberar: number;
  liberaEm: string | null;
  situacaoD2: SituacaoD2 | null;
  situacaoRetido: SituacaoRetido | null;
}

export interface TotaisCaixaHotmart {
  liquido: number;
  retido: number;
  custoAntecipacao: number;
  entraRapido: number;
  retidoALiberar: number;
  liquidoTotal: number;
  nVendas: number;
}

/** Janela máxima aceita pela RPC (22023 acima disso). Validada aqui para nem consultar. */
export const JANELA_MAX_DIAS_CAIXA = 400;

/**
 * Marco da antecipação: a vigência de fin.premissas_recebimento que liga o D+2 começa aqui (z68). Só é usado para
 * AVISAR — o cálculo está no banco. Se a vigência mudar no banco, este aviso tem de mudar junto.
 */
export const INICIO_ANTECIPACAO = '2026-06-01';

const num = (v: unknown) => Number(v ?? 0) || 0;
const dataOuNull = (v: unknown) => (typeof v === 'string' && v ? v.slice(0, 10) : null);

export function normalizarLinhaCaixa(r: Record<string, unknown>): LinhaCaixaHotmart {
  const entraEm = dataOuNull(r.entra_em);
  const liberaEm = dataOuNull(r.libera_em);
  // O SQL devolve 'a_receber'/'em_garantia' mesmo com data nula (null <= hoje cai no else): sem data, sem situação.
  const d2 = r.situacao_d2 === 'recebido' || r.situacao_d2 === 'a_receber' ? r.situacao_d2 : null;
  const ret = r.situacao_retido === 'liberado' || r.situacao_retido === 'em_garantia' ? r.situacao_retido : null;
  return {
    dia: String(r.dia ?? '').slice(0, 10),
    nVendas: num(r.n_vendas),
    liquido: num(r.liquido),
    retido: num(r.retido),
    custoAntecipacao: num(r.custo_antecipacao),
    entraRapido: num(r.entra_rapido),
    entraEm,
    retidoALiberar: num(r.retido_a_liberar),
    liberaEm,
    situacaoD2: entraEm ? d2 : null,
    situacaoRetido: liberaEm ? ret : null,
  };
}

export function normalizarTotaisCaixa(r: Record<string, unknown> | null | undefined): TotaisCaixaHotmart {
  const x = r ?? {};
  return {
    liquido: num(x.liquido),
    retido: num(x.retido),
    custoAntecipacao: num(x.custo_antecipacao),
    entraRapido: num(x.entra_rapido),
    retidoALiberar: num(x.retido_a_liberar),
    liquidoTotal: num(x.liquido_total),
    nVendas: num(x.n_vendas),
  };
}

/** Dia sem antecipação (antes do marco): tinha líquido e nada entrou em D+2 nem custou antecipar. Lido do dado. */
export function semAntecipacao(l: LinhaCaixaHotmart): boolean {
  return l.liquido > 0 && l.entraRapido === 0 && l.custoAntecipacao === 0;
}

const centavos = (v: number) => Math.round(v * 100) / 100;

/** O que os totais não trazem pronto: do D+2, quanto já caiu e quanto ainda cai; do retido, quanto já foi liberado. */
export interface DerivadoCaixa {
  jaCaiuD2: number;
  aCairD2: number;
  jaLiberado: number;
}

export function derivarCaixa(linhas: LinhaCaixaHotmart[], totais: TotaisCaixaHotmart): DerivadoCaixa {
  let jaCaiu = 0;
  let aCair = 0;
  for (const l of linhas) {
    if (l.situacaoD2 === 'recebido') jaCaiu += l.entraRapido;
    else if (l.situacaoD2 === 'a_receber') aCair += l.entraRapido;
  }
  return {
    jaCaiuD2: centavos(jaCaiu),
    aCairD2: centavos(aCair),
    jaLiberado: centavos(totais.retido - totais.retidoALiberar),
  };
}

function diaUTC(ymd: string): number {
  const [y, m, d] = ymd.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

export function somarDias(ymd: string, n: number): string {
  return new Date(diaUTC(ymd) + n * 86_400_000).toISOString().slice(0, 10);
}

export function diasEntre(de: string, ate: string): number {
  return Math.round((diaUTC(ate) - diaUTC(de)) / 86_400_000);
}

const ISO = /^\d{4}-\d{2}-\d{2}$/;

/** Mesmas regras da RPC (22023), para não consultar com período que o banco recusa. */
export function validarPeriodoCaixa(de: string, ate: string):
  { ok: true } | { ok: false; motivo: 'datas' | 'invertido' | 'janela' } {
  if (!ISO.test(de) || !ISO.test(ate)) return { ok: false, motivo: 'datas' };
  if (ate < de) return { ok: false, motivo: 'invertido' };
  if (diasEntre(de, ate) > JANELA_MAX_DIAS_CAIXA) return { ok: false, motivo: 'janela' };
  return { ok: true };
}

/** Padrão: desde o marco da antecipação até hoje; passou de 400 dias, recua o início para caber na janela. */
export function periodoPadraoCaixa(hojeISO: string): { de: string; ate: string } {
  const de = diasEntre(INICIO_ANTECIPACAO, hojeISO) > JANELA_MAX_DIAS_CAIXA
    ? somarDias(hojeISO, -JANELA_MAX_DIAS_CAIXA)
    : INICIO_ANTECIPACAO;
  return { de, ate: hojeISO };
}

/** O período pega vendas de antes do marco (sem antecipação): a tela avisa. */
export function pegaAntesDaAntecipacao(de: string): boolean {
  return de < INICIO_ANTECIPACAO;
}

export function chaveCaixa(de: string, ate: string): string {
  return `${de}|${ate}`;
}
