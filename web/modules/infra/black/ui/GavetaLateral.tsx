'use client';

// Gaveta lateral da Jornada e dos criativos. Não é modal (o mapa continua visível e clicável): role="dialog"
// aria-modal="false", 520 px à direita, sem fundo escuro; abaixo de 640 px, tela inteira. Esc fecha e devolve o
// foco a quem abriu. O Drawer canônico é um modal centrado, por isso esta peça própria (decisão registrada).
import { useEffect, useId, useRef } from 'react';
import { Icon } from '@/shared/ui/icons';
import { NO } from '../domain/jornada';
import type { AlvoGaveta, DadosTela } from './contexto';
import { GavetaCriativo } from './GavetaCriativo';
import { GavetaEtapa } from './GavetaEtapa';

export function GavetaLateral({ d, alvo, onClose, onTrocar }: { d: DadosTela; alvo: AlvoGaveta | null; onClose: () => void; onTrocar: (a: AlvoGaveta) => void }) {
  const titulo = useId();
  const fechar = useRef<HTMLButtonElement>(null);
  const aberta = alvo !== null;
  const fecharRef = useRef(onClose);
  useEffect(() => { fecharRef.current = onClose; });

  useEffect(() => {
    if (!aberta) return;
    const anterior = document.activeElement instanceof HTMLElement || document.activeElement instanceof SVGElement ? document.activeElement : null;
    fechar.current?.focus();
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') fecharRef.current(); };
    window.addEventListener('keydown', tecla);
    return () => {
      window.removeEventListener('keydown', tecla);
      if (anterior && anterior.isConnected) anterior.focus();
    };
  }, [aberta]);

  if (!alvo) return null;
  const nome = alvo.tipo === 'etapa' ? NO.get(alvo.id)?.titulo ?? 'Etapa' : d.idx.anuncio.get(alvo.id)?.nome ?? 'Criativo';
  const tipo = alvo.tipo === 'etapa' ? 'Etapa da jornada' : 'Criativo';

  return (
    <aside role="dialog" aria-modal="false" aria-labelledby={titulo}
      className="gp-panel-in fixed inset-y-0 right-0 z-40 flex w-full flex-col border-l border-[var(--border-strong)] bg-[var(--surface-1)] shadow-2xl sm:w-[520px]">
      <header className="flex items-start justify-between gap-3 border-b border-[var(--border)] p-4">
        <div className="min-w-0">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{tipo}</p>
          <h2 id={titulo} className="break-words text-base font-bold text-[var(--fg)]">{nome}</h2>
        </div>
        <button ref={fechar} type="button" onClick={onClose} aria-label="Fechar"
          className="shrink-0 rounded-[var(--r-md)] p-2 text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]">
          <Icon name="x" />
        </button>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {alvo.tipo === 'etapa'
          ? <GavetaEtapa key={alvo.id} d={d} id={alvo.id} onTrocar={onTrocar} />
          : <GavetaCriativo key={alvo.id} d={d} id={alvo.id} />}
      </div>
    </aside>
  );
}
