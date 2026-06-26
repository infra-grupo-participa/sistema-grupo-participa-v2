'use client';

import { useCallback, useEffect, useState } from 'react';

type Theme = 'dark' | 'light';
const KEY = 'gp_theme';

/** Tema claro/escuro persistido em localStorage. Porta de GPTheme (auth.js). */
export function useTheme() {
  const [theme, setTheme] = useState<Theme>('dark');

  useEffect(() => {
    // Sincroniza com o tema já aplicado ao DOM pelo script inline do layout (fonte externa).
    const stored = (typeof window !== 'undefined' && localStorage.getItem(KEY)) as Theme | null;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (stored === 'dark' || stored === 'light') setTheme(stored);
  }, []);

  const apply = useCallback((t: Theme) => {
    setTheme(t);
    document.documentElement.setAttribute('data-theme', t);
    try {
      localStorage.setItem(KEY, t);
    } catch {
      /* ignore */
    }
  }, []);

  const toggle = useCallback(() => apply(theme === 'dark' ? 'light' : 'dark'), [theme, apply]);

  return { theme, toggle };
}
