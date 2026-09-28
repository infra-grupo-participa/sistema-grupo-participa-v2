'use client';

// Tablist das sub-abas do Faturamento — mesmo padrão WAI-ARIA de ui/receber/ContasAReceber.tsx (SubAbasReceber):
// ativação automática (seta move o foco E troca a aba), Home/End para a primeira/última.
import { useRef } from 'react';
import type { SubAbaFaturamento } from './hash';
import { SUBABAS_FATURAMENTO } from './textos';

export const SUBABAS_FATURAMENTO_LISTA: { k: SubAbaFaturamento; l: string }[] = [
  { k: 'periodo', l: SUBABAS_FATURAMENTO.periodo },
  { k: 'caixa', l: SUBABAS_FATURAMENTO.caixa },
  { k: 'taxa', l: SUBABAS_FATURAMENTO.taxa },
];

export function SubAbasFaturamento({ ativa, onSelecionar }: {
  ativa: SubAbaFaturamento; onSelecionar: (s: SubAbaFaturamento) => void;
}) {
  const botoes = useRef<Partial<Record<SubAbaFaturamento, HTMLButtonElement | null>>>({});
  const L = SUBABAS_FATURAMENTO_LISTA;
  const ir = (alvo: SubAbaFaturamento) => { onSelecionar(alvo); botoes.current[alvo]?.focus(); };
  const mover = (dir: 1 | -1) => {
    const i = L.findIndex((s) => s.k === ativa);
    ir(L[(i + dir + L.length) % L.length].k);
  };
  return (
    <div
      role="tablist"
      aria-label={SUBABAS_FATURAMENTO.rotuloGrupo}
      className="flex w-fit overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]"
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') { e.preventDefault(); mover(1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); mover(-1); }
        else if (e.key === 'Home') { e.preventDefault(); ir(L[0].k); }
        else if (e.key === 'End') { e.preventDefault(); ir(L[L.length - 1].k); }
      }}
    >
      {L.map((s, i) => (
        <button
          key={s.k}
          ref={(el) => { botoes.current[s.k] = el; }}
          type="button"
          role="tab"
          id={`faturamento-tab-${s.k}`}
          aria-selected={ativa === s.k}
          aria-controls={`faturamento-painel-${s.k}`}
          tabIndex={ativa === s.k ? 0 : -1}
          onClick={() => onSelecionar(s.k)}
          className={`${i ? 'border-l border-[var(--border)] ' : ''}px-3 py-1.5 text-xs font-semibold ${
            ativa === s.k ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'
          }`}
        >
          {s.l}
        </button>
      ))}
    </div>
  );
}
