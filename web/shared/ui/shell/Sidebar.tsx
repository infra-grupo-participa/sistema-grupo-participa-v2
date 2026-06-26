'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ehAdminOuAcima, ehDev, type GpUser } from '@/shared/domain/auth';
import { REPORTS, SYSTEM_NAV } from '@/shared/ui/nav/config';

const GROUPS_KEY = 'gp_sidebar_groups';
const REPORTS_KEY = 'gp_reports_nav_state';

function loadState(key: string): Record<string, boolean> {
  try {
    return JSON.parse(localStorage.getItem(key) || '{}');
  } catch {
    return {};
  }
}

function normalize(p: string): string {
  return (p || '/').replace(/\/$/, '') || '/';
}

export function Sidebar({ user }: { user: GpUser }) {
  const pathname = usePathname();
  const isAdmin = ehAdminOuAcima(user);
  const isDev = ehDev(user);

  // Estado de colapso dos grupos e subgrupos (persistido).
  const [groups, setGroups] = useState<Record<string, boolean>>({});
  const [reports, setReports] = useState<Record<string, boolean>>({});
  useEffect(() => {
    // Restaura o estado de colapso persistido (localStorage = sistema externo).
    /* eslint-disable react-hooks/set-state-in-effect */
    setGroups(loadState(GROUPS_KEY));
    setReports(loadState(REPORTS_KEY));
    /* eslint-enable react-hooks/set-state-in-effect */
  }, []);

  const toggleGroup = (name: string) => {
    setGroups((prev) => {
      const next = { ...prev, [name]: !prev[name] };
      localStorage.setItem(GROUPS_KEY, JSON.stringify(next));
      return next;
    });
  };
  const toggleReport = (key: string) => {
    setReports((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      localStorage.setItem(REPORTS_KEY, JSON.stringify(next));
      return next;
    });
  };

  const cur = normalize(pathname);
  const itemCls = (active: boolean) =>
    `relative flex items-center gap-2.5 pl-3 pr-2 py-2 rounded-[var(--r-md)] text-sm cursor-pointer transition-colors duration-150 ${
      active
        ? 'bg-[var(--accent-subtle)] text-[var(--fg)] font-medium before:absolute before:left-0 before:top-1/2 before:-translate-y-1/2 before:h-4 before:w-[3px] before:rounded-full before:bg-[var(--accent)]'
        : 'text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]'
    }`;
  const iconBox = 'grid place-items-center w-6 h-6 rounded-[var(--r-sm)] text-[13px] shrink-0';

  return (
    <aside className="w-[var(--sidebar-width)] shrink-0 h-full overflow-y-auto bg-[var(--surface-1)] border-r border-[var(--border)] px-3 py-4 flex flex-col gap-1">
      {/* Marca */}
      <div className="px-3 pb-3 mb-1 border-b border-[var(--border-faint)]">
        <div className="flex items-center gap-2">
          <span className="grid place-items-center w-7 h-7 rounded-[var(--r-md)] bg-[var(--accent)] text-black font-bold text-sm">GP</span>
          <div className="leading-tight">
            <div className="text-sm font-bold text-[var(--fg)]">Grupo Participa</div>
            <div className="text-[10px] text-[var(--fg-3)] capitalize">{user.cargo}</div>
          </div>
        </div>
      </div>

      {/* Início */}
      <Group label="Início" collapsed={!!groups.home} onToggle={() => toggleGroup('home')}>
        <Link href="/" className={itemCls(cur === '/')}>
          <span className={iconBox}>🏠</span>
          <span>Início</span>
        </Link>
      </Group>

      <Divider />

      {/* Relatórios */}
      <Group label="Relatórios" collapsed={!!groups.reports} onToggle={() => toggleGroup('reports')}>
        {REPORTS.filter((g) => !g.adminOnly || isAdmin).map((group) => {
          const onGroup = normalize(group.path) === cur;
          const open = reports[group.key] ?? onGroup;
          const children = group.children.filter((c) => !c.adminOnly || isAdmin);
          return (
            <div key={group.key}>
              <div className={itemCls(onGroup)}>
                <Link href={group.defaultHref} className="flex items-center gap-2.5 flex-1 min-w-0">
                  <span className={iconBox}>{group.emoji || '📋'}</span>
                  <span className="truncate">{group.label}</span>
                </Link>
                {children.length > 0 && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.preventDefault();
                      toggleReport(group.key);
                    }}
                    aria-label="Alternar subtópicos"
                    className="text-[var(--fg-3)] px-1"
                  >
                    {open ? '▾' : '▸'}
                  </button>
                )}
              </div>
              {children.length > 0 && open && (
                <div className="ml-4 mt-0.5 flex flex-col gap-0.5">
                  {children.map((child) => {
                    const active = normalize(child.path) === cur;
                    return (
                      <Link key={child.key} href={child.href} className={itemCls(active)}>
                        <span className={iconBox}>{child.emoji || '•'}</span>
                        <span>{child.label}</span>
                      </Link>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </Group>

      <Divider />

      {/* Sistema */}
      <Group label="Sistema" collapsed={!!groups.system} onToggle={() => toggleGroup('system')}>
        {SYSTEM_NAV.filter((i) => (!i.adminOnly || isAdmin) && (!i.devOnly || isDev)).map((item) => {
          const active =
            normalize(item.path) === cur ||
            (item.activePrefixes || []).some((p) => cur.startsWith(normalize(p) + '/'));
          return (
            <Link key={item.key} href={item.path} className={itemCls(active)}>
              <span className={iconBox}>{item.emoji || '▫'}</span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </Group>
    </aside>
  );
}

function Group({
  label,
  collapsed,
  onToggle,
  children,
}: {
  label: string;
  collapsed: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  return (
    <div>
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-center justify-between px-3 py-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]"
      >
        <span>{label}</span>
        <span>{collapsed ? '⌃' : '⌄'}</span>
      </button>
      {!collapsed && <div className="flex flex-col gap-0.5">{children}</div>}
    </div>
  );
}

function Divider() {
  return <div className="my-2 border-t border-[var(--border-faint)]" />;
}
