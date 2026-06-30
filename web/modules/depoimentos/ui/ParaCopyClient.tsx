'use client';

import { useEffect, useMemo, useState } from 'react';
import { Card, Toolbar, SearchInput, Button, EmptyState } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { type Depoimento, loadParaCopy } from './depoimentos-data';

export function ParaCopyClient() {
  const [deps, setDeps] = useState<Array<Depoimento & { aluno_nome?: string }>>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState('');

  useEffect(() => {
    (async () => { setDeps(await loadParaCopy()); setLoading(false); })();
  }, []);

  const filtered = useMemo(() => {
    const t = q.toLowerCase().trim();
    return deps.filter((d) => !t || `${d.aluno_nome ?? ''} ${d.gancho ?? ''} ${d.resumo ?? ''}`.toLowerCase().includes(t));
  }, [deps, q]);

  const copy = (v: string) => { navigator.clipboard?.writeText(v); setCopied(v); setTimeout(() => setCopied(''), 1500); };

  return (
    <div>
      <div className="flex items-center gap-3 mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">Para Copy</h1>
        <a href="/depoimentos#biblioteca" className="text-sm text-[var(--accent)]">← Biblioteca</a>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">Trechos prontos para posts, reels e anúncios. {loading && 'carregando…'}</p>
      <Toolbar className="mb-4">
        <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por aluno ou trecho…" />
      </Toolbar>

      <div className="grid gap-4 sm:grid-cols-2">
        {filtered.map((d) => {
          const hls = Array.isArray(d.highlights) ? d.highlights : [];
          return (
            <Card key={d.id} className="p-4">
              <div className="text-xs text-[var(--fg-3)] mb-2">{d.aluno_nome || 'Aluno'}{d.profissao ? ` · ${d.profissao}` : ''}</div>
              {d.gancho && <Block label="Gancho" value={d.gancho} onCopy={copy} copied={copied} />}
              {d.resumo && <Block label="Resumo" value={d.resumo} onCopy={copy} copied={copied} />}
              {d.antes_depois && <Block label="Antes → Depois" value={`Antes: ${d.antes_depois.antes}\nDepois: ${d.antes_depois.depois}`} onCopy={copy} copied={copied} />}
              {hls.map((h, i) => <Block key={i} label={h.tipo} value={h.texto} onCopy={copy} copied={copied} />)}
            </Card>
          );
        })}
        {!filtered.length && !loading && <EmptyState title="Nenhum depoimento com highlights ainda" hint="Gere highlights na Biblioteca." icon="depoimentos" />}
      </div>
    </div>
  );
}

function Block({ label, value, onCopy, copied }: { label: string; value: string; onCopy: (v: string) => void; copied: string }) {
  return (
    <div className="mb-2 p-2 rounded-[var(--r-md)] bg-[var(--surface-1)]">
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-wide text-[var(--accent)] font-semibold">{label}</span>
        <Button variant="link" size="sm" onClick={() => onCopy(value)}>{copied === value ? <><Icon name="check" size={13} /> copiado</> : 'copiar'}</Button>
      </div>
      <div className="text-sm text-[var(--fg)] whitespace-pre-wrap">{value}</div>
    </div>
  );
}
