'use client';

// Peças compartilhadas pelas visões da Hotmart (Faturamento, Pessoas,
// Identidade, Ofertas, Conciliação) — extraído de ui/Hotmart.tsx em 27/09/2026.
import { useEffect, useState } from 'react';
import { Badge } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { Icon } from '@/shared/ui/icons';
import { fmtDataHora } from '@/shared/ui/format';
import type { SyncHotmart } from '../../domain/hotmart';

export const PERIODOS = [
  { dias: 30, rotulo: '30 dias' }, { dias: 90, rotulo: '90 dias' },
  { dias: 365, rotulo: '12 meses' },
  // "Tudo" = desde a 1ª venda do espelho (Aurum, 2021). "3 anos" cortava o HM de ago/2023.
  { dias: Math.ceil((Date.now() - Date.UTC(2021, 0, 1)) / 86_400_000), rotulo: 'Tudo (desde 2021)' },
] as const;

export function isoDiasAtras(n: number): string {
  const d = new Date(Date.now() - n * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

/** Carrega sob demanda. O resultado guarda a CHAVE da consulta que o gerou: trocar
 *  de filtro não mostra o dado velho (a chave não bate → volta a "carregando"),
 *  sem setState síncrono dentro do efeito. */
export function useCarga<T>(fn: () => Promise<T>, deps: unknown[]) {
  const chave = JSON.stringify(deps);
  const [res, setRes] = useState<{ chave: string; dados: T | null; erro: string | null } | null>(null);
  useEffect(() => {
    let vivo = true;
    fn()
      .then((d) => { if (vivo) setRes({ chave, dados: d, erro: null }); })
      .catch((e: Error) => { if (vivo) setRes({ chave, dados: null, erro: e.message }); });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave]);
  const atual = res && res.chave === chave ? res : null;
  return { dados: atual?.dados ?? null, erro: atual?.erro ?? null };
}

export function Erro({ msg }: { msg: string }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--red-border)] bg-[var(--red-subtle)] p-4 text-sm text-[var(--fg)]">
      <Icon name="alert" size={16} className="mr-1.5 inline text-[var(--red)]" />{msg}
    </div>
  );
}

export function Chip({ ativo, onClick, children, tom = 'neutral' }: { ativo: boolean; onClick: () => void; children: React.ReactNode; tom?: Tone }) {
  return (
    <button type="button" aria-pressed={ativo} onClick={onClick}
      className={`rounded-[var(--r-sm)] border px-2 py-1 text-xs ${ativo ? 'border-[var(--accent)] font-semibold text-[var(--fg)] bg-[var(--surface-3)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`}>
      <Badge tone={tom}>{children}</Badge>
    </button>
  );
}

export function SyncSelo({ sync: estado }: { sync: { s: SyncHotmart; atrasado: boolean } | null }) {
  if (!estado) return null;
  const sync = estado.s;
  const tom: Tone = sync.janelas_com_erro > 0 || estado.atrasado ? 'warning' : 'success';
  return (
    <span className="ml-auto">
      <Badge tone={tom}>
        {sync.transacoes.toLocaleString('pt-BR')} transações · atualizado {sync.ultima_atualizacao ? fmtDataHora(sync.ultima_atualizacao) : '—'}
        {sync.janelas_pendentes > 0 ? ` · sincronizando histórico (${sync.janelas_pendentes})` : ''}
        {sync.janelas_com_erro > 0 ? ` · ${sync.janelas_com_erro} janela(s) com erro` : ''}
      </Badge>
    </span>
  );
}

/** Seta + % vs. dia anterior — verde alta, vermelho queda. */
export function Variacao({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-[11px] text-[var(--fg-4)]">—</span>;
  const subiu = pct >= 0;
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-semibold tabular ${subiu ? 'text-[var(--green)]' : 'text-[var(--red)]'}`}>
      <Icon name={subiu ? 'arrow-up' : 'arrow-down'} size={12} />
      {Math.abs(pct).toFixed(0)}%
    </span>
  );
}
