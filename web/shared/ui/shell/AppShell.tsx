'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import type { GpUser } from '@/shared/domain/auth';

const COLLAPSE_KEY = 'gp_sidebar_collapsed';

/** Casca autenticada: header + sidebar colapsável (desktop) / drawer (mobile) + conteúdo. */
export function AppShell({ user, children }: { user: GpUser; children: React.ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const pathname = usePathname();

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (localStorage.getItem(COLLAPSE_KEY) === '1') setCollapsed(true);
  }, []);

  const toggleCollapse = () =>
    setCollapsed((c) => {
      const next = !c;
      try {
        localStorage.setItem(COLLAPSE_KEY, next ? '1' : '0');
      } catch {
        /* ignore */
      }
      return next;
    });

  return (
    <div className="h-dvh flex flex-col overflow-hidden">
      <Header
        user={user}
        onToggleSidebar={() => setMobileOpen((v) => !v)}
        collapsed={collapsed}
        onToggleCollapse={toggleCollapse}
      />
      <div className="flex flex-1 min-h-0">
        {/* Sidebar desktop — recolhível (anima a largura para liberar área de trabalho) */}
        <div
          className={`hidden md:block shrink-0 overflow-hidden transition-[width] duration-300 ease-in-out ${collapsed ? 'w-0' : 'w-[var(--sidebar-width)]'}`}
        >
          <Sidebar user={user} />
        </div>

        {/* Sidebar mobile — drawer sobreposto */}
        <div
          className={`${mobileOpen ? 'fixed inset-y-0 left-0 z-50 pt-[var(--header-height)]' : 'hidden'} md:hidden`}
        >
          <Sidebar user={user} />
        </div>
        {mobileOpen && (
          <button
            type="button"
            aria-label="Fechar navegação"
            onClick={() => setMobileOpen(false)}
            className="fixed inset-0 z-40 bg-black/45 md:hidden"
          />
        )}
        <main className="flex-1 min-w-0 overflow-auto p-4 sm:p-6 bg-[var(--surface-0)]">
          {/* key por rota → fade sutil a cada navegação (percepção de fluidez, sem quebrar densidade) */}
          <div key={pathname} className="gp-fade-in">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
