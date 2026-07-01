'use client';

import { useEffect } from 'react';
import { Icon } from '@/shared/ui/icons';

/** Card de detalhe: modal centralizado amplo com header (avatar/título/badges/ações),
 *  corpo rolável e rodapé de ações fixo. Info à vista, orientado à operação. */
export function Drawer({
  open = true,
  onClose,
  title,
  subtitle,
  avatar,
  badges,
  actions,
  footer,
  children,
  width = 'max-w-3xl',
}: {
  open?: boolean;
  onClose: () => void;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  avatar?: React.ReactNode;
  badges?: React.ReactNode;
  actions?: React.ReactNode;
  footer?: React.ReactNode;
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
    <div className="fixed inset-0 z-[1000] flex items-start sm:items-center justify-center p-3 sm:p-6">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/60 backdrop-blur-[2px] gp-overlay-in" />
      <div className={`relative w-full ${width} max-h-[92vh] flex flex-col rounded-[var(--r-xl)] border border-[var(--border-strong)] bg-[var(--surface-1)] shadow-[var(--shadow-lg)] gp-modal-in overflow-hidden`}>
        <div className="shrink-0 bg-[var(--surface-1)] border-b border-[var(--border)] px-5 py-4">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              {avatar && <div className="shrink-0">{avatar}</div>}
              <div className="min-w-0">
                <h2 className="text-lg font-bold text-[var(--fg)] truncate">{title}</h2>
                {subtitle && <p className="text-xs text-[var(--fg-3)] truncate mt-0.5">{subtitle}</p>}
              </div>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              {actions}
              <button onClick={onClose} aria-label="Fechar" className="w-8 h-8 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="x" /></button>
            </div>
          </div>
          {badges && <div className="flex flex-wrap gap-1.5 mt-3">{badges}</div>}
        </div>
        <div className="flex-1 overflow-y-auto p-5">{children}</div>
        {footer && <div className="shrink-0 bg-[var(--surface-1)] border-t border-[var(--border)] px-5 py-3 flex flex-wrap items-center gap-2">{footer}</div>}
      </div>
    </div>
  );
}

/** Avatar circular com inicial — cabeçalho dos cards de detalhe. */
export function AvatarInicial({ nome, size = 40 }: { nome?: string | null; size?: number }) {
  const inicial = (nome || '?').trim().charAt(0).toUpperCase();
  return (
    <div
      className="grid place-items-center rounded-full bg-[var(--accent-subtle)] text-[var(--accent)] font-bold border border-[var(--accent-border)]"
      style={{ width: size, height: size, fontSize: size * 0.4 }}
    >
      {inicial}
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
