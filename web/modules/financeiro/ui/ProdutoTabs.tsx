'use client';

// Abas de produto (HM / Aurum) — nível acima da timeline de canais. Pedido
// explícito do Marcio: "separa HM do AURUM... não junta". Filtra no cliente
// (board.cards já vem inteiro numa chamada, `origem` está em cada card —
// troca instantânea, zero query nova; 305 cards no total, custo desprezível).
//
// Cor por produto reaproveita a MESMA paleta do badge de origem no card
// (CardBoard.tsx: info=HM, purple=AURUM) — sinal consistente em todo o board,
// não uma terceira convenção de cor. Âmbar (--accent) fica de fora: é
// exclusivo de seleção/ação, e aqui a cor identifica o PRODUTO, não marca
// "está selecionado" (isso é a borda/peso do tab ativo).
import type { CardBoard } from '../domain/types';

export type ProdutoChave = CardBoard['origem'];

export const PRODUTOS: { chave: ProdutoChave; rotulo: string }[] = [
  { chave: 'HM', rotulo: 'Holding Masters' },
  { chave: 'AURUM', rotulo: 'Aurum' },
];

const TOM: Record<ProdutoChave, { texto: string; borda: string; fundo: string }> = {
  HM: { texto: 'text-[var(--info)]', borda: 'border-[var(--info-border)]', fundo: 'bg-[var(--info-subtle)]' },
  AURUM: { texto: 'text-[var(--purple)]', borda: 'border-[var(--purple-border)]', fundo: 'bg-[var(--purple-subtle)]' },
};

export function ProdutoTabs({ contagens, ativo, onSelecionar }: {
  /** Contagem de cards por produto no board completo (sem filtro de canal) — nunca 0 silencioso. */
  contagens: Record<ProdutoChave, number>;
  ativo: ProdutoChave;
  onSelecionar: (produto: ProdutoChave) => void;
}) {
  return (
    <div className="flex items-center gap-1.5 mb-3" role="tablist" aria-label="Produto">
      {PRODUTOS.map((p) => {
        const active = ativo === p.chave;
        const tom = TOM[p.chave];
        const vazio = contagens[p.chave] === 0;
        return (
          <button
            key={p.chave}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onSelecionar(p.chave)}
            className={`inline-flex items-center gap-2 rounded-[var(--r-md)] border px-3.5 py-2 text-sm font-semibold transition-colors focus-visible:ring-2 focus-visible:ring-[var(--border-accent)] ${
              active
                ? `${tom.borda} ${tom.fundo} ${tom.texto}`
                : 'border-[var(--border)] text-[var(--fg-3)] hover:border-[var(--border-strong)] hover:text-[var(--fg-2)]'
            }`}
          >
            {p.rotulo}
            <span
              className={`tabular rounded-[var(--r-pill)] px-1.5 py-0.5 text-[11px] font-bold ${
                active ? 'bg-[var(--surface-1)]' : 'bg-[var(--surface-3)]'
              }`}
            >
              {contagens[p.chave]}
            </span>
            {vazio && (
              <span className="text-[10px] font-medium text-[var(--fg-4)] normal-case">sem cards</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
