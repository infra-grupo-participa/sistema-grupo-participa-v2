'use client';

// Gaveta lateral da Jornada e dos criativos: 520 px à direita (abaixo de 640 px, tela inteira).
// Renderiza num portal no <body>, acima da barra do app (que é z-[60]): antes ela ficava em z-40 dentro da página e
// o cabeçalho da gaveta, com o botão Fechar, ficava escondido atrás da barra. Agora: botão X fixo no topo (o
// cabeçalho não rola; só o corpo rola), Esc fecha, clique fora (no fundo) fecha, o foco fica preso na gaveta e
// volta a quem abriu ao fechar.
import { useEffect, useId, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Icon } from '@/shared/ui/icons';
import { NO } from '../domain/jornada';
import type { AlvoGaveta, DadosTela } from './contexto';
import { GavetaCriativo } from './GavetaCriativo';
import { GavetaEtapa } from './GavetaEtapa';
import { ROTULO_INTEIRO } from './pecas';

const FOCAVEL = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

export function GavetaLateral({ d, alvo, onClose, onTrocar }: { d: DadosTela; alvo: AlvoGaveta | null; onClose: () => void; onTrocar: (a: AlvoGaveta) => void }) {
  const titulo = useId();
  const fechar = useRef<HTMLButtonElement>(null);
  const painel = useRef<HTMLElement>(null);
  const aberta = alvo !== null;
  const fecharRef = useRef(onClose);
  useEffect(() => { fecharRef.current = onClose; });

  useEffect(() => {
    if (!aberta) return;
    const anterior = document.activeElement instanceof HTMLElement || document.activeElement instanceof SVGElement ? document.activeElement : null;
    fechar.current?.focus();
    const tecla = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); fecharRef.current(); return; }
      if (e.key !== 'Tab' || !painel.current) return;
      const itens = Array.from(painel.current.querySelectorAll<HTMLElement>(FOCAVEL)).filter((el) => el.offsetParent !== null);
      if (itens.length === 0) return;
      const primeiro = itens[0]; const ultimo = itens[itens.length - 1];
      if (e.shiftKey && document.activeElement === primeiro) { e.preventDefault(); ultimo.focus(); }
      else if (!e.shiftKey && document.activeElement === ultimo) { e.preventDefault(); primeiro.focus(); }
    };
    window.addEventListener('keydown', tecla);
    return () => {
      window.removeEventListener('keydown', tecla);
      if (anterior && anterior.isConnected) anterior.focus();
    };
  }, [aberta]);

  // A gaveta só abre por clique (alvo começa nulo no servidor), então o document já existe aqui.
  if (!alvo || typeof document === 'undefined') return null;
  const nome = alvo.tipo === 'etapa' ? NO.get(alvo.id)?.titulo ?? 'Etapa' : d.idx.anuncio.get(alvo.id)?.nome ?? 'Criativo';
  const tipo = alvo.tipo === 'etapa' ? 'Etapa da jornada' : 'Criativo';

  return createPortal(
    <div className="fixed inset-0 z-[1000]">
      <button type="button" aria-label="Fechar a gaveta" tabIndex={-1} onClick={onClose}
        className="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)] gp-overlay-in" />
      <aside ref={painel} role="dialog" aria-modal="true" aria-labelledby={titulo}
        className="gp-panel-in absolute inset-y-0 right-0 flex h-dvh w-full flex-col border-l border-[var(--border-strong)] bg-[var(--surface-1)] shadow-[var(--shadow-overlay)] sm:w-[520px]">
        <header className="flex shrink-0 items-start justify-between gap-3 border-b border-[var(--border)] bg-[var(--surface-1)] p-4">
          <div className="min-w-0">
            <p className="text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{tipo}</p>
            <h2 id={titulo} className="break-words text-base font-bold text-[var(--fg)]">{nome}</h2>
          </div>
          <button ref={fechar} type="button" onClick={onClose} aria-label="Fechar"
            className="gp-press inline-flex shrink-0 items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] px-2.5 py-1.5 text-sm text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]">
            <Icon name="x" /><span>Fechar</span>
          </button>
        </header>
        <div className={`min-h-0 flex-1 overflow-y-auto overscroll-contain p-4 ${ROTULO_INTEIRO}`}>
          {alvo.tipo === 'etapa'
            ? <GavetaEtapa key={alvo.id} d={d} id={alvo.id} onTrocar={onTrocar} />
            : <GavetaCriativo key={alvo.id} d={d} id={alvo.id} />}
        </div>
      </aside>
    </div>,
    document.body,
  );
}
