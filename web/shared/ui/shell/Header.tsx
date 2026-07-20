'use client';

import { useRouter } from 'next/navigation';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { useTheme } from './use-theme';
import { Icon } from '@/shared/ui/icons';
import type { GpUser } from '@/shared/domain/auth';

export function Header({
  user,
  onToggleSidebar,
  collapsed,
  onToggleCollapse,
}: {
  user: GpUser;
  onToggleSidebar?: () => void;
  collapsed?: boolean;
  onToggleCollapse?: () => void;
}) {
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
          <Icon name="menu" size={18} />
        </button>
      )}
      {onToggleCollapse && (
        <button
          type="button"
          onClick={onToggleCollapse}
          aria-label={collapsed ? 'Expandir menu lateral' : 'Recolher menu lateral'}
          title={collapsed ? 'Expandir menu' : 'Recolher menu'}
          className="hidden md:grid w-9 h-9 place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--accent)] hover:border-[var(--border-accent)] hover:bg-[var(--accent-subtle)] transition-colors"
        >
          <Icon name={collapsed ? 'panel-open' : 'panel-close'} size={18} />
        </button>
      )}
      {/* Logo no header só quando NÃO está visível na sidebar: sempre no mobile (drawer),
          e no desktop apenas com a sidebar recolhida — evita a marca duplicada. */}
      <div className={collapsed ? 'block' : 'md:hidden'}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/images/logo-grupo-participa-branco.svg" alt="Grupo Participa" className="gp-logo-dark h-6 w-auto" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/images/logo-grupo-participa-preto.svg" alt="Grupo Participa" className="gp-logo-light h-6 w-auto" />
      </div>

      <div className="ml-auto flex items-center gap-3">
        <span className="text-xs px-2 py-1 rounded-[var(--r-pill)] bg-[var(--surface-3)] text-[var(--fg-2)] capitalize">
          {user.cargo}
        </span>
        <span className="text-sm text-[var(--fg)] max-w-[200px] truncate hidden sm:inline">
          {user.nome || 'Usuário'}
        </span>
        <div className="w-8 h-8 grid place-items-center rounded-full bg-[var(--accent)] text-black font-semibold text-sm ring-1 ring-[var(--border-accent)] select-none">
          {inicial}
        </div>
        <button
          type="button"
          onClick={toggle}
          aria-label="Alternar tema"
          title="Alternar tema claro/escuro"
          className="w-8 h-8 grid place-items-center rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--accent)] hover:border-[var(--border-accent)] hover:bg-[var(--accent-subtle)] transition-colors"
        >
          <Icon name={theme === 'dark' ? 'sun' : 'moon'} />
        </button>
        <button
          type="button"
          onClick={logout}
          className="text-sm px-3 py-1.5 rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"
        >
          Sair
        </button>
      </div>
    </header>
  );
}
