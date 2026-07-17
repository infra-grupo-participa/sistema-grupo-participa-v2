'use client';

import { Icon } from '@/shared/ui/icons';

/** Tabela densa e legível: header sticky, hover sutil, sem zebra.
 *  `fixed`: layout de colunas fixo (larguras definidas nos Th) — células truncam
 *  em vez de alargar a tabela, eliminando o scroll horizontal. */
export function DataTable({ children, className = '', fixed = false, minWidth }: { children: React.ReactNode; className?: string; fixed?: boolean; minWidth?: number }) {
  return (
    <div className={`rounded-[var(--r-lg)] border border-[var(--border)] overflow-hidden bg-[var(--surface-2)] shadow-[var(--shadow-sm)] ${className}`}>
      {/* Com muitas colunas, `minWidth` mantém as larguras e deixa a tabela ROLAR
          na horizontal em telas estreitas, em vez de espremer a 1ª coluna (o nome)
          até sumir. Sem minWidth, table-fixed + w-full comprime tudo no container. */}
      <div className="overflow-x-auto">
        <table style={minWidth ? { minWidth } : undefined} className={`w-full text-sm border-collapse ${fixed ? 'table-fixed' : ''}`}>{children}</table>
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
      className={`text-left px-3 py-2.5 text-[11px] font-semibold uppercase tracking-wide whitespace-nowrap overflow-hidden ${sortable ? 'cursor-pointer select-none hover:text-[var(--fg)]' : ''} ${active ? 'text-[var(--fg)]' : ''} ${className}`}
    >
      <span className="inline-flex max-w-full items-center gap-1">
        <span className="truncate">{children}</span>
        {sortable && <span className="text-[var(--accent)] inline-flex w-3 shrink-0">{active ? <Icon name={dir === 'asc' ? 'arrow-up' : 'arrow-down'} size={12} /> : null}</span>}
      </span>
    </th>
  );
}

export function Tr({ children, onClick, className = '', style }: { children: React.ReactNode; onClick?: () => void; className?: string; style?: React.CSSProperties }) {
  return (
    <tr
      onClick={onClick}
      style={style}
      className={`border-t border-[var(--border-faint)] transition-colors ${onClick ? 'cursor-pointer hover:bg-[var(--surface-3)]' : ''} ${className}`}
    >
      {children}
    </tr>
  );
}

export function Td({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <td className={`px-3 py-2.5 align-middle ${className}`}>{children}</td>;
}
