'use client';

import { useEffect } from 'react';
import { Button } from './Button';
import { Icon } from '@/shared/ui/icons';

/** Modal centralizado com overlay e animação (paridade .modal-overlay/.modal do legado). */
export function Modal({ open = true, onClose, title, children, footer, width = 'max-w-lg' }: {
  open?: boolean; onClose: () => void; title?: React.ReactNode; children: React.ReactNode; footer?: React.ReactNode; width?: string;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[1000] flex items-center justify-center p-4">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-[var(--scrim)] backdrop-blur-[2px] gp-overlay-in" />
      <div className={`relative w-full ${width} max-h-[90vh] overflow-y-auto rounded-[var(--r-xl)] border border-[var(--border-strong)] bg-[var(--surface-2)] shadow-[var(--highlight-surface),var(--shadow-overlay)] gp-modal-in overscroll-contain`}>
        {title && (
          <div className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-[var(--border)] bg-[color-mix(in_srgb,var(--surface-2)_88%,transparent)] backdrop-blur-md px-5 py-3.5">
            <h2 className="text-base font-semibold text-[var(--fg)]">{title}</h2>
            <button onClick={onClose} aria-label="Fechar" className="gp-press w-8 h-8 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"><Icon name="x" /></button>
          </div>
        )}
        <div className="p-5">{children}</div>
        {footer && <div className="flex flex-wrap justify-end gap-2 border-t border-[var(--border)] bg-[var(--surface-1)]/40 px-5 py-3.5 rounded-b-[var(--r-xl)]">{footer}</div>}
      </div>
    </div>
  );
}

/** Diálogo de confirmação binário (paridade #confirm-overlay/#confirm-box). */
export function ConfirmDialog({ open = true, onConfirm, onCancel, title = 'Confirmar', message, confirmLabel = 'Confirmar', cancelLabel = 'Cancelar', danger = false }: {
  open?: boolean; onConfirm: () => void; onCancel: () => void; title?: string; message: React.ReactNode; confirmLabel?: string; cancelLabel?: string; danger?: boolean;
}) {
  return (
    <Modal
      open={open}
      onClose={onCancel}
      title={title}
      width="max-w-sm"
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={onCancel}>{cancelLabel}</Button>
          <Button variant={danger ? 'danger' : 'primary'} size="sm" onClick={onConfirm}>{confirmLabel}</Button>
        </>
      }
    >
      <p className="text-sm text-[var(--fg-2)] leading-relaxed">{message}</p>
    </Modal>
  );
}
