'use client';

// Trilha do filtro cruzado da aba Criativos e páginas: Campanha › Conjunto › Criativo › Página. Cada chip mostra
// o nome exato da fonte e sai no X; "Limpar" volta tudo.
import type { FiltroCriativos } from '../domain/tipos';

const ORDEM: { k: keyof FiltroCriativos; l: string }[] = [
  { k: 'campanha', l: 'Campanha' }, { k: 'conjunto', l: 'Conjunto' }, { k: 'anuncio', l: 'Criativo' }, { k: 'pagina', l: 'Página' },
];

export function TrilhaFiltro({ filtro, nome, onTirar, onLimpar }: {
  filtro: FiltroCriativos; nome: (k: keyof FiltroCriativos, id: string) => string; onTirar: (k: keyof FiltroCriativos) => void; onLimpar: () => void;
}) {
  const ativos = ORDEM.filter(({ k }) => filtro[k]);
  return (
    <nav aria-label="Filtro cruzado" className="flex flex-wrap items-center gap-1.5 text-xs">
      <span className="text-[var(--fg-3)]">Filtro:</span>
      {ativos.length === 0 && <span className="text-[var(--fg-3)]">nenhum. Clique numa campanha, conjunto, criativo ou página.</span>}
      {ativos.map(({ k, l }, i) => (
        <span key={k} className="inline-flex min-w-0 items-center gap-1.5">
          {i > 0 && <span aria-hidden="true" className="text-[var(--fg-3)]">›</span>}
          <button type="button" onClick={() => onTirar(k)} title={`Tirar o filtro de ${l.toLowerCase()}`}
            className="inline-flex min-w-0 max-w-full items-center gap-1 rounded-full border border-[var(--border-accent)] bg-[var(--surface-3)] px-2 py-0.5 text-left text-[var(--fg)]">
            <span className="text-[var(--fg-3)]">{l}:</span> <span className="break-all">{nome(k, filtro[k]!)}</span> <span aria-hidden="true">×</span>
          </button>
        </span>
      ))}
      {ativos.length > 0 && <button type="button" onClick={onLimpar} className="text-[var(--accent)] underline-offset-2 hover:underline">Limpar</button>}
    </nav>
  );
}
