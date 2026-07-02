'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Feedback efêmero de ação ("Feito!", "Falhou.") — um por vez, some sozinho.
 * Flashes consecutivos reiniciam o relógio (o antigo setTimeout solto cortava o toast novo).
 */
export function useFlash(duracaoMs = 3000): { toast: string; flash: (msg: string) => void } {
  const [toast, setToast] = useState('');
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const flash = useCallback((msg: string) => {
    setToast(msg);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setToast(''), duracaoMs);
  }, [duracaoMs]);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  return { toast, flash };
}

/** Balão fixo do useFlash. Renderiza nada quando a mensagem está vazia. */
export function Toast({ children }: { children: React.ReactNode }) {
  if (!children) return null;
  return (
    <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]" role="status">
      {children}
    </div>
  );
}
