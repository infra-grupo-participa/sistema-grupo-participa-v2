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

/** Balão fixo do useFlash. Renderiza nada quando a mensagem está vazia.
 *  Visual e entrada em `.gp-toast` (globals.css): material translúcido que sobe
 *  de baixo via @starting-style — transição, não keyframe, como no Sonner. */
export function Toast({ children }: { children: React.ReactNode }) {
  if (!children) return null;
  return (
    <div className="gp-toast" role="status">
      {children}
    </div>
  );
}
