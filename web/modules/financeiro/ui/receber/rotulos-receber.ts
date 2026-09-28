// Rótulos da Previsão de caixa usados por mais de uma sub-aba (grade, composição, Base auditável e o CSV dela).
// Funções puras, sem React: a exportação lê a MESMA fonte que a tela.
import { BLOCOS_RECEBER, COMPONENTES_VENDA, GRADE_RECEBER, SITUACAO_RECEBER, BASE_AUDITAVEL } from './textos';

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
/** 'YYYY-MM' → 'set/2026'. */
export const rotuloMes = (m: string) => `${MESES[Number(m.slice(5, 7)) - 1]}/${m.slice(0, 4)}`;

export function rotuloComponente(c: string): string {
  if (c === 'antecipacao') return COMPONENTES_VENDA.antecipacao;
  if (c === 'garantia') return COMPONENTES_VENDA.garantia;
  if (c === 'cheio') return GRADE_RECEBER.componenteCheio;
  if (c === 'reserva') return COMPONENTES_VENDA.reserva;
  return c;
}

const ROTULOS_BLOCO: Record<number, string> = {
  1: BLOCOS_RECEBER.vendasRealizadas, 2: BLOCOS_RECEBER.assinaturasEParcelasFuturas, 3: BLOCOS_RECEBER.vendasNovas,
  4: BLOCOS_RECEBER.eventosPlanejados, 5: BLOCOS_RECEBER.recebimentosInformados, 6: BLOCOS_RECEBER.reserva,
  8: BLOCOS_RECEBER.informativoBoard,
};
export const rotuloBloco = (b: number) => ROTULOS_BLOCO[b] ?? `Bloco ${b}`;

/** As 6 situações do contrato v2. Valor fora do contrato sai cru (não disfarça). */
export function rotuloSituacaoLinha(s: string): string {
  if (s === 'a_receber') return SITUACAO_RECEBER.aReceber;
  if (s === 'realizada') return SITUACAO_RECEBER.realizada;
  if (s === 'em_atraso_fora') return SITUACAO_RECEBER.foraDaProjecao;
  if (s === 'coberta_informado') return SITUACAO_RECEBER.cobertaInformado;
  if (s === 'sem_base') return BASE_AUDITAVEL.situacaoSemBase;
  if (s === 'informativo') return BASE_AUDITAVEL.situacaoInformativo;
  return s;
}

/** 'certo' | 'estimado' | 'informativo' → texto; NULL (banco antigo) → travessão. */
export function rotuloCerteza(c: string | null): string {
  if (c == null) return '—';
  return BASE_AUDITAVEL.certezas[c] ?? c;
}
