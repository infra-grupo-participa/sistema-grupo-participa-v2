'use client';

import { useEffect } from 'react';
import { Icon } from '@/shared/ui/icons';

/** Drawer lateral com overlay, animação e header. Hierarquia e foco consistentes. */
export function Drawer({
  open = true,
  onClose,
  title,
  subtitle,
  badges,
  actions,
  children,
  width = 'max-w-lg',
}: {
  open?: boolean;
  onClose: () => void;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  badges?: React.ReactNode;
  actions?: React.ReactNode;
  children: React.ReactNode;
  width?: string;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[1000] flex justify-end">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/55 backdrop-blur-[1px] gp-overlay-in" />
      <div className={`relative w-full ${width} h-full overflow-y-auto bg-[var(--surface-1)] border-l border-[var(--border-strong)] shadow-[var(--shadow-lg)] gp-panel-in`}>
        <div className="sticky top-0 z-10 bg-[var(--surface-1)]/95 backdrop-blur border-b border-[var(--border)] px-5 py-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <h2 className="text-lg font-bold text-[var(--fg)] truncate">{title}</h2>
              {subtitle && <p className="text-xs text-[var(--fg-3)] truncate mt-0.5">{subtitle}</p>}
            </div>
            <div className="flex items-center gap-2 shrink-0">
              {actions}
              <button onClick={onClose} aria-label="Fechar" className="w-8 h-8 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="x" /></button>
            </div>
          </div>
          {badges && <div className="flex flex-wrap gap-1.5 mt-3">{badges}</div>}
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

/** Abas internas (drawer/painel). */
export function Tabs({ tabs, active, onChange }: { tabs: { k: string; l: string }[]; active: string; onChange: (k: string) => void }) {
  return (
    <div className="flex gap-1 border-b border-[var(--border)] mb-4 -mx-1 overflow-x-auto">
      {tabs.map((t) => (
        <button
          key={t.k}
          onClick={() => onChange(t.k)}
          className={`px-3 py-2 text-sm whitespace-nowrap border-b-2 -mb-px transition-colors ${
            active === t.k ? 'border-[var(--accent)] text-[var(--fg)] font-medium' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'
          }`}
        >
          {t.l}
        </button>
      ))}
    </div>
  );
}

/** Linha rótulo/valor — densidade de leitura consistente nos drawers. */
export function Row({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 py-1.5 border-b border-[var(--border-faint)] last:border-0">
      <span className="text-xs text-[var(--fg-3)] shrink-0">{k}</span>
      <span className="text-sm text-[var(--fg)] text-right break-words">{v ?? '—'}</span>
    </div>
  );
}
