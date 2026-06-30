'use client';

import { Icon } from '@/shared/ui/icons';

/** Tabela densa e legível: header sticky, hover sutil, sem zebra. */
export function DataTable({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`rounded-[var(--r-lg)] border border-[var(--border)] overflow-hidden bg-[var(--surface-2)] shadow-[var(--shadow-sm)] ${className}`}>
      <div className="overflow-x-auto">
        <table className="w-full text-sm border-collapse">{children}</table>
      </div>
    </div>
  );
}

export function Thead({ children }: { children: React.ReactNode }) {
  return (
    <thead className="sticky top-0 z-[1] bg-[var(--surface-3)] text-[var(--fg-3)]">
      <tr>{children}</tr>
    </thead>
  );
}

export function Th({
  children,
  sortable,
  active,
  dir,
  onClick,
  className = '',
}: {
  children: React.ReactNode;
  sortable?: boolean;
  active?: boolean;
  dir?: 'asc' | 'desc';
  onClick?: () => void;
  className?: string;
}) {
  return (
    <th
      onClick={onClick}
      className={`text-left px-3 py-2.5 text-[11px] font-semibold uppercase tracking-wide whitespace-nowrap ${sortable ? 'cursor-pointer select-none hover:text-[var(--fg)]' : ''} ${active ? 'text-[var(--fg)]' : ''} ${className}`}
    >
      <span className="inline-flex items-center gap-1">
        {children}
        {sortable && <span className="text-[var(--accent)] inline-flex w-3">{active ? <Icon name={dir === 'asc' ? 'arrow-up' : 'arrow-down'} size={12} /> : null}</span>}
      </span>
    </th>
  );
}

export function Tr({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) {
  return (
    <tr
      onClick={onClick}
      className={`border-t border-[var(--border-faint)] transition-colors ${onClick ? 'cursor-pointer hover:bg-[var(--surface-3)]' : ''}`}
    >
      {children}
    </tr>
  );
}

export function Td({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <td className={`px-3 py-2.5 align-middle ${className}`}>{children}</td>;
}
