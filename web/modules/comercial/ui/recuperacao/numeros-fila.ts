// Números da fila de recuperação (faixa do topo e contadores das faixas A–D). Puro e testável.
import type { FaixaScore, ItemFila } from '../../domain/types';
import { encerrado } from './ordem-fila';

export const FAIXAS: FaixaScore[] = ['A', 'B', 'C', 'D'];

export interface NumerosFila {
  total: number;
  /** Ainda em trabalho (nem ganho, nem saída). */
  emTrabalho: number;
  ganhos: number;
  /** Ganhos ÷ total da fila, em %. */
  taxa: number;
  /** Responderam, ficaram sem retorno e ainda estão "A abordar". */
  semRetorno: number;
  porFaixa: Record<FaixaScore, { total: number; aAbordar: number }>;
}

export function numerosFila(itens: Pick<ItemFila, 'faixa' | 'status' | 'sinais'>[]): NumerosFila {
  const porFaixa = Object.fromEntries(FAIXAS.map((f) => [f, { total: 0, aAbordar: 0 }])) as NumerosFila['porFaixa'];
  let ganhos = 0;
  let semRetorno = 0;
  let emTrabalho = 0;
  for (const i of itens) {
    porFaixa[i.faixa].total += 1;
    if (i.status === 'a_abordar') porFaixa[i.faixa].aAbordar += 1;
    if (i.status === 'ganho') ganhos += 1;
    if (!encerrado(i.status)) emTrabalho += 1;
    if (i.status === 'a_abordar' && i.sinais.includes('respondeu_sem_retorno')) semRetorno += 1;
  }
  return { total: itens.length, emTrabalho, ganhos, taxa: itens.length ? (ganhos / itens.length) * 100 : 0, semRetorno, porFaixa };
}
