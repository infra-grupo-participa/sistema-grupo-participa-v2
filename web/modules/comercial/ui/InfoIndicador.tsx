'use client';

// Ícone (i) ao lado de um indicador: clicar abre um pop-up com o que o número representa, como é contado,
// para que serve e a meta. O texto vem de `domain/metricas.ts` (fonte única) ou, para indicador próprio de uma
// tela, de `texto`. Teclado: Enter/Espaço abre, Esc fecha e devolve o foco.
import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import { METRICAS } from '../domain/metricas';
import type { MetricaKey } from '../domain/types';

export interface TextoIndicador {
  nome: string;
  oQueE: string;
  comoConta?: string;
  paraQue?: string;
  meta?: string | null;
}

export function InfoIndicador({ metrica, texto, className = '' }: { metrica?: MetricaKey; texto?: TextoIndicador; className?: string }) {
  const def: TextoIndicador | undefined = texto ?? (metrica ? METRICAS[metrica] : undefined);
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const botao = useRef<HTMLButtonElement>(null);
  const idPainel = useId();
  const painel = useRef<HTMLSpanElement>(null);
  // Deslocamento horizontal para o pop-up não sair da tela (borda da gaveta, última coluna).
  const [desloc, setDesloc] = useState(0);

  useLayoutEffect(() => {
    if (!aberto || !painel.current) return;
    const r = painel.current.getBoundingClientRect();
    const margem = 12;
    let dx = 0;
    if (r.right > window.innerWidth - margem) dx = window.innerWidth - margem - r.right;
    if (r.left + dx < margem) dx = margem - r.left;
    // Ajuste medido do DOM depois de abrir (layout externo).
     
    setDesloc(dx);
  }, [aberto]);

  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') { setAberto(false); botao.current?.focus(); } };
    document.addEventListener('mousedown', fora);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc); };
  }, [aberto]);

  if (!def) return null;
  return (
    <span ref={ref} className={`relative inline-flex align-middle ${className}`}>
      <button
        ref={botao}
        type="button"
        aria-label={`O que é: ${def.nome}`}
        aria-expanded={aberto}
        aria-controls={idPainel}
        onClick={(e) => { e.stopPropagation(); setDesloc(0); setAberto((a) => !a); }}
        className="grid place-items-center w-5 h-5 rounded-full text-[var(--fg-4)] hover:text-[var(--fg-2)] hover:bg-[var(--surface-3)] focus-visible:text-[var(--fg)]"
      >
        <InfoGlyph />
      </button>
      {aberto && (
        <span
          ref={painel}
          id={idPainel}
          style={{ marginLeft: desloc }}
          role="dialog"
          aria-label={def.nome}
          onClick={(e) => e.stopPropagation()}
          className="absolute left-1/2 top-full z-40 mt-1.5 w-[min(300px,calc(100vw-32px))] -translate-x-1/2 rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-3 text-left shadow-[var(--highlight-surface),var(--shadow-lg)] gp-pop-in origin-top"
        >
          <span className="block text-[13px] font-semibold text-[var(--fg)]">{def.nome}</span>
          <span className="mt-1 block text-xs leading-relaxed text-[var(--fg-2)]">{def.oQueE}</span>
          {def.comoConta && <Linha rotulo="Como conta" texto={def.comoConta} />}
          {def.paraQue && <Linha rotulo="Para que serve" texto={def.paraQue} />}
          {def.meta && <Linha rotulo="Meta" texto={def.meta} />}
        </span>
      )}
    </span>
  );
}

function Linha({ rotulo, texto }: { rotulo: string; texto: string }) {
  return (
    <span className="mt-2 block text-xs leading-relaxed">
      <span className="block text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</span>
      <span className="text-[var(--fg-2)]">{texto}</span>
    </span>
  );
}

/** "i" num círculo, herdando currentColor. */
function InfoGlyph() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5" />
      <path d="M12 8h.01" />
    </svg>
  );
}
