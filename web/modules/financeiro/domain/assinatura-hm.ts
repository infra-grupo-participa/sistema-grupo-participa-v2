// Mensalidade do HM antigo (produto Hotmart 3507214 — definição do Marcio, 28/09/2026). Função PURA, sem I/O.
//
// Decisões do Marcio (28/09):
//   1. fica à parte no card (bloco "Assinatura HM"); pago e saldo do Programa não mudam;
//   2. quem paga/pagou e não tem card vai para uma lista própria, com a turma de origem (não ganha card);
//   3. o atraso da mensalidade é separado do "devendo" do Programa: aparece no bloco Assinatura, só dos últimos 120 dias.
// Fonte: 20260928z52 — fn_fin_board_assinatura_hm (1 chamada por abertura do board) e fn_fin_assinatura_hm_sem_card.
// `pessoa_chave` = fin.chave_opaca(fin.identidade.pessoa_chave), a MESMA chave de BoardHotmart.pessoa_chave.
import type { BoardHotmart } from './hotmart';
import { fmtMesAno } from './board-hotmart';

/** fn_fin_board_assinatura_hm — uma linha por pessoa que tem cobrança da mensalidade. Sem dado pessoal. */
export interface AssinaturaHMBoard {
  pessoa_chave: string;
  mensalidades_pagas: number;
  pago: number;
  primeira: string | null;
  ultima_paga: string | null;
  /** Última mensalidade paga há ≤ 45 dias. */
  ainda_paga: boolean;
  /** Mensalidades vencidas e não pagas nos últimos 120 dias (a mesma deduplicação de fin.parcelas_devidas). */
  atraso_120d_n: number;
  atraso_120d_valor: number;
  turma_origem: string | null;
}

/** fn_fin_assinatura_hm_sem_card — pagou mensalidade e não tem card (nem HM nem Aurum). */
export interface AssinaturaHMSemCard {
  pessoa_chave: string;
  nome: string | null;
  emails: string[];
  /** Mascarado pelo banco (CPF ···1234) para quem não tem gp_pode_ver_cpf(). */
  documento: string | null;
  telefone: string | null;
  turma_origem: string | null;
  /** 'calendário' | 'cadastro' | 'calendário e cadastro' | 'sem origem'. */
  origem_regra: string | null;
  turma_calendario: string | null;
  turma_cadastro: string | null;
  primeira: string | null;
  ultima_paga: string | null;
  mensalidades_pagas: number;
  pago: number;
  ainda_paga: boolean;
  atraso_120d_n: number;
  atraso_120d_valor: number;
}

/** Colunas das RPCs — o teste de contrato confere contra o RETURNS TABLE da z52. */
export const COLUNAS_ASSINATURA_HM_BOARD = [
  'pessoa_chave', 'mensalidades_pagas', 'pago', 'primeira', 'ultima_paga', 'ainda_paga',
  'atraso_120d_n', 'atraso_120d_valor', 'turma_origem',
] as const satisfies readonly (keyof AssinaturaHMBoard)[];

export const COLUNAS_ASSINATURA_HM_SEM_CARD = [
  'pessoa_chave', 'nome', 'emails', 'documento', 'telefone',
  'turma_origem', 'origem_regra', 'turma_calendario', 'turma_cadastro',
  'primeira', 'ultima_paga', 'mensalidades_pagas', 'pago', 'ainda_paga',
  'atraso_120d_n', 'atraso_120d_valor',
] as const satisfies readonly (keyof AssinaturaHMSemCard)[];

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

/** Numeric/int do Postgres pode chegar como string pelo PostgREST. */
export function normalizarAssinaturaBoard(r: AssinaturaHMBoard): AssinaturaHMBoard {
  return {
    ...r,
    mensalidades_pagas: num(r.mensalidades_pagas),
    pago: num(r.pago),
    ainda_paga: r.ainda_paga === true,
    atraso_120d_n: num(r.atraso_120d_n),
    atraso_120d_valor: num(r.atraso_120d_valor),
  };
}

export function normalizarAssinaturaSemCard(r: AssinaturaHMSemCard): AssinaturaHMSemCard {
  return {
    ...r,
    emails: Array.isArray(r.emails) ? r.emails : [],
    mensalidades_pagas: num(r.mensalidades_pagas),
    pago: num(r.pago),
    ainda_paga: r.ainda_paga === true,
    atraso_120d_n: num(r.atraso_120d_n),
    atraso_120d_valor: num(r.atraso_120d_valor),
  };
}

/** Mapa pessoa_chave → linha normalizada. */
export function indexarAssinaturaHM(linhas: readonly AssinaturaHMBoard[]): Map<string, AssinaturaHMBoard> {
  const m = new Map<string, AssinaturaHMBoard>();
  for (const l of linhas) if (l.pessoa_chave) m.set(l.pessoa_chave, normalizarAssinaturaBoard(l));
  return m;
}

/**
 * Mensalidade da pessoa deste card, em card de QUALQUER produto: o mapa só tem quem paga/pagou o 3507214, e a lista
 * sem card exclui quem tem card HM ou Aurum — exigir card HM aqui fazia a pessoa com card Aurum sumir de tudo
 * (5 pessoas, P2 da z52; reprovação do João, 28/09). Só com pessoa identificada: card sem pessoa_chave nunca casa.
 */
export function assinaturaDoCard(
  hm: BoardHotmart | null | undefined, mapa: ReadonlyMap<string, AssinaturaHMBoard> | null | undefined,
): AssinaturaHMBoard | null {
  if (!mapa || !hm || !hm.encontrado || !hm.pessoa_chave) return null;
  return mapa.get(hm.pessoa_chave) ?? null;
}

/** "Assinatura em dia" (z52): paga nos últimos 45 dias e nenhuma mensalidade em atraso nos últimos 120. */
export function assinaturaEmDia(a: Pick<AssinaturaHMBoard, 'ainda_paga' | 'atraso_120d_n'>): boolean {
  return a.ainda_paga && a.atraso_120d_n === 0;
}

export type SituacaoAssinatura = 'ativa' | 'em_atraso' | 'encerrada';
export const ROTULO_SITUACAO_ASSINATURA: Record<SituacaoAssinatura, string> = {
  ativa: 'ativa', em_atraso: 'em atraso', encerrada: 'encerrada',
};

/** Resumo do bloco "Assinatura HM" do card/ficha. */
export interface ResumoAssinaturaCard {
  mensalidades: number;
  valor: number;
  de: string | null;
  ate: string | null;
  /** null = sem como decidir (camada nova não carregou e o board não diz). */
  situacao: SituacaoAssinatura | null;
  atrasoN: number;
  atrasoValor: number;
  turmaOrigem: string | null;
}

/**
 * Junta o que o board já mostra (fn_fin_board_hotmart, CTE `ass`) com a mensalidade da z52.
 * Quantidade/valor/período: os do board quando ele tem (não muda o que já aparecia); senão os da z52.
 * Situação e atraso: da z52 — depois da seção 4 da z52, `assinatura_ativa` do board deixa de ver a
 * mensalidade atrasada. Sem a z52 (carregando/erro), cai no `assinatura_ativa` antigo e não mostra atraso.
 * null quando não há mensalidade paga nem atraso a mostrar.
 */
export function resumoAssinaturaCard(
  hm: BoardHotmart | null | undefined, a: AssinaturaHMBoard | null | undefined,
): ResumoAssinaturaCard | null {
  const doBoard = !!hm && hm.encontrado && num(hm.assinatura_mensalidades) > 0;
  const temNova = !!a && (a.mensalidades_pagas > 0 || a.atraso_120d_n > 0);
  if (!doBoard && !temNova) return null;
  const situacao: SituacaoAssinatura | null = a
    ? (assinaturaEmDia(a) ? 'ativa' : a.atraso_120d_n > 0 ? 'em_atraso' : 'encerrada')
    : hm?.assinatura_ativa == null ? null : hm.assinatura_ativa ? 'ativa' : 'encerrada';
  return {
    mensalidades: doBoard ? num(hm!.assinatura_mensalidades) : a!.mensalidades_pagas,
    valor: doBoard ? num(hm!.assinatura_valor) : a!.pago,
    de: doBoard ? hm!.assinatura_de ?? null : a!.primeira,
    ate: doBoard ? hm!.assinatura_ate ?? null : a!.ultima_paga,
    situacao,
    atrasoN: a?.atraso_120d_n ?? 0,
    atrasoValor: a?.atraso_120d_valor ?? 0,
    turmaOrigem: a?.turma_origem ?? null,
  };
}

/** Linha curta do card: "Assinatura HM: 12 × · R$ 23.964 · até 09/2026" (ou "nenhuma paga" quando só há atraso). */
export function linhaResumoAssinatura(r: ResumoAssinaturaCard, fmtValor: (n: number) => string): string {
  if (r.mensalidades <= 0) return 'Assinatura HM: nenhuma paga';
  const ate = fmtMesAno(r.ate);
  return `Assinatura HM: ${r.mensalidades} × · ${fmtValor(r.valor)}${ate ? ` · até ${ate}` : ''}`;
}

/** "mensalidade em atraso: 2 · R$ 3.994" — null sem atraso. */
export function linhaAtrasoMensalidade(r: Pick<ResumoAssinaturaCard, 'atrasoN' | 'atrasoValor'> | null, fmtValor: (n: number) => string): string | null {
  if (!r || r.atrasoN <= 0) return null;
  return `mensalidade em atraso: ${r.atrasoN} · ${fmtValor(r.atrasoValor)}`;
}

export interface TotaisAssinaturaSemCard {
  pessoas: number;
  pago: number;
  aindaPagam: number;
  comAtraso: number;
  atrasoValor: number;
}

export function totaisAssinaturaSemCard(lista: readonly AssinaturaHMSemCard[]): TotaisAssinaturaSemCard {
  const t: TotaisAssinaturaSemCard = { pessoas: 0, pago: 0, aindaPagam: 0, comAtraso: 0, atrasoValor: 0 };
  for (const l of lista) {
    t.pessoas += 1;
    t.pago += num(l.pago);
    if (l.ainda_paga) t.aindaPagam += 1;
    if (num(l.atraso_120d_n) > 0) { t.comAtraso += 1; t.atrasoValor += num(l.atraso_120d_valor); }
  }
  return t;
}
