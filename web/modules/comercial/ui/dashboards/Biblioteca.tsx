'use client';

// Biblioteca de widgets: cada métrica de METRICAS, agrupada. Arraste para a grade ou clique para adicionar.
import { Icon } from '@/shared/ui/icons';
import { METRICAS } from '../../domain/metricas';
import type { MetricaKey } from '../../domain/types';
import { InfoIndicador } from '../InfoIndicador';
import type { Arrasto } from './GradeDash';
import { GRUPOS_BIBLIOTECA, ICONE_METRICA } from './layout';

export function Biblioteca({ onAdicionar, setArrasto, cheio }: {
  onAdicionar: (m: MetricaKey) => void;
  setArrasto: (a: Arrasto) => void;
  /** Chegou no limite de widgets: não adiciona mais. */
  cheio: boolean;
}) {
  return (
    <nav aria-label="Biblioteca de widgets" className="min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
      <p className="text-sm font-semibold text-[var(--fg)]">Biblioteca</p>
      <p className="mt-0.5 text-[11px] leading-relaxed text-[var(--fg-3)]">
        {cheio ? 'Limite de widgets atingido. Remova um para adicionar outro.' : 'Arraste para a grade ou clique para adicionar.'}
      </p>
      <div className="mt-3 space-y-3">
        {GRUPOS_BIBLIOTECA.map((g) => (
          <section key={g.key} aria-labelledby={`bib-${g.key}`}>
            <h3 id={`bib-${g.key}`} className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{g.rotulo}</h3>
            <ul className="space-y-0.5">
              {g.metricas.map((m) => (
                <li key={m} className="flex items-center gap-0.5 min-w-0">
                  <button
                    type="button"
                    draggable={!cheio}
                    disabled={cheio}
                    onDragStart={(e) => {
                      e.dataTransfer.effectAllowed = 'copy';
                      e.dataTransfer.setData('text/plain', METRICAS[m].nome);
                      setArrasto({ tipo: 'metrica', metrica: m });
                    }}
                    onDragEnd={() => setArrasto(null)}
                    onClick={() => onAdicionar(m)}
                    title={`Adicionar: ${METRICAS[m].nome}`}
                    className="flex flex-1 min-w-0 items-center gap-2 rounded-[var(--r-sm)] px-2 py-1.5 text-left text-xs text-[var(--fg-2)] cursor-grab active:cursor-grabbing hover:bg-[var(--surface-3)] hover:text-[var(--fg)] disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    <span className="grid w-6 h-6 shrink-0 place-items-center rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)]">
                      <Icon name={ICONE_METRICA[m]} size={13} />
                    </span>
                    <span className="truncate">{METRICAS[m].nome}</span>
                  </button>
                  <InfoIndicador metrica={m} className="shrink-0" />
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </nav>
  );
}
