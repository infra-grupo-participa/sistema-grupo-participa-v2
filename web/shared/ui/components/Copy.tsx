'use client';

import { useState } from 'react';
import { Button } from './Button';
import { Icon } from '@/shared/ui/icons';

/** Valor em destaque pronto para copiar (ex.: código de rastreio) — feedback "Copiado!" por 2s. */
export function CopyField({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);
  async function copiar() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch { /* clipboard indisponível (http/permissão) — o texto continua selecionável */ }
  }
  return (
    <div className="flex items-center justify-between gap-3 rounded-[var(--r-lg)] border-2 border-[var(--accent-border)] bg-[var(--accent-subtle)] px-3.5 py-3 shadow-[var(--shadow-sm)]">
      <div className="min-w-0 flex items-center gap-3">
        <span className="w-9 h-9 shrink-0 grid place-items-center rounded-[var(--r-md)] bg-[var(--accent)] text-black"><Icon name="copy" size={16} /></span>
        <div className="min-w-0">
          <div className="text-[10px] uppercase tracking-wider font-bold text-[var(--accent)]">{label}</div>
          <div className="text-lg font-bold text-[var(--fg)] tabular tracking-wide truncate select-all leading-tight" title={value}>{value}</div>
        </div>
      </div>
      <Button size="sm" onClick={copiar} aria-label={`Copiar ${label.toLowerCase()}`}>
        <Icon name={copied ? 'check' : 'copy'} size={13} /> {copied ? 'Copiado!' : 'Copiar'}
      </Button>
    </div>
  );
}
