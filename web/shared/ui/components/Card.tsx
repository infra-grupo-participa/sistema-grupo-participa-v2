/** Superfície elevada padrão (surface-2 + borda + sombra sutil). Profundidade consistente. */
export function Card({ children, className = '', as: As = 'div', ...rest }: { children: React.ReactNode; className?: string; as?: React.ElementType } & React.HTMLAttributes<HTMLElement>) {
  return (
    <As
      className={`rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] ${className}`}
      {...rest}
    >
      {children}
    </As>
  );
}

/** KPI: número em destaque com rótulo e cor semântica opcional. */
export function StatCard({ label, value, tone, hint }: { label: string; value: React.ReactNode; tone?: string; hint?: string }) {
  return (
    <Card className="p-4">
      <div className="text-2xl font-bold tabular leading-none" style={tone ? { color: tone } : undefined}>{value}</div>
      <div className="mt-1.5 text-xs font-medium text-[var(--fg-3)]">{label}</div>
      {hint && <div className="mt-0.5 text-[11px] text-[var(--fg-3)]">{hint}</div>}
    </Card>
  );
}

/** Título de seção com hairline — ritmo vertical consistente. */
export function SectionTitle({ children, right }: { children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 mb-2">
      <h2 className="text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">{children}</h2>
      {right}
    </div>
  );
}

export function EmptyState({ title, hint, icon = '∅' }: { title: string; hint?: string; icon?: string }) {
  return (
    <div className="py-12 text-center">
      <div className="text-2xl opacity-40">{icon}</div>
      <div className="mt-2 text-sm text-[var(--fg-2)]">{title}</div>
      {hint && <div className="mt-1 text-xs text-[var(--fg-3)]">{hint}</div>}
    </div>
  );
}
