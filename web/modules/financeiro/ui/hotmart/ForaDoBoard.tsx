'use client';

// Adimplência + "pagaram e não estão no board", SOB DEMANDA. Com o HM antigo (446345) no HM, fn_fin_hotmart_pessoas
// devolve ~9,3 mil pessoas (~9,5 MB, 2,1 s — medido 27/09). Carregar isso em toda abertura do board gastaria o egress
// da organização à toa: a seção só busca quando alguém pede, e depois reaproveita o cache (carregar-pessoas.ts).
import { useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { FinanceiroRepository } from '../../application/ports';
import type { FamiliaHotmart } from '../../domain/hotmart';
import { HotmartPessoas } from './HotmartPessoas';

export function ForaDoBoard({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const [aberto, setAberto] = useState(false);
  if (aberto) return <HotmartPessoas repo={repo} familia={familia} recorte="sem_card" />;
  return (
    <button
      type="button"
      onClick={() => setAberto(true)}
      className="flex w-full items-center justify-between gap-3 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] px-4 py-3 text-left transition-colors hover:bg-[var(--surface-2)] focus-visible:ring-2"
    >
      <span>
        <span className="block text-sm font-semibold text-[var(--fg)]">Está todo mundo pagando em dia? · Quem pagou na Hotmart e não está no board</span>
        <span className="block text-xs text-[var(--fg-3)]">Toda a base da Hotmart desde a primeira venda — leva alguns segundos para carregar.</span>
      </span>
      <Icon name="chevron-down" size={16} className="shrink-0 text-[var(--fg-3)]" />
    </button>
  );
}
