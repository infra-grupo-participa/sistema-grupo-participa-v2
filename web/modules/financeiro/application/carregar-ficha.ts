// Caso de uso: ficha do aluno (drawer) — histórico financeiro completo do
// comprador, para responder "por que ainda não pagou" e o que cobrar do
// comercial. Reusa o card já carregado no board (não busca de novo).
import type { CompraHistorico, Lancamento, Cobranca, InteracaoAtivacao } from '../domain/types';
import type { FinanceiroRepository } from './ports';

export interface Ficha {
  extrato: Lancamento[];
  compras: CompraHistorico[];
  cobrancas: Cobranca[];
  historicoAtivacao: InteracaoAtivacao[];
}

/** Carrega extrato + compras Hotmart + histórico de cobrança + histórico do
 *  comercial (ativação) de um comprador. */
export async function carregarFicha(
  repo: FinanceiroRepository,
  compradorId: string,
  contatoHmId: string,
): Promise<Ficha> {
  const [extrato, compras, cobrancas, historicoAtivacao] = await Promise.all([
    repo.loadExtrato(compradorId),
    repo.loadComprasAluno(compradorId),
    repo.loadCobrancas(contatoHmId),
    repo.loadHistoricoAtivacao(contatoHmId),
  ]);
  return { extrato, compras, cobrancas, historicoAtivacao };
}
