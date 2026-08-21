'use client';

// Board de cards — colunas por FAIXAS_FUNIL (vindas do SQL) OU por prazo de
// pagamento (F6/F7, 0307/0308 no repo da esteira — 3º eixo, ./domain/prazo.ts).
// Card ordenado por saldo_a_pagar desc dentro da coluna.
// Colunas sem cards colapsam (Board genérico decide o layout); aqui só
// entra o dado: título curto, descrição longa como tooltip, soma de saldo
// (saldoEfetivo — mesma regra do rodapé, nunca soma resíduo de centavos).
//
// SELETOR, não terceiro agrupamento simultâneo: o board já tem 2 eixos
// convivendo, documentados como intencionalmente paralelos em ./domain/types.ts
// (FaixaFunil, do SQL) e ./domain/board.ts (FAIXAS/faixaDe, domínio) — três é
// o limite antes de virar ruído. O toggle troca QUAL eixo está agrupando as
// colunas; nunca os dois ao mesmo tempo.
import { useState } from 'react';
import { Board, EmptyState, type BoardColuna } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { saldoEfetivo } from '../domain/financeiro';
import { faixaPrazoDe, FAIXAS_PRAZO_ORDEM, FAIXA_PRAZO_META } from '../domain/prazo';
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

type Eixo = 'funil' | 'prazo';

export function BoardView({ colunas, cards, hojeISO, onOpen }: {
  colunas: Record<FaixaFunil, CardComEfeito[]>;
  /** Lista plana (mesmos cards de `colunas`, já filtrados por produto/ação) —
   *  necessária para reagrupar localmente por prazo, sem query nova. */
  cards: CardComEfeito[];
  /** Data de referência (ISO) para faixaPrazoDe — injetada pelo chamador,
   *  mesma disciplina de proximaAcao()/preverRecebimento() em ./domain/cobranca.ts. */
  hojeISO: string;
  onOpen: (id: string) => void;
}) {
  const [eixo, setEixo] = useState<Eixo>('funil');

  const boardColunas: BoardColuna<CardComEfeito>[] = eixo === 'funil'
    ? FAIXAS_FUNIL.map(({ chave, rotulo }) => {
        const itens = colunas[chave] ?? [];
        const somaSaldo = itens.reduce((a, c) => a + saldoEfetivo(c.conta), 0);
        return {
          key: chave,
          titulo: rotulo,
          descricao: DESCRICAO_FAIXA[chave],
          itens,
          resumo: itens.length ? fmtBRL(somaSaldo) : undefined,
        };
      })
    : FAIXAS_PRAZO_ORDEM.map((faixa) => {
        const itens = cards
          .filter((c) => faixaPrazoDe(c.conta, hojeISO) === faixa)
          .sort((a, b) => (b.conta.saldo_a_pagar ?? 0) - (a.conta.saldo_a_pagar ?? 0));
        const somaSaldo = itens.reduce((a, c) => a + saldoEfetivo(c.conta), 0);
        const meta = FAIXA_PRAZO_META[faixa];
        return {
          key: faixa,
          titulo: meta.label,
          descricao: meta.descricao,
          itens,
          resumo: itens.length ? fmtBRL(somaSaldo) : undefined,
        };
      });

  const totalCards = boardColunas.reduce((a, c) => a + c.itens.length, 0);

  return (
    <div>
      <div className="mb-3 flex items-center gap-1.5" role="group" aria-label="Agrupar o board por">
        <span className="text-[11px] font-medium uppercase tracking-wide text-[var(--fg-4)]">Agrupar por</span>
        <SeletorEixo ativo={eixo === 'funil'} onClick={() => setEixo('funil')}>Estágio do funil</SeletorEixo>
        <SeletorEixo ativo={eixo === 'prazo'} onClick={() => setEixo('prazo')}>Prazo de pagamento</SeletorEixo>
      </div>

      {!totalCards ? (
        <EmptyState title="Nenhum card no board" hint="Sem contas para os filtros aplicados." icon="wallet" />
      ) : (
        <Board
          colunas={boardColunas}
          keyOf={(c) => c.conta.contato_hm_id}
          renderItem={(c) => <CardBoardView card={c} onOpen={onOpen} />}
        />
      )}
    </div>
  );
}

function SeletorEixo({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      onClick={onClick}
      className={`rounded-[var(--r-sm)] px-2 py-1 text-xs font-semibold transition-colors focus-visible:ring-2 ${
        ativo
          ? 'bg-[var(--accent-subtle)] text-[var(--accent)] border border-[var(--accent-border)]'
          : 'text-[var(--fg-3)] border border-transparent hover:bg-[var(--surface-2)]'
      }`}
    >
      {children}
    </button>
  );
}
