'use client';

// Peças de layout da caixa de conversas: altura que ocupa o resto da tela e o menu de respostas rápidas.
// Sem regra de negócio aqui.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';

/**
 * Altura que sobra na área de conteúdo abaixo do elemento (sem número mágico): acompanha o aviso de
 * demonstração e o cabeçalho, que podem quebrar linha ou sumir. Mínimo para notebook baixo.
 */
export function useAlturaDisponivel<T extends HTMLElement>(minimo = 480) {
  const ref = useRef<T>(null);
  const [altura, setAltura] = useState<number | null>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    const area = el?.closest('main');
    if (!el || !area) return;
    const medir = () => {
      const estilo = getComputedStyle(area);
      const topo = el.getBoundingClientRect().top - area.getBoundingClientRect().top + area.scrollTop;
      const livre = area.clientHeight - topo - parseFloat(estilo.paddingBottom || '0');
      setAltura(Math.max(minimo, Math.floor(livre)));
    };
    medir();
    // Observa a área e o bloco da página (aviso que some, cabeçalho que quebra linha). O topo medido
    // não depende da altura do próprio elemento, então não entra em laço.
    const ro = new ResizeObserver(medir);
    ro.observe(area);
    if (el.parentElement) ro.observe(el.parentElement);
    return () => ro.disconnect();
  }, [minimo]);
  return { ref, altura };
}

/**
 * Menu de respostas rápidas (popover acima do campo). Abre focado no primeiro item;
 * setas navegam, Enter escolhe, Esc fecha e devolve o foco a quem abriu.
 */
export function MenuRespostas({ id, frases, ancora, onEscolher, onFechar }: {
  id: string; frases: string[]; onEscolher: (f: string) => void; onFechar: () => void;
  /** Botão que abre o menu: clicar nele não conta como "fora" (ele mesmo alterna). */
  ancora?: React.RefObject<HTMLElement | null>;
}) {
  const caixa = useRef<HTMLDivElement>(null);
  const itens = useRef<(HTMLButtonElement | null)[]>([]);
  // A função mais recente fica num ref: o efeito roda só ao abrir (foco no 1º item uma vez).
  const fechar = useRef(onFechar);
  useEffect(() => { fechar.current = onFechar; });
  useEffect(() => {
    itens.current[0]?.focus();
    const fora = (e: MouseEvent) => {
      const alvo = e.target as Node;
      if (!caixa.current?.contains(alvo) && !ancora?.current?.contains(alvo)) fechar.current();
    };
    document.addEventListener('mousedown', fora);
    return () => document.removeEventListener('mousedown', fora);
  }, [ancora]);
  const onKeyDown = (e: React.KeyboardEvent, i: number) => {
    const n = frases.length;
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); onFechar(); return; }
    if (e.key === 'Tab') { onFechar(); return; }
    const j = e.key === 'ArrowDown' ? (i + 1) % n : e.key === 'ArrowUp' ? (i - 1 + n) % n
      : e.key === 'Home' ? 0 : e.key === 'End' ? n - 1 : null;
    if (j == null) return;
    e.preventDefault();
    itens.current[j]?.focus();
  };
  return (
    <div
      ref={caixa}
      id={id}
      role="menu"
      aria-label="Respostas rápidas"
      className="absolute bottom-full left-0 right-0 mb-2 z-20 rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-1 shadow-[var(--shadow-md)] gp-fade-in"
    >
      <div className="px-2 pt-1 pb-1.5 text-[11px] text-[var(--fg-3)]">Respostas rápidas do playbook · Enter insere</div>
      {frases.map((f, i) => (
        <button
          key={f}
          ref={(el) => { itens.current[i] = el; }}
          type="button"
          role="menuitem"
          onClick={() => onEscolher(f)}
          onKeyDown={(e) => onKeyDown(e, i)}
          className="w-full text-left rounded-[var(--r-md)] px-3 py-2 text-sm text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)] focus-visible:bg-[var(--surface-3)] focus-visible:text-[var(--fg)] outline-none"
        >
          {f}
        </button>
      ))}
    </div>
  );
}
