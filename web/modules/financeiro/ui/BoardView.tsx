'use client';

// Board de cards — 5 colunas (FAIXAS_FUNIL, vindas do SQL). Card ordenado por
// saldo_a_pagar desc dentro da coluna (já vem assim de carregar-board.ts).
import { Board, EmptyState, type BoardColuna } from '@/shared/ui/components';
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
  const boardColunas: BoardColuna<CardComEfeito>[] = FAIXAS_FUNIL.map(({ chave, rotulo }) => ({
    key: chave,
    titulo: rotulo,
    descricao: DESCRICAO_FAIXA[chave],
    itens: colunas[chave] ?? [],
  }));

  const totalCards = boardColunas.reduce((a, c) => a + c.itens.length, 0);
  if (!totalCards) {
    return <EmptyState title="Nenhum card no board" hint="Sem contas para os filtros aplicados." icon="wallet" />;
  }

  return (
    <Board
      colunas={boardColunas}
      keyOf={(c) => c.conta.contato_hm_id}
      renderItem={(c) => <CardBoardView card={c} onOpen={onOpen} />}
      renderVazio={() => <p className="text-[11px] text-[var(--fg-3)] text-center py-6">Nenhum card nesta faixa (com os filtros atuais).</p>}
    />
  );
}
