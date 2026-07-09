// Blocos visuais da ficha do aluno — compartilhados entre leitura (AlunoDrawer) e edição (AlunoForm).

import { Icon } from '@/shared/ui/icons';

/** Cabeçalho de seção com ícone de acento (linguagem do card de Placas). */
export function SecTitle({ icon, children }: { icon: string; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 text-[var(--fg)]">
      <Icon name={icon} size={15} className="text-[var(--accent)]" /> {children}
    </span>
  );
}

export function SubTitle({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mt-3 mb-1 pt-1 border-t border-[var(--border-faint)]">{children}</div>;
}

export function Section({ children }: { children: React.ReactNode }) {
  return <div className="space-y-1.5">{children}</div>;
}

export function Row({ k, v }: { k: string; v: string | null }) {
  return <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]"><span className="text-xs text-[var(--fg-3)]">{k}</span><span className="text-sm text-[var(--fg)] text-right">{v || '—'}</span></div>;
}
