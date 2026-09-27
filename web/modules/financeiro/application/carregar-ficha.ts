// Caso de uso: ficha do aluno (drawer) — histórico financeiro completo do
// comprador, para responder "por que ainda não pagou" e o que cobrar do
// comercial. Reusa o card já carregado no board (não busca de novo).
//
// 27/09: as compras gravadas pelo webhook (fn_fin_compras_aluno) saíram da ficha — a lista de pagamentos agora vem
// do espelho da Hotmart (fonte oficial, inclui o que o webhook perdeu) junto com os lançamentos do board
// (domain/pagamentos-ficha.ts). Buscar as duas seria a mesma venda duas vezes.
import type { Lancamento, Cobranca, InteracaoAtivacao } from '../domain/types';
import type { FinanceiroRepository } from './ports';

export interface Ficha {
  extrato: Lancamento[];
  cobrancas: Cobranca[];
  historicoAtivacao: InteracaoAtivacao[];
}

/** Carrega os lançamentos do board + histórico de cobrança + histórico do comercial (ativação) de um comprador. */
export async function carregarFicha(
  repo: FinanceiroRepository,
  compradorId: string,
  contatoHmId: string,
): Promise<Ficha> {
  const [extrato, cobrancas, historicoAtivacao] = await Promise.all([
    repo.loadExtrato(compradorId),
    repo.loadCobrancas(contatoHmId),
    repo.loadHistoricoAtivacao(contatoHmId),
  ]);
  return { extrato, cobrancas, historicoAtivacao };
}
