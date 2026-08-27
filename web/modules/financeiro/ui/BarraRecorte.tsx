'use client';

// Barra de recorte ativo (N1, 2026-08-27) — acima do mosaico. Antes o recorte
// só era nomeado no RODAPÉ (RodapeTotais.tsx), depois do mosaico inteiro: quem
// chega com canal + busca aplicados precisava rolar até o fim para saber o que
// estava vendo. Chips removíveis (canal · busca), cada um com seu ×, mais
// "limpar tudo".
//
// A montagem do rótulo vem de domain/recorte.ts — a mesma função que
// RodapeTotais usa — para as duas nunca divergirem sobre o que está no
// recorte (era a duplicação que este componente existe para apagar).
//
// "Limpar tudo" NÃO reseta o produto: HM/AURUM é uma ABA (ProdutoTabs), não
// um filtro — produtoAtivo não tem estado "nenhum" (ver FinanceiroClient.tsx).
// Por isso este componente só recebe onLimparCanal/onLimparBusca/onLimparTudo,
// nunca um onLimparProduto.
import { Icon } from '@/shared/ui/icons';
import { itensRecorte, type ItemRecorte, type RecorteAtivo } from '../domain/recorte';

export function BarraRecorte({ recorte, onLimparCanal, onLimparBusca, onLimparCor, onLimparTudo }: {
  recorte: RecorteAtivo;
  onLimparCanal: () => void;
  onLimparBusca: () => void;
  onLimparCor: () => void;
  /** Limpa canal + busca + cor, mantém produto (ver nota do arquivo). */
  onLimparTudo: () => void;
}) {
  const itens = itensRecorte(recorte);
  // Mapa EXAUSTIVO por tipo de chip — o Record<> força o compilador a travar
  // se um filtro novo nascer sem handler. Antes era um ternário
  // (`tipo === 'canal' ? A : B`), que mandava silenciosamente qualquer tipo
  // novo para o handler da busca: o chip de cor limparia a busca.
  const limpar: Record<ItemRecorte['tipo'], () => void> = {
    canal: onLimparCanal,
    busca: onLimparBusca,
    cor: onLimparCor,
  };
  if (!itens.length) return null;

  return (
    <div className="mb-3 flex flex-wrap items-center gap-1.5" aria-label="Recorte ativo do board">
      <span className="text-[11px] font-medium uppercase tracking-wide text-[var(--fg-4)]">Filtrando por</span>
      {itens.map((item) => (
        <span
          key={item.tipo}
          className="inline-flex items-center gap-1 rounded-[var(--r-pill)] border border-[var(--accent-border)] bg-[var(--accent-subtle)] py-0.5 pl-2.5 pr-1 text-[11px] font-semibold text-[var(--accent)]"
        >
          {item.label}
          <button
            type="button"
            onClick={limpar[item.tipo]}
            aria-label={`Remover filtro: ${item.label}`}
            className="inline-flex h-4 w-4 items-center justify-center rounded-[var(--r-pill)] hover:bg-[var(--surface-1)] focus-visible:ring-2"
          >
            <Icon name="x" size={11} />
          </button>
        </span>
      ))}
      <button
        type="button"
        onClick={onLimparTudo}
        className="text-[11px] font-semibold text-[var(--fg-3)] underline underline-offset-2 hover:text-[var(--fg-2)] focus-visible:ring-2 rounded-[var(--r-sm)]"
      >
        limpar tudo
      </button>
    </div>
  );
}
