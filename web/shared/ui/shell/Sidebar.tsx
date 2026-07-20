'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ehAdminOuAcima, ehDev, podeVer, type GpUser } from '@/shared/domain/auth';
import { podeVerFinanceiro } from '@/modules/financeiro/domain/acesso';
import { REPORTS, SYSTEM_NAV, type ReportGroup } from '@/shared/ui/nav/config';
import { Icon } from '@/shared/ui/icons';

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
  // Hash atual da URL — usado para destacar a aba ativa dos itens hash-nav.
  const [hash, setHash] = useState('');
  useEffect(() => {
    // Restaura o estado de colapso persistido (localStorage = sistema externo).
    /* eslint-disable react-hooks/set-state-in-effect */
    setGroups(loadState(GROUPS_KEY));
    setReports(loadState(REPORTS_KEY));
    setHash(window.location.hash || '');
    /* eslint-enable react-hooks/set-state-in-effect */
    const sync = () => setHash(window.location.hash || '');
    window.addEventListener('hashchange', sync);
    return () => window.removeEventListener('hashchange', sync);
  }, []);
  // Nav entre páginas (Next Link) muda o pathname mas nem sempre dispara 'hashchange';
  // re-sincroniza o hash quando a rota troca.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setHash(window.location.hash || '');
  }, [pathname]);

  /**
   * Clique num item hash-nav (ex.: #agenda-horarios) quando já estamos na mesma rota.
   * O <Link> do Next atualiza a URL mas não dispara 'hashchange' para hash-na-mesma-rota,
   * então setamos window.location.hash à mão para emitir o evento que a página escuta.
   */
  const onHashChildClick = (e: React.MouseEvent, childPath: string, childHash?: string) => {
    if (!childHash || normalize(childPath) !== cur) return; // rota diferente: deixa o Link navegar
    e.preventDefault();
    // pushState (não location.hash=) atualiza a URL sem recarregar; o hashchange manual
    // avisa a página e a própria sidebar a re-sincronizarem a aba ativa.
    if ((window.location.hash || '') !== childHash) window.history.pushState(null, '', childHash);
    window.dispatchEvent(new HashChangeEvent('hashchange'));
  };

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

  // O grupo aparece se o cargo permite E o usuário tem o setor.
  // Financeiro tem regra própria (visualizador NÃO vê dinheiro) — espelha
  // gp_pode_ver_financeiro() no banco, senão a tela abriria vazia.
  const podeVerGrupo = (g: ReportGroup) => {
    if (g.adminOnly && !isAdmin) return false;
    if (g.setor === 'financeiro') return podeVerFinanceiro(user);
    return podeVer(user, g.setor);
  };

  const itemCls = (active: boolean) =>
    `group/item relative flex items-center gap-2.5 pl-3 pr-2 py-2 rounded-[var(--r-md)] text-sm cursor-pointer transition-colors duration-150 ${
      active
        ? 'bg-[var(--accent-subtle)] text-[var(--fg)] font-medium before:absolute before:left-0 before:top-1/2 before:-translate-y-1/2 before:h-4 before:w-[3px] before:rounded-full before:bg-[var(--accent)]'
        : 'text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]'
    }`;
  // Ícone: âmbar no item ativo (assinatura da marca) e no hover; herda a cor do texto no repouso.
  const iconBoxCls = (active: boolean) =>
    `grid place-items-center w-6 h-6 rounded-[var(--r-sm)] text-[13px] shrink-0 transition-colors duration-150 ${
      active ? 'text-[var(--accent)]' : 'text-[var(--fg-3)] group-hover/item:text-[var(--accent)]'
    }`;

  return (
    <aside className="w-[var(--sidebar-width)] shrink-0 h-full overflow-y-auto bg-[var(--surface-1)] border-r border-[var(--border)] px-3 py-4 flex flex-col gap-1">
      {/* Marca */}
      <div className="px-3 pb-3 mb-1 border-b border-[var(--border-faint)]">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/images/logo-grupo-participa-branco.svg" alt="Grupo Participa" className="gp-logo-dark h-7 w-auto" />
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/images/logo-grupo-participa-preto.svg" alt="Grupo Participa" className="gp-logo-light h-7 w-auto" />
        <div className="text-[10px] text-[var(--fg-3)] capitalize mt-1.5">{user.cargo}</div>
      </div>

      {/* Início */}
      <Group label="Início" collapsed={!!groups.home} onToggle={() => toggleGroup('home')}>
        <Link href="/" className={itemCls(cur === '/')}>
          <span className={iconBoxCls(cur === '/')}><Icon name="home" /></span>
          <span>Início</span>
        </Link>
      </Group>

      <Divider />

      {/* Relatórios */}
      <Group label="Relatórios" collapsed={!!groups.reports} onToggle={() => toggleGroup('reports')}>
        {REPORTS.filter(podeVerGrupo).map((group) => {
          const onGroup = normalize(group.path) === cur;
          const open = reports[group.key] ?? onGroup;
          const children = group.children.filter((c) => !c.adminOnly || isAdmin);
          return (
            <div key={group.key}>
              <div className={itemCls(onGroup)}>
                <Link href={group.defaultHref} className="flex items-center gap-2.5 flex-1 min-w-0">
                  <span className={iconBoxCls(onGroup)}><Icon name={group.ico || 'clipboard'} /></span>
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
                    <Icon name={open ? 'chevron-down' : 'chevron-right'} size={14} />
                  </button>
                )}
              </div>
              {children.length > 0 && open && (
                <div className="ml-4 mt-0.5 flex flex-col gap-0.5">
                  {(() => {
                    const defaultHashKey = children.find((c) => c.hash)?.key;
                    return children.map((child) => {
                      const onPath = normalize(child.path) === cur;
                      const active = child.hash
                        ? onPath && (hash === child.hash || (!hash && child.key === defaultHashKey))
                        : onPath;
                      return (
                        <Link
                          key={child.key}
                          href={child.href}
                          onClick={(e) => onHashChildClick(e, child.path, child.hash)}
                          className={itemCls(active)}
                        >
                          <span className={iconBoxCls(active)}><Icon name={child.ico || 'circle'} size={14} /></span>
                          <span>{child.label}</span>
                        </Link>
                      );
                    });
                  })()}
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
              <span className={iconBoxCls(active)}><Icon name={item.ico || 'circle'} /></span>
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
        className="group/grp w-full flex items-center justify-between px-3 py-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)] hover:text-[var(--fg-2)] transition-colors rounded-[var(--r-sm)]"
      >
        <span>{label}</span>
        <Icon name={collapsed ? 'chevron-up' : 'chevron-down'} size={14} className="text-[var(--fg-4)] group-hover/grp:text-[var(--fg-2)] transition-colors" />
      </button>
      {!collapsed && <div className="flex flex-col gap-0.5">{children}</div>}
    </div>
  );
}

function Divider() {
  return <div className="my-2 border-t border-[var(--border-faint)]" />;
}
