'use client';

import { useRouter } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { useTheme } from './use-theme';
import type { GpUser } from '@/shared/domain/auth';

export function Header({ user, onToggleSidebar }: { user: GpUser; onToggleSidebar?: () => void }) {
  const router = useRouter();
  const { theme, toggle } = useTheme();

  async function logout() {
    const supabase = createBrowserSupabase();
    await supabase.auth.signOut();
    router.push('/login');
    router.refresh();
  }

  const inicial = (user.nome || 'U').charAt(0).toUpperCase();

  return (
    <header className="h-[var(--header-height)] shrink-0 flex items-center gap-3 px-4 bg-[var(--surface-1)] border-b border-[var(--border)]">
      {onToggleSidebar && (
        <button
          type="button"
          onClick={onToggleSidebar}
          aria-label="Alternar navegação"
          className="md:hidden w-9 h-9 grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg)]"
        >
          ☰
        </button>
      )}
      <span className="font-bold text-[var(--accent)] tracking-tight">Grupo Participa</span>

      <div className="ml-auto flex items-center gap-3">
        <span className="text-xs px-2 py-1 rounded-[var(--r-pill)] bg-[var(--surface-3)] text-[var(--fg-2)] capitalize">
          {user.cargo}
        </span>
        <span className="text-sm text-[var(--fg)] max-w-[200px] truncate hidden sm:inline">
          {user.nome || 'Usuário'}
        </span>
        <div className="w-8 h-8 grid place-items-center rounded-full bg-[var(--accent)] text-black font-semibold text-sm">
          {inicial}
        </div>
        <button
          type="button"
          onClick={toggle}
          aria-label="Alternar tema"
          title="Alternar tema claro/escuro"
          className="w-8 h-8 grid place-items-center rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)]"
        >
          {theme === 'dark' ? '☀' : '☾'}
        </button>
        <button
          type="button"
          onClick={logout}
          className="text-sm px-3 py-1.5 rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)]"
        >
          Sair
        </button>
      </div>
    </header>
  );
}
