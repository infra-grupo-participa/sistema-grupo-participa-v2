'use client';

// Aba "Funis" do Financeiro (limpeza aprovada em 28/09/2026): junta o que ficava escondido dentro do Faturamento —
// Funis (cada evento de 2020 a hoje, educação × escritório) e Análise (contratado, previsão, dependência de eventos e
// crescimento) — na mesma tela, porque as duas respondem "de onde vem o dinheiro" com o mesmo calendário de eventos.
import { useState } from 'react';
import type { FinanceiroRepository } from '../../application/ports';
import { FAMILIAS_EM_ORDEM, ROTULO_FAMILIA, type FamiliaHotmart } from '../../domain/hotmart';
import { AnaliseFaturamento } from './AnaliseFaturamento';
import { FunisEventos } from './FunisEventos';

const SUBABAS = [
  { k: 'funis', l: 'Funis por evento' },
  { k: 'analise', l: 'Análise' },
] as const;

export function FunisEAnalise({ repo }: { repo: FinanceiroRepository }) {
  const [sub, setSub] = useState<'funis' | 'analise'>('funis');
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]" role="tablist" aria-label="Funis ou análise">
          {SUBABAS.map((s, i) => (
            <button key={s.k} type="button" role="tab" aria-selected={sub === s.k} onClick={() => setSub(s.k)}
              className={`${i ? 'border-l border-[var(--border)] ' : ''}px-3 py-1.5 text-xs font-semibold ${sub === s.k ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
              {s.l}
            </button>
          ))}
        </div>
        {sub === 'analise' && FAMILIAS_EM_ORDEM.map((f) => (
          <button key={f} type="button" aria-pressed={familia === f} onClick={() => setFamilia(f)}
            className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold ${familia === f ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}>
            {ROTULO_FAMILIA[f]}
          </button>
        ))}
      </div>
      {sub === 'funis' ? <FunisEventos repo={repo} /> : <AnaliseFaturamento key={familia} repo={repo} familia={familia} />}
    </div>
  );
}
