'use client';

import { useState } from 'react';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import type { GpUser } from '@/shared/domain/auth';

/** Casca autenticada: header + sidebar colapsável + área de conteúdo. */
export function AppShell({ user, children }: { user: GpUser; children: React.ReactNode }) {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="h-dvh flex flex-col overflow-hidden">
      <Header user={user} onToggleSidebar={() => setMobileOpen((v) => !v)} />
      <div className="flex flex-1 min-h-0">
        {/* Sidebar: fixa no desktop, drawer no mobile */}
        <div
          className={`${mobileOpen ? 'fixed inset-y-0 left-0 z-50 pt-[var(--header-height)]' : 'hidden'} md:static md:block md:pt-0`}
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
          {children}
        </main>
      </div>
    </div>
  );
}
