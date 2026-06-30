/** Superfície elevada padrão (surface-2 + borda + sombra sutil). Profundidade consistente. */
export function Card({ children, className = '', as: As = 'div', ...rest }: { children: React.ReactNode; className?: string; as?: React.ElementType } & React.HTMLAttributes<HTMLElement> & Partial<Pick<React.AnchorHTMLAttributes<HTMLAnchorElement>, 'href' | 'target' | 'rel'>>) {
  return (
    <As
      className={`rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] ${className}`}
      {...rest}
    >
      {children}
    </As>
  );
}

/** Linha de acento (borda-topo) das stat cards do legado. */
const BAR: Record<string, string> = {
  accent: 'var(--accent)', green: 'var(--green)', yellow: 'var(--yellow)',
  red: 'var(--red)', purple: 'var(--purple)', gray: 'var(--border-strong)',
};

/** KPI: número em destaque com rótulo e cor semântica opcional.
 *  `bar` desenha a linha de acento no topo (paridade com .stat-card.orange/green/… do legado). */
export function StatCard({ label, value, tone, hint, bar }: {
  label: string; value: React.ReactNode; tone?: string; hint?: string; bar?: keyof typeof BAR;
}) {
  return (
    <Card className="p-4" style={bar ? { borderTop: `2px solid ${BAR[bar]}` } : undefined}>
      <div className="text-2xl font-bold tabular leading-none" style={tone ? { color: tone } : undefined}>{value}</div>
      <div className="mt-1.5 text-xs font-medium text-[var(--fg-3)]">{label}</div>
      {hint && <div className="mt-0.5 text-[11px] text-[var(--fg-3)]">{hint}</div>}
    </Card>
  );
}

/** KPI com borda-esquerda colorida (paridade com .vg-kpi-card / .ht21-info-card do legado). */
export function KpiCard({ label, value, hint, bar = 'accent' }: {
  label: string; value: React.ReactNode; hint?: string; bar?: keyof typeof BAR;
}) {
  return (
    <Card className="p-4" style={{ borderLeft: `4px solid ${BAR[bar]}` }}>
      <div className="text-xs font-medium uppercase tracking-wide text-[var(--fg-3)]">{label}</div>
      <div className="mt-1 text-2xl font-bold tabular leading-none text-[var(--fg)]">{value}</div>
      {hint && <div className="mt-1 text-[11px] text-[var(--fg-3)]">{hint}</div>}
    </Card>
  );
}

/** Card de seção com título e subtítulo — bloco de conteúdo padrão. */
export function SectionCard({ title, subtitle, right, children, className = '' }: {
  title?: React.ReactNode; subtitle?: React.ReactNode; right?: React.ReactNode; children: React.ReactNode; className?: string;
}) {
  return (
    <Card className={`p-5 ${className}`}>
      {(title || right) && (
        <div className="flex items-start justify-between gap-3 mb-3">
          <div className="min-w-0">
            {title && <h2 className="text-base font-bold text-[var(--fg)]">{title}</h2>}
            {subtitle && <p className="mt-0.5 text-sm text-[var(--fg-2)] leading-relaxed">{subtitle}</p>}
          </div>
          {right}
        </div>
      )}
      {children}
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
