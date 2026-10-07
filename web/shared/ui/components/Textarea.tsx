'use client';

import { forwardRef } from 'react';

// Não existia no design system — 1º consumidor é a observação de cobrança do
// Financeiro. Mesma folha de estilo do Input (Controls.tsx), sem duplicar token.
const textareaCls =
  'w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg)] placeholder:text-[var(--fg-3)] shadow-[var(--shadow-xs)] ' +
  'px-3 py-2 text-sm leading-relaxed transition-[border-color,box-shadow,background-color,color] duration-[var(--dur-fast)] ease-[var(--ease-out)] ' +
  'hover:border-[var(--border-strong)] focus:border-[var(--border-accent)] focus:shadow-[var(--field-halo)] disabled:opacity-50 resize-y';

export const Textarea = forwardRef<HTMLTextAreaElement, React.TextareaHTMLAttributes<HTMLTextAreaElement>>(
  function Textarea({ className = '', rows = 3, ...rest }, ref) {
    return <textarea ref={ref} rows={rows} className={`${textareaCls} ${className}`} {...rest} />;
  },
);
