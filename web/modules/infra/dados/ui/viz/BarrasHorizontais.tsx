'use client';

export type Barra = { valor: string; rotulo: string; quantidade: number };

export function BarrasHorizontais({ titulo, barras, selecionado, onSelect }: { titulo: string; barras: Barra[]; selecionado?: string; onSelect: (valor: string) => void }) {
  const max = Math.max(1, ...barras.map((b) => b.quantidade));
  return <section aria-label={titulo} className="min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
    <h3 className="mb-3 text-sm font-semibold text-[var(--fg)]">{titulo}</h3>
    {barras.length === 0 && <p className="text-sm text-[var(--fg-3)]">Sem informação</p>}
    <div className="space-y-2">{barras.map((b) => <button type="button" key={b.valor} onClick={() => onSelect(b.valor)} aria-pressed={selecionado === b.valor} aria-label={`${b.rotulo}: ${b.quantidade}`} className="block w-full rounded-[var(--r-md)] px-2 py-1 text-left hover:bg-[var(--surface-3)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
      <span className="flex justify-between gap-2 text-xs text-[var(--fg-2)]"><span className="truncate">{b.rotulo}</span><span className="tabular">{b.quantidade}</span></span>
      <svg className="mt-1 h-3 w-full" viewBox="0 0 100 12" preserveAspectRatio="none" role="img" aria-hidden="true"><rect x="0" y="0" width="100" height="12" rx="3" fill="var(--surface-3)"/><rect x="0" y="0" width={Math.max(2, b.quantidade / max * 100)} height="12" rx="3" fill={selecionado === b.valor ? 'var(--green)' : 'var(--accent)'}/></svg>
    </button>)}</div>
  </section>;
}
