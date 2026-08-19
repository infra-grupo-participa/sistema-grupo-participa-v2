'use client';

// Kanban de colunas genérico — não existia no design system (financeiro é o
// 1º consumidor). Reutilizável por qualquer módulo que precise de board de
// cards agrupados em colunas fixas (não editável por drag — só leitura +
// clique). Rolagem horizontal entre colunas, vertical dentro de cada uma.

export interface BoardColuna<T> {
  key: string;
  titulo: string;
  descricao?: string;
  itens: T[];
}

export function Board<T>({ colunas, renderItem, renderVazio, keyOf }: {
  colunas: BoardColuna<T>[];
  renderItem: (item: T) => React.ReactNode;
  renderVazio?: (coluna: BoardColuna<T>) => React.ReactNode;
  keyOf: (item: T) => string;
}) {
  return (
    <div className="flex gap-3 overflow-x-auto pb-2 items-start" role="list" aria-label="Board por faixa">
      {colunas.map((col) => (
        <BoardColunaView key={col.key} coluna={col} renderItem={renderItem} renderVazio={renderVazio} keyOf={keyOf} />
      ))}
    </div>
  );
}

function BoardColunaView<T>({ coluna, renderItem, renderVazio, keyOf }: {
  coluna: BoardColuna<T>;
  renderItem: (item: T) => React.ReactNode;
  renderVazio?: (coluna: BoardColuna<T>) => React.ReactNode;
  keyOf: (item: T) => string;
}) {
  return (
    <section
      role="listitem"
      aria-label={`${coluna.titulo} — ${coluna.itens.length} ${coluna.itens.length === 1 ? 'item' : 'itens'}`}
      className="flex flex-col shrink-0 w-[280px] rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)]"
    >
      <header className="shrink-0 px-3 py-2.5 border-b border-[var(--border)]">
        <div className="flex items-center justify-between gap-2">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)] truncate" title={coluna.titulo}>{coluna.titulo}</h3>
          <span className="shrink-0 text-[11px] font-semibold tabular text-[var(--fg-3)] rounded-[var(--r-pill)] bg-[var(--surface-3)] px-1.5 py-0.5">{coluna.itens.length}</span>
        </div>
        {coluna.descricao && <p className="mt-0.5 text-[11px] text-[var(--fg-3)] leading-snug">{coluna.descricao}</p>}
      </header>
      <div className="flex-1 min-h-0 overflow-y-auto p-2 flex flex-col gap-2 max-h-[calc(100dvh-320px)]">
        {coluna.itens.length === 0
          ? (renderVazio ? renderVazio(coluna) : <p className="text-[11px] text-[var(--fg-3)] text-center py-6">Nenhum card nesta faixa.</p>)
          : coluna.itens.map((item) => <div key={keyOf(item)}>{renderItem(item)}</div>)}
      </div>
    </section>
  );
}
