'use client';

import { useMemo } from 'react';
import type { ContaReceber } from '../domain/types';
import { agrupar, resumir, statusLabel, statusTone, STATUS_ORDEM, type Filtros } from '../domain/financeiro';
import { Badge, Button, EmptyState, KpiCard, Loading, ProgressBar, SectionCard } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';

type Gaveta = Filtros['gaveta'];

/** Statuses que têm gaveta própria nos QueueCards — drill direto. */
const GAVETA_POR_STATUS: Partial<Record<string, Gaveta>> = {
  vencido: 'vencido',
  sem_acordo: 'sem_acordo',
  quitado: 'quitado',
};

export function FinanceiroDashboard({ contas, loading, onDrill, onDrillStatus }: {
  contas: ContaReceber[];
  loading: boolean;
  onDrill: (g: Gaveta) => void;
  /** Statuses sem gaveta própria navegam com o filtro de status aplicado. */
  onDrillStatus?: (s: string) => void;
}) {
  const r = useMemo(() => resumir(contas), [contas]);
  const canais = useMemo(() => agrupar(contas, (c) => c.canal), [contas]);
  const porStatus = useMemo(() => {
    const rank = (s: string) => {
      const i = (STATUS_ORDEM as readonly string[]).indexOf(s);
      return i === -1 ? STATUS_ORDEM.length : i;
    };
    return agrupar(contas, (c) => c.status_financeiro).sort((a, b) => rank(a.chave) - rank(b.chave));
  }, [contas]);
  const parado = useMemo(
    () => contas.filter((c) => c.status_financeiro === 'sem_acordo').reduce((acc, c) => acc + (c.saldo_a_pagar ?? 0), 0),
    [contas],
  );

  if (loading) return <Loading label="Carregando contas da turma…" />;

  const maxCanal = Math.max(1, ...canais.map((f) => f.aReceber));
  const pctParado = r.aReceber > 0 ? Math.round((parado / r.aReceber) * 100) : 0;

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
        <KpiCard label="Recebido (bruto)" bar="green" value={fmtBRL(r.recebidoBruto)} hint={`${r.alunos} alunos na turma`} />
        <KpiCard label="Recebido (líquido)" bar="green" value={fmtBRL(r.recebidoLiquido)} hint="o que caiu na conta" />
        <KpiCard label="Taxas Hotmart" bar="yellow" value={fmtBRL(r.taxas)} hint="o que a Hotmart reteve" />
        <KpiCard label="A receber" bar="accent" value={fmtBRL(r.aReceber)} hint={`de ${fmtBRL(r.pacoteTotal)} contratados`} />
        <KpiCard label="Vencido" bar="red" value={fmtBRL(r.vencido)} hint={`${r.emAtraso} conta(s) em atraso`} />
        <KpiCard
          label="Cobertura"
          bar="accent"
          value={
            <div className="space-y-1.5">
              <div>{r.cobertura.toFixed(1)}%</div>
              <ProgressBar value={r.cobertura} tone="accent" height={5} />
            </div>
          }
          hint="% do contratado que já entrou"
        />
      </div>

      <div className="grid gap-4 lg:grid-cols-2 items-start">
        <SectionCard title="A receber por canal" subtitle="Quanto ainda falta entrar, por origem de aquisição.">
          {canais.length === 0 ? (
            <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />
          ) : (
            <div className="space-y-3">
              {canais.map((f) => (
                <div key={f.chave} className="min-w-0">
                  <div className="flex items-baseline justify-between gap-3">
                    <span className="text-sm text-[var(--fg)] truncate">{f.chave}</span>
                    <span className="text-sm font-semibold tabular text-[var(--fg)] shrink-0">{fmtBRL(f.aReceber)}</span>
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <div className="flex-1 h-2 rounded-[var(--r-pill)] bg-[var(--surface-4)] overflow-hidden">
                      <div className="h-full rounded-[var(--r-pill)] bg-[var(--accent)]" style={{ width: `${(f.aReceber / maxCanal) * 100}%` }} />
                    </div>
                    <span className="text-[11px] text-[var(--fg-3)] tabular shrink-0 w-16 text-right">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </SectionCard>

        <SectionCard title="Situação das contas" subtitle="Clique numa situação para abrir as contas correspondentes.">
          {porStatus.length === 0 ? (
            <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />
          ) : (
            <div className="space-y-1">
              {porStatus.map((f) => {
                const g = GAVETA_POR_STATUS[f.chave];
                const clicavel = Boolean(g) || Boolean(onDrillStatus);
                return (
                  <button
                    key={f.chave}
                    type="button"
                    disabled={!clicavel}
                    onClick={() => (g ? onDrill(g) : onDrillStatus?.(f.chave))}
                    className={`w-full flex items-center gap-3 rounded-[var(--r-md)] px-2 py-1.5 text-left transition-colors ${clicavel ? 'hover:bg-[var(--surface-3)] cursor-pointer' : 'cursor-default'}`}
                  >
                    <Badge tone={statusTone(f.chave)} dot>{statusLabel(f.chave)}</Badge>
                    <span className="ml-auto text-xs text-[var(--fg-3)] tabular shrink-0">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                    <span className="text-sm font-semibold tabular text-[var(--fg)] w-28 text-right shrink-0">{fmtBRL(f.aReceber)}</span>
                  </button>
                );
              })}
            </div>
          )}
        </SectionCard>
      </div>

      <SectionCard
        title="Onde está o dinheiro parado"
        subtitle="Alunos sem data de pagamento combinada — transformar isso em acordo é a ação principal do financeiro."
      >
        {r.semAcordo === 0 ? (
          <EmptyState icon="party" title="Nenhum aluno sem acordo" hint="Toda a turma tem data de pagamento combinada." />
        ) : (
          <div className="flex flex-wrap items-center gap-4">
            <div className="min-w-0">
              <div className="text-3xl font-bold tabular text-[var(--fg)]">{fmtBRL(parado)}</div>
              <div className="text-sm text-[var(--fg-2)] mt-1">
                parados com <strong className="text-[var(--fg)]">{r.semAcordo}</strong> {r.semAcordo === 1 ? 'aluno' : 'alunos'} sem acordo
                {pctParado > 0 && <> — <strong className="text-[var(--fg)]">{pctParado}%</strong> de tudo que há a receber</>}
              </div>
            </div>
            <Button className="ml-auto" onClick={() => onDrill('sem_acordo')}>Ver contas sem acordo</Button>
          </div>
        )}
      </SectionCard>
    </div>
  );
}
