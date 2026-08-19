'use client';

// Kanban de colunas genérico — não existia no design system (financeiro é o
// 1º consumidor). Reutilizável por qualquer módulo que precise de board de
// cards agrupados em colunas fixas (não editável por drag — só leitura +
// clique). Grid fixo (nº de colunas) em vez de flex+scroll: todas as faixas
// cabem na viewport sem rolagem horizontal (decisão de produto 2026-08-19).
// Coluna sem itens colapsa em faixa fina (largura fixa) e devolve o espaço
// às colunas com conteúdo — mesmo assim permanece anunciada por completo a
// quem usa leitor de tela (aria-label na faixa, não apenas o texto visual).

export interface BoardColuna<T> {
  key: string;
  titulo: string;
  /** Texto longo — vira `title` (tooltip), nunca ocupa espaço permanente no cabeçalho. */
  descricao?: string;
  itens: T[];
  /** Resumo numérico da coluna (ex.: soma de saldo) — formatado pelo chamador. */
  resumo?: React.ReactNode;
}

export function Board<T>({ colunas, renderItem, renderVazio, keyOf }: {
  colunas: BoardColuna<T>[];
  renderItem: (item: T) => React.ReactNode;
  renderVazio?: (coluna: BoardColuna<T>) => React.ReactNode;
  keyOf: (item: T) => string;
}) {
  // Template dinâmico: colunas vazias colapsam em 56px fixos; as com itens
  // dividem o restante igualmente (minmax evita que uma coluna cheia esprema
  // as outras a ponto de truncar o card).
  const gridTemplate = colunas.map((c) => (c.itens.length === 0 ? '56px' : 'minmax(180px,1fr)')).join(' ');

  return (
    <div className="grid gap-3 items-start" role="list" aria-label="Board por faixa" style={{ gridTemplateColumns: gridTemplate }}>
      {colunas.map((col) => (
        <BoardColunaView key={col.key} coluna={col} renderItem={renderItem} renderVazio={renderVazio} keyOf={keyOf} />
      ))}
    </div>
  );
}

function BoardColunaView<T>({ coluna, renderItem, keyOf }: {
  coluna: BoardColuna<T>;
  renderItem: (item: T) => React.ReactNode;
  /** Não usado aqui: coluna vazia colapsa antes de renderizar itens/placeholder. */
  renderVazio?: (coluna: BoardColuna<T>) => React.ReactNode;
  keyOf: (item: T) => string;
}) {
  const vazia = coluna.itens.length === 0;
  const aria = `${coluna.titulo} — ${coluna.itens.length} ${coluna.itens.length === 1 ? 'item' : 'itens'}${vazia ? ', faixa sem cards, recolhida' : ''}`;

  if (vazia) {
    return (
      <section
        role="listitem"
        aria-label={aria}
        title={coluna.descricao ? `${coluna.titulo} — ${coluna.descricao}` : coluna.titulo}
        className="flex flex-col items-center gap-2 shrink-0 h-full min-h-[180px] rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] py-3"
      >
        <span className="shrink-0 text-[10px] font-semibold tabular text-[var(--fg-3)] rounded-[var(--r-pill)] bg-[var(--surface-3)] px-1.5 py-0.5">0</span>
        <span
          className="flex-1 min-h-0 [writing-mode:vertical-rl] rotate-180 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] whitespace-nowrap"
          aria-hidden="true"
        >
          {coluna.titulo}
        </span>
      </section>
    );
  }

  return (
    <section
      role="listitem"
      aria-label={aria}
      className="flex flex-col shrink-0 min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)]"
    >
      <header className="shrink-0 px-3 py-2 border-b border-[var(--border)]" title={coluna.descricao}>
        <div className="flex items-center justify-between gap-2">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-2)] truncate">{coluna.titulo}</h3>
          <span className="shrink-0 text-[11px] font-semibold tabular text-[var(--fg-3)] rounded-[var(--r-pill)] bg-[var(--surface-3)] px-1.5 py-0.5">{coluna.itens.length}</span>
        </div>
        {coluna.resumo != null && <div className="mt-0.5 text-[13px] font-bold tabular text-[var(--fg)] truncate">{coluna.resumo}</div>}
      </header>
      <div className="flex-1 min-h-0 overflow-y-auto p-2 flex flex-col gap-2 max-h-[calc(100dvh-320px)]">
        {coluna.itens.map((item) => <div key={keyOf(item)}>{renderItem(item)}</div>)}
      </div>
    </section>
  );
}
