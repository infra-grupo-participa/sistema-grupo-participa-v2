'use client';

// Board de cards — 5 colunas (FAIXAS_FUNIL, vindas do SQL). Card ordenado por
// saldo_a_pagar desc dentro da coluna (já vem assim de carregar-board.ts).
// Colunas sem cards colapsam (Board genérico decide o layout); aqui só
// entra o dado: título curto, descrição longa como tooltip, soma de saldo
// (saldoEfetivo — mesma regra do rodapé, nunca soma resíduo de centavos).
import { Board, EmptyState, type BoardColuna } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { saldoEfetivo } from '../domain/financeiro';
import { CardBoardView } from './CardBoard';
import { FAIXAS_FUNIL, type CardComEfeito } from '../application/carregar-board';
import type { FaixaFunil } from '../domain/types';

const DESCRICAO_FAIXA: Record<FaixaFunil, string> = {
  sem_tratativa: 'Boleto gerado, aguardando pagamento ou comprou sem contato ainda.',
  em_negociacao: 'Reunião agendada ou finalizada — em conversa com o comercial.',
  acordo_em_curso: 'Tem vencimento combinado ou já pagou parte do saldo.',
  quitado: 'Chegou nos estágios de ativação — pacote 100% pago.',
  em_risco: 'Solicitou cancelamento, cancelou ou foi reembolsado.',
};

export function BoardView({ colunas, onOpen }: {
  colunas: Record<FaixaFunil, CardComEfeito[]>;
  onOpen: (id: string) => void;
}) {
  const boardColunas: BoardColuna<CardComEfeito>[] = FAIXAS_FUNIL.map(({ chave, rotulo }) => {
    const itens = colunas[chave] ?? [];
    const somaSaldo = itens.reduce((a, c) => a + saldoEfetivo(c.conta), 0);
    return {
      key: chave,
      titulo: rotulo,
      descricao: DESCRICAO_FAIXA[chave],
      itens,
      resumo: itens.length ? fmtBRL(somaSaldo) : undefined,
    };
  });

  const totalCards = boardColunas.reduce((a, c) => a + c.itens.length, 0);
  if (!totalCards) {
    return <EmptyState title="Nenhum card no board" hint="Sem contas para os filtros aplicados." icon="wallet" />;
  }

  return (
    <Board
      colunas={boardColunas}
      keyOf={(c) => c.conta.contato_hm_id}
      renderItem={(c) => <CardBoardView card={c} onOpen={onOpen} />}
    />
  );
}
