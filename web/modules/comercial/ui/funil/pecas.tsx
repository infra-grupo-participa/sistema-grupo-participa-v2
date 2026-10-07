'use client';

// Peças do funil: popover/menu (posição fixa, não corta dentro da coluna que rola) e altura útil do kanban.
// Faixa de números, aviso e segmentado vêm de '../comum'.
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';

// ── Popover ──

type Lado = { top?: number; bottom?: number; left?: number; right?: number };

/** Caixa flutuante ancorada num botão. Fecha com Esc, clique fora, rolagem ou redimensionar; devolve o foco. */
export function Popover({ ancora, aberto, onFechar, alinhar = 'direita', largura = 240, rotulo, role = 'dialog', children }: {
  ancora: React.RefObject<HTMLElement | null>;
  aberto: boolean;
  onFechar: () => void;
  alinhar?: 'esquerda' | 'direita';
  largura?: number;
  rotulo: string;
  role?: 'dialog' | 'menu';
  children: React.ReactNode;
}) {
  const caixa = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<Lado | null>(null);

  useLayoutEffect(() => {
    if (!aberto || !ancora.current) return;
    const r = ancora.current.getBoundingClientRect();
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const p: Lado = {};
    if (vh - r.bottom < 280 && r.top > vh - r.bottom) p.bottom = vh - r.top + 4; else p.top = r.bottom + 4;
    if (alinhar === 'direita') p.right = Math.max(8, vw - r.right); else p.left = Math.min(r.left, vw - largura - 8);
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPos(p);
  }, [aberto, ancora, alinhar, largura]);

  useEffect(() => {
    if (!aberto) return;
    const fechar = () => onFechar();
    const fora = (e: MouseEvent) => {
      const t = e.target as Node;
      if (caixa.current?.contains(t) || ancora.current?.contains(t)) return;
      onFechar();
    };
    const rolou = (e: Event) => { if (!caixa.current?.contains(e.target as Node)) onFechar(); };
    const tecla = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.stopPropagation();
      onFechar();
      ancora.current?.focus();
    };
    document.addEventListener('mousedown', fora);
    window.addEventListener('scroll', rolou, true);
    window.addEventListener('resize', fechar);
    window.addEventListener('keydown', tecla, true);
    return () => {
      document.removeEventListener('mousedown', fora);
      window.removeEventListener('scroll', rolou, true);
      window.removeEventListener('resize', fechar);
      window.removeEventListener('keydown', tecla, true);
    };
  }, [aberto, onFechar, ancora]);

  if (!aberto || !pos) return null;
  return (
    <div
      ref={caixa}
      role={role}
      aria-label={rotulo}
      style={{ ...pos, width: largura, maxWidth: 'calc(100vw - 16px)' }}
      className="fixed z-[950] max-h-[min(70vh,480px)] overflow-y-auto overscroll-contain rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-1 shadow-[var(--highlight-surface),var(--shadow-lg)] gp-pop-in"
    >
      {children}
    </div>
  );
}

// ── Menu ──

export interface ItemMenu {
  rotulo: string;
  icone?: string;
  dica?: string;
  /** Texto completo no title (ex.: a lista de campos que faltam). */
  titulo?: string;
  desativado?: boolean;
  ativo?: boolean;
  onEscolher?: () => void;
  /** Linha de título de grupo (não clicável). */
  grupo?: boolean;
}

/** Botão + menu (role=menu): setas sobem/descem, Enter escolhe, Esc fecha e devolve o foco. */
export function Menu({ rotulo, itens, gatilho, classeGatilho = '', largura = 232 }: {
  rotulo: string;
  itens: ItemMenu[];
  gatilho: React.ReactNode;
  classeGatilho?: string;
  largura?: number;
}) {
  const [aberto, setAberto] = useState(false);
  const botao = useRef<HTMLButtonElement>(null);
  const lista = useRef<HTMLDivElement>(null);
  const fechar = useCallback(() => setAberto(false), []);

  const focaveis = () => Array.from(lista.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not([disabled])') ?? []);
  useEffect(() => {
    if (!aberto) return;
    const t = setTimeout(() => focaveis()[0]?.focus(), 0);
    return () => clearTimeout(t);
  }, [aberto]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    const fs = focaveis();
    const i = fs.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === 'ArrowDown') { e.preventDefault(); fs[(i + 1) % fs.length]?.focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); fs[(i - 1 + fs.length) % fs.length]?.focus(); }
    else if (e.key === 'Home') { e.preventDefault(); fs[0]?.focus(); }
    else if (e.key === 'End') { e.preventDefault(); fs[fs.length - 1]?.focus(); }
    else if (e.key === 'Tab') setAberto(false);
  };

  return (
    <>
      <button
        ref={botao}
        type="button"
        aria-label={rotulo}
        title={rotulo}
        aria-haspopup="menu"
        aria-expanded={aberto}
        draggable={false}
        onClick={(e) => { e.stopPropagation(); setAberto((v) => !v); }}
        className={classeGatilho}
      >
        {gatilho}
      </button>
      <Popover ancora={botao} aberto={aberto} onFechar={fechar} rotulo={rotulo} role="menu" largura={largura}>
        <div ref={lista} onKeyDown={onKeyDown}>
          {itens.map((it, i) => it.grupo ? (
            <div key={i} role="presentation" className="px-2 pt-2 pb-1 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">{it.rotulo}</div>
          ) : (
            <button
              key={i}
              type="button"
              role="menuitem"
              disabled={it.desativado}
              title={it.titulo}
              aria-current={it.ativo ? 'true' : undefined}
              tabIndex={-1}
              onClick={() => { setAberto(false); botao.current?.focus(); it.onEscolher?.(); }}
              className="w-full flex items-center gap-2 min-h-8 px-2 py-1 rounded-[var(--r-sm)] text-left text-sm text-[var(--fg)] hover:bg-[var(--surface-4)] focus-visible:bg-[var(--surface-4)] disabled:text-[var(--fg-3)] disabled:hover:bg-transparent disabled:cursor-not-allowed"
            >
              <span className="w-4 shrink-0 grid place-items-center text-[var(--fg-3)]">
                {it.ativo ? <Icon name="check" size={14} /> : it.icone ? <Icon name={it.icone} size={14} /> : null}
              </span>
              <span className="flex-1 truncate">{it.rotulo}</span>
              {it.dica && <span className="shrink-0 text-[11px] text-[var(--fg-3)]">{it.dica}</span>}
            </button>
          ))}
        </div>
      </Popover>
    </>
  );
}

// ── Altura útil ──

/**
 * Altura que sobra da janela abaixo do elemento (menos a folga do padding do content-area). Substitui
 * alturas mágicas tipo calc(100dvh-340px), que quebravam quando o aviso de demonstração some ou cresce.
 */
export function useAlturaRestante<T extends HTMLElement>(folga = 24, minimo = 360): [(el: T | null) => void, number | null] {
  // Ref por callback: o elemento só aparece depois da carga, e a medida precisa rodar quando ele chega.
  const [el, setEl] = useState<T | null>(null);
  const [altura, setAltura] = useState<number | null>(null);
  useEffect(() => {
    if (!el) return;
    const medir = () => {
      const topo = el.getBoundingClientRect().top + (el.closest('main')?.scrollTop ?? 0);
      setAltura(Math.max(minimo, Math.floor(window.innerHeight - topo - folga)));
    };
    medir();
    window.addEventListener('resize', medir);
    // O que fica acima (aviso, cabeçalho, faixa) pode mudar de altura depois da carga.
    const ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(medir) : null;
    const pagina = el.closest('main')?.firstElementChild ?? el.parentElement;
    if (ro && pagina) ro.observe(pagina);
    return () => { window.removeEventListener('resize', medir); ro?.disconnect(); };
  }, [el, folga, minimo]);
  return [setEl, altura];
}
