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
