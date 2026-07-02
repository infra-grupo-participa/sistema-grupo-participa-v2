/** Spinner — track surface-4, topo âmbar (paridade .spinner do legado). */
export function Spinner({ size = 24 }: { size?: number }) {
  return (
    <span
      className="inline-block rounded-full align-middle"
      style={{
        width: size, height: size,
        border: `${Math.max(2, size / 10)}px solid var(--surface-4)`,
        borderTopColor: 'var(--accent)',
        animation: 'gp-spin .75s linear infinite',
      }}
      aria-label="Carregando"
      role="status"
    />
  );
}

/** Estado de carregamento dentro de um bloco (paridade .loading-wrap). */
export function Loading({ label = 'Carregando…', minHeight = 240 }: { label?: string; minHeight?: number }) {
  return (
    <div
      className="flex items-center justify-center gap-3 rounded-[var(--r-xl)] border border-[var(--border)] bg-[var(--surface-2)] text-[var(--fg-3)] text-sm"
      style={{ minHeight }}
    >
      <Spinner /> {label}
    </div>
  );
}

/** Barra de skeleton pulsante — bloco de construção para placeholders de carga. */
export function Skeleton({ w, h = 12, className = '' }: { w?: number | string; h?: number; className?: string }) {
  return <div className={`rounded bg-[var(--surface-3)] animate-pulse ${className}`} style={{ width: w, height: h }} aria-hidden />;
}

/**
 * Esqueleto de linhas de tabela na 1ª carga (padrão do piloto Placas).
 * `cols` = larguras (px) das colunas após a primeira; `avatar` inclui célula inicial com avatar+2 linhas.
 */
export function SkeletonRows({ rows = 6, cols = [64, 80, 96, 40, 56], avatar = true }: {
  rows?: number; cols?: number[]; avatar?: boolean;
}) {
  return (
    <>
      {Array.from({ length: rows }).map((_, i) => (
        <tr key={i} className="border-t border-[var(--border-faint)]">
          {avatar && (
            <td className="px-3 py-2.5">
              <div className="flex items-center gap-2.5">
                <span className="w-8 h-8 rounded-full bg-[var(--surface-3)] animate-pulse shrink-0" />
                <div className="space-y-1.5">
                  <Skeleton w={144} h={12} />
                  <Skeleton w={176} h={10} />
                </div>
              </div>
            </td>
          )}
          {cols.map((w, j) => (
            <td key={j} className="px-3 py-2.5"><Skeleton w={w} /></td>
          ))}
        </tr>
      ))}
    </>
  );
}

const FILL: Record<string, string> = {
  accent: 'var(--accent)', green: 'var(--green)', yellow: 'var(--yellow)', red: 'var(--red)', purple: 'var(--purple)',
};

/** Barra de progresso fina (paridade .progress-bar / .vg-progress-bar). */
export function ProgressBar({ value, tone = 'accent', height = 6, showLabel = false }: {
  value: number; tone?: keyof typeof FILL; height?: number; showLabel?: boolean;
}) {
  const pct = Math.max(0, Math.min(100, value));
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 rounded-[var(--r-pill)] bg-[var(--surface-4)] overflow-hidden" style={{ height }}>
        <div className="h-full rounded-[var(--r-pill)] transition-[width] duration-300" style={{ width: `${pct}%`, background: FILL[tone] }} />
      </div>
      {showLabel && <span className="text-[11px] tabular text-[var(--fg-3)] w-9 text-right">{Math.round(pct)}%</span>}
    </div>
  );
}
