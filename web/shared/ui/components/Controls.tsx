'use client';

import { forwardRef } from 'react';
import { Icon } from '@/shared/ui/icons';

/** Barra de ferramentas — agrupa busca, filtros e ações com espaçamento consistente. */
export function Toolbar({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <div className={`flex flex-wrap items-center gap-2 ${className}`}>{children}</div>;
}

const inputCls =
  'w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg)] placeholder:text-[var(--fg-3)] ' +
  'px-3 py-2 text-sm transition-colors focus:border-[var(--border-accent)] disabled:opacity-50';

/** Campo de busca com ícone (paridade .search-wrap / .search-icon). */
export const SearchInput = forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  function SearchInput({ className = '', ...rest }, ref) {
    return (
      <div className="relative min-w-[200px] flex-1">
        <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--fg-3)]"><Icon name="search" size={15} /></span>
        <input ref={ref} type="search" className={`${inputCls} pl-8 ${className}`} {...rest} />
      </div>
    );
  },
);

/** Input de texto padrão do design system. */
export const Input = forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  function Input({ className = '', ...rest }, ref) {
    return <input ref={ref} className={`${inputCls} ${className}`} {...rest} />;
  },
);

/** Select com chevron custom (paridade .filter-select). */
export const FilterSelect = forwardRef<HTMLSelectElement, React.SelectHTMLAttributes<HTMLSelectElement>>(
  function FilterSelect({ className = '', children, ...rest }, ref) {
    return (
      <div className="relative">
        <select
          ref={ref}
          className={`${inputCls} appearance-none pr-8 cursor-pointer ${className}`}
          {...rest}
        >
          {children}
        </select>
        <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-[var(--fg-3)]"><Icon name="chevron-down" size={14} /></span>
      </div>
    );
  },
);

/** Switch (paridade .toggle/.toggle-slider). Controlado. */
export function Toggle({ checked, onChange, label, disabled }: {
  checked: boolean; onChange: (v: boolean) => void; label?: string; disabled?: boolean;
}) {
  return (
    <label className={`inline-flex items-center gap-2 select-none ${disabled ? 'opacity-50' : 'cursor-pointer'}`}>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => !disabled && onChange(!checked)}
        className="relative inline-flex shrink-0 rounded-[var(--r-pill)] transition-colors duration-150"
        style={{ width: 38, height: 21, background: checked ? 'var(--accent)' : 'var(--surface-4)' }}
      >
        <span
          className="absolute top-0.5 rounded-full bg-white transition-transform duration-150"
          style={{ width: 17, height: 17, left: 2, transform: checked ? 'translateX(17px)' : 'translateX(0)' }}
        />
      </button>
      {label && <span className="text-sm text-[var(--fg-2)]">{label}</span>}
    </label>
  );
}
