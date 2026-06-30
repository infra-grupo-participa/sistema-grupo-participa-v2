/** Linha do tempo vertical (paridade .historico-list / steps de auditoria do legado). */

const DOT: Record<string, string> = {
  accent: 'var(--accent)', green: 'var(--green)', yellow: 'var(--yellow)',
  red: 'var(--red)', purple: 'var(--purple)', info: 'var(--info)', base: 'var(--fg-3)',
};

export type TimelineEntry = {
  icon?: React.ReactNode;
  tone?: keyof typeof DOT;
  title: React.ReactNode;
  meta?: React.ReactNode;
  body?: React.ReactNode;
  done?: boolean;
};

export function Timeline({ items }: { items: TimelineEntry[] }) {
  return (
    <ol className="relative ml-3 border-l border-[var(--border)]">
      {items.map((it, i) => (
        <TimelineItem key={i} {...it} last={i === items.length - 1} />
      ))}
    </ol>
  );
}

function TimelineItem({ icon, tone = 'base', title, meta, body, done, last }: TimelineEntry & { last?: boolean }) {
  const color = DOT[tone];
  return (
    <li className={`relative pl-5 ${last ? '' : 'pb-5'}`}>
      <span
        className="absolute -left-[9px] top-0.5 grid place-items-center rounded-full text-[10px]"
        style={{
          width: 18, height: 18,
          background: done ? color : `color-mix(in srgb, ${color} 14%, transparent)`,
          color: done ? '#fff' : color, /* hex-ok: branco de contraste sobre dot preenchido */
          border: `1px solid color-mix(in srgb, ${color} 40%, transparent)`,
        }}
      >
        {icon ?? (done ? '✓' : '')}
      </span>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm font-medium text-[var(--fg)]">{title}</span>
        {meta && <span className="text-[11px] tabular text-[var(--fg-3)] shrink-0">{meta}</span>}
      </div>
      {body && <div className="mt-1 text-xs text-[var(--fg-2)] leading-relaxed">{body}</div>}
    </li>
  );
}
