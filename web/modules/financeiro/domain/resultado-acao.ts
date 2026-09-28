// Resultado por ação/evento do Programa (João, 28/09: "no evento X a gente ofertou X, teve retorno X, as pessoas
// compraram no evento X"). Soma os cards do board pela ação de origem (fin.vw_acao_card). Só o que o board já sabe:
// quem entrou, quantos pagaram, quanto já entrou e quanto falta — cancelado/reembolsado não entra no "a receber".
import type { StatusFinanceiro } from './types';

export interface CardDaAcao {
  acaoNome: string | null;
  acaoData: string | null;
  status: StatusFinanceiro;
  pago: number | null;
  saldo: number | null;
}

export interface ResultadoAcao {
  acao: string;
  data: string | null;
  pessoas: number;
  pagaram: number;
  quitados: number;
  saidas: number;
  recebido: number;
  aReceber: number;
}

const MORTO: StatusFinanceiro[] = ['cancelado', 'reembolsado'];

export function resultadoPorAcao(cards: CardDaAcao[]): ResultadoAcao[] {
  const mapa = new Map<string, ResultadoAcao>();
  for (const c of cards) {
    const acao = c.acaoNome ?? 'Sem ação identificada';
    const r = mapa.get(acao) ?? { acao, data: null, pessoas: 0, pagaram: 0, quitados: 0, saidas: 0, recebido: 0, aReceber: 0 };
    r.pessoas += 1;
    const pago = Number(c.pago) || 0;
    if (pago > 0) r.pagaram += 1;
    if (c.status === 'quitado') r.quitados += 1;
    if (MORTO.includes(c.status)) r.saidas += 1;
    r.recebido += pago;
    if (!MORTO.includes(c.status)) r.aReceber += Math.max(0, Number(c.saldo) || 0);
    if (c.acaoData && (r.data == null || c.acaoData < r.data)) r.data = c.acaoData;
    mapa.set(acao, r);
  }
  return [...mapa.values()].sort((a, b) => (a.data ?? '9999').localeCompare(b.data ?? '9999') || b.pessoas - a.pessoas);
}
