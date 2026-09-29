'use client';

// Aba "Escritório" do Financeiro (#escritorio, 30/09/2026): o setor escritório (Sessão de Viabilidade → Croqui →
// Holding Familiar). Sub-abas no hash (#escritorio?ver=), como o Faturamento. Hoje só o Funil; Contratos da Holding
// Familiar entra depois — ver SUBABAS_ESCRITORIO_ATIVAS em ./hash.ts. O tablist só aparece com 2+ sub-abas ativas.
import { useRef } from 'react';
import type { CacheEscritorioFunil } from '../../application/carregar-escritorio-funil';
import { ROTULO_SUBABA_ESCRITORIO, SUBABAS_ESCRITORIO_ATIVAS, type SubAbaEscritorio } from './hash';
import { FunilEscritorio } from './FunilEscritorio';

export function EscritorioAba({ sub, onSubChange, cacheFunil }: {
  sub: SubAbaEscritorio; onSubChange: (s: SubAbaEscritorio) => void; cacheFunil: CacheEscritorioFunil;
}) {
  return (
    <div className="space-y-4">
      {SUBABAS_ESCRITORIO_ATIVAS.length > 1 && <SubAbasEscritorio ativa={sub} onSelecionar={onSubChange} />}
      <div role={SUBABAS_ESCRITORIO_ATIVAS.length > 1 ? 'tabpanel' : undefined} id={`escritorio-painel-${sub}`}
        aria-labelledby={SUBABAS_ESCRITORIO_ATIVAS.length > 1 ? `escritorio-tab-${sub}` : undefined}>
        {sub === 'funil' && <FunilEscritorio cache={cacheFunil} />}
      </div>
    </div>
  );
}

/** Mesmo padrão WAI-ARIA do SubAbasFaturamento: seta move o foco e troca a aba, Home/End. */
function SubAbasEscritorio({ ativa, onSelecionar }: { ativa: SubAbaEscritorio; onSelecionar: (s: SubAbaEscritorio) => void }) {
  const botoes = useRef<Partial<Record<SubAbaEscritorio, HTMLButtonElement | null>>>({});
  const L = SUBABAS_ESCRITORIO_ATIVAS;
  const ir = (alvo: SubAbaEscritorio) => { onSelecionar(alvo); botoes.current[alvo]?.focus(); };
  const mover = (dir: 1 | -1) => ir(L[(L.indexOf(ativa) + dir + L.length) % L.length]);
  return (
    <div role="tablist" aria-label="Escritório" className="flex w-fit overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]"
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') { e.preventDefault(); mover(1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); mover(-1); }
        else if (e.key === 'Home') { e.preventDefault(); ir(L[0]); }
        else if (e.key === 'End') { e.preventDefault(); ir(L[L.length - 1]); }
      }}>
      {L.map((s, i) => (
        <button key={s} ref={(el) => { botoes.current[s] = el; }} type="button" role="tab" id={`escritorio-tab-${s}`}
          aria-selected={ativa === s} aria-controls={`escritorio-painel-${s}`} tabIndex={ativa === s ? 0 : -1}
          onClick={() => onSelecionar(s)}
          className={`${i ? 'border-l border-[var(--border)] ' : ''}px-3 py-1.5 text-xs font-semibold ${
            ativa === s ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
          {ROTULO_SUBABA_ESCRITORIO[s]}
        </button>
      ))}
    </div>
  );
}
