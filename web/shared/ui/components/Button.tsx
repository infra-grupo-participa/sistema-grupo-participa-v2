'use client';

import { forwardRef } from 'react';

type Variant = 'primary' | 'ghost' | 'danger' | 'success' | 'subtle';
type Size = 'sm' | 'md';

const VARIANTS: Record<Variant, string> = {
  primary: 'bg-[var(--accent)] text-black hover:brightness-110 border border-transparent',
  success: 'bg-[var(--green)] text-black hover:brightness-110 border border-transparent',
  danger: 'bg-transparent text-[var(--red)] border border-[var(--red-border)] hover:bg-[var(--red-subtle)]',
  ghost: 'bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]',
  subtle: 'bg-[var(--surface-3)] text-[var(--fg)] border border-[var(--border)] hover:bg-[var(--surface-4)]',
};
const SIZES: Record<Size, string> = { sm: 'px-3 py-1.5 text-xs', md: 'px-4 py-2 text-sm' };

interface Props extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
}

export const Button = forwardRef<HTMLButtonElement, Props>(function Button(
  { variant = 'primary', size = 'md', className = '', ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      className={`inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] font-semibold transition-[filter,background,border-color,color] duration-150 disabled:opacity-50 disabled:cursor-not-allowed ${VARIANTS[variant]} ${SIZES[size]} ${className}`}
      {...rest}
    />
  );
});
