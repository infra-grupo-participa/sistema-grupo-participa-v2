'use client';

// Dashboard executivo do Financeiro — 5 blocos, de cima para baixo:
// 1. A foto do dinheiro (recebido / a receber / cobertura)
// 2. Previsão de recebimento (quando o dinheiro entra)
// 3. Risco: envelhecimento do saldo (aging) + saúde da carteira, lado a lado
// 4. Fazer agora (as 3 ações do operador)
// 5. A receber por canal
import { useMemo } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber } from '../domain/types';
import {
  agrupar, resumir, statusLabel, statusTone, STATUS_ORDEM, type Gaveta,
} from '../domain/financeiro';
import { AGING_META, distribuicaoAging, preverRecebimento } from '../domain/cobranca';
import { Card, EmptyState, Loading, ProgressBar, SectionTitle } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';

/** Tom semântico → token de cor (mesma paleta do Badge). */
const TONE_COLOR: Record<ReturnType<typeof statusTone>, string> = {
  neutral: 'var(--fg-3)',
  accent: 'var(--accent)',
  success: 'var(--green)',
  warning: 'var(--yellow)',
  danger: 'var(--red)',
  info: 'var(--info)',
};

const MORTOS = new Set(['cancelado', 'reembolsado']);

export function FinanceiroDashboard({ contas, loading, onDrill, onDrillStatus }: {
  contas: ContaReceber[];
  loading: boolean;
  onDrill: (g: Gaveta) => void;
  /** Statuses sem gaveta própria navegam com o filtro de status aplicado. */
  onDrillStatus?: (s: string) => void;
}) {
  const hojeISO = new Date().toISOString().slice(0, 10);
  const r = useMemo(() => resumir(contas), [contas]);
  const forecast = useMemo(() => preverRecebimento(contas, hojeISO), [contas, hojeISO]);
  const aging = useMemo(() => distribuicaoAging(contas), [contas]);
  const canais = useMemo(() => agrupar(contas, (c) => c.canal), [contas]);
  const porStatus = useMemo(() => {
    const rank = (s: string) => {
      const i = (STATUS_ORDEM as readonly string[]).indexOf(s);
      return i === -1 ? STATUS_ORDEM.length : i;
    };
    return agrupar(contas, (c) => c.status_financeiro).sort((a, b) => rank(a.chave) - rank(b.chave));
  }, [contas]);

  if (loading) return <Loading label="Carregando contas da turma…" />;
  if (!contas.length) return <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />;

  // Barra empilhada só com contas vivas; mortas apagadas no fim da legenda.
  const vivos = porStatus.filter((f) => !MORTOS.has(f.chave));
  const mortos = porStatus.filter((f) => MORTOS.has(f.chave));

  const acoes: { g: Gaveta; label: string; hint: string; n: number; sub: string; color: string; icon: string }[] = [
    { g: 'vencido', label: 'Vencido', hint: 'cobrar já', n: r.vencidoQtd, sub: `${fmtBRL(r.vencido)} em atraso`, color: 'var(--red)', icon: 'alert' },
    { g: 'sem_acordo', label: 'Sem acordo', hint: 'combinar data', n: r.semAcordo, sub: 'sem vencimento definido', color: 'var(--accent)', icon: 'clipboard' },
    { g: 'incalculavel', label: 'A calcular', hint: 'descobrir valor', n: r.incalculavel, sub: 'sem insumo de crédito', color: 'var(--yellow)', icon: 'notebook' },
  ];

  const maxCanal = Math.max(1, ...canais.map((f) => f.aReceber));

  return (
    <div className="space-y-4">
      {/* Bloco 1 — a foto do dinheiro */}
      <Card className="p-4 border-[var(--border-accent)]" style={{ borderTop: '3px solid var(--accent)' }}>
        <div className="grid gap-x-6 gap-y-3.5 sm:grid-cols-3">
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Recebido</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--green)] break-words">{fmtBRL(r.recebidoBruto)}</div>
          </div>
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">A receber</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--accent)] break-words">{fmtBRL(r.aReceber)}</div>
          </div>
          <div className="min-w-0">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Cobertura</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--fg)]">{r.cobertura.toFixed(1)}%</div>
            <div className="mt-1.5"><ProgressBar value={r.cobertura} tone="accent" height={5} /></div>
            <div className="mt-1 text-[10px] text-[var(--fg-3)]">do contratado ({fmtBRL(r.pacoteTotal)}) já entrou</div>
          </div>
        </div>
        <div className="mt-3 pt-2.5 border-t border-[var(--border-faint)] text-[10px] tabular text-[var(--fg-3)]">
          líquido {fmtBRL(r.recebidoLiquido)} · taxas {fmtBRL(r.taxas)} · {r.alunos} alunos
        </div>
      </Card>

      {/* Bloco 2 — previsão de recebimento: quando o dinheiro entra */}
      <div>
        <SectionTitle>Previsão de recebimento</SectionTitle>
        <Card className="p-3.5">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3">
            <MiniPrevisao label="Próx. 7 dias" valor={forecast.proximos7} cor="var(--green)" />
            <MiniPrevisao label="Próx. 30 dias" valor={forecast.proximos30} cor="var(--accent)" />
            <MiniPrevisao label="Em risco (vencido)" valor={forecast.emRisco} cor="var(--red)" />
            <MiniPrevisao label="Sem prazo" valor={forecast.semPrazo} cor="var(--fg-3)" />
          </div>
        </Card>
      </div>

      {/* Bloco 3 — risco: aging do saldo (a novidade) + saúde por status, lado a lado */}
      <div className="grid gap-4 lg:grid-cols-2">
        <div>
          <SectionTitle>Envelhecimento do saldo</SectionTitle>
          <Card className="p-4">
            {!aging.length ? (
              <EmptyState title="Nada a receber em aberto" icon="check" />
            ) : (
              <>
                <div className="flex h-2.5 rounded-[var(--r-pill)] overflow-hidden bg-[var(--surface-4)]" role="img" aria-label="Distribuição do saldo a receber por faixa de atraso">
                  {aging.map((f) => (
                    <div
                      key={f.bucket}
                      title={`${AGING_META[f.bucket].label} · ${fmtBRL(f.valor)}`}
                      style={{ flexGrow: f.valor, flexBasis: 0, background: TONE_COLOR[AGING_META[f.bucket].tone] }}
                    />
                  ))}
                </div>
                <div className="mt-3 space-y-0.5">
                  {aging.map((f) => (
                    <div key={f.bucket} className="flex items-center gap-2 px-1.5 py-1 min-w-0">
                      <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: TONE_COLOR[AGING_META[f.bucket].tone] }} />
                      <span className="text-[11px] text-[var(--fg-2)] truncate">{AGING_META[f.bucket].label}</span>
                      <span className="ml-auto text-[11px] tabular text-[var(--fg-3)] shrink-0">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                      <span className="text-[11px] font-semibold tabular text-[var(--fg)] shrink-0 w-20 text-right">{fmtBRL(f.valor)}</span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </Card>
        </div>

        <div>
          <SectionTitle>Saúde da carteira</SectionTitle>
          <Card className="p-4">
            <div className="flex h-2.5 rounded-[var(--r-pill)] overflow-hidden bg-[var(--surface-4)]" role="img" aria-label="Distribuição dos alunos por status">
              {vivos.map((f) => (
                <div
                  key={f.chave}
                  title={`${statusLabel(f.chave)} · ${f.alunos}`}
                  style={{ flexGrow: f.alunos, flexBasis: 0, background: TONE_COLOR[statusTone(f.chave)] }}
                />
              ))}
            </div>
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-0.5">
              {vivos.map((f) => <LegendaStatus key={f.chave} chave={f.chave} alunos={f.alunos} onClick={onDrillStatus} />)}
              {mortos.map((f) => <LegendaStatus key={f.chave} chave={f.chave} alunos={f.alunos} onClick={onDrillStatus} morta />)}
            </div>
          </Card>
        </div>
      </div>

      {/* Bloco 4 — fazer agora */}
      <div>
        <SectionTitle>Fazer agora</SectionTitle>
        <div className="grid gap-3 sm:grid-cols-3">
          {acoes.map((a) => {
            const vazio = a.n === 0;
            return (
              <button
                key={a.g}
                type="button"
                disabled={vazio}
                onClick={() => onDrill(a.g)}
                className={`text-left rounded-[var(--r-lg)] border bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-3.5 transition-colors ${vazio ? 'opacity-50 cursor-default border-[var(--border)]' : 'border-[var(--border)] hover:border-[var(--border-strong)] cursor-pointer'}`}
                style={{ borderTopWidth: 3, borderTopColor: vazio ? 'var(--border)' : a.color }}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-2xl font-bold tabular leading-none text-[var(--fg)]">
                      {vazio ? <Icon name="check" size={22} className="text-[var(--green)]" /> : a.n.toLocaleString('pt-BR')}
                    </div>
                    <div className="mt-1.5 text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-2)]">{a.label}</div>
                    <div className="mt-0.5 text-[10px] text-[var(--fg-3)] truncate">{vazio ? 'nada aqui' : a.sub}</div>
                  </div>
                  <span
                    className="grid place-items-center w-7 h-7 rounded-[var(--r-md)] shrink-0"
                    style={{ background: `color-mix(in srgb, ${a.color} 14%, transparent)`, color: a.color }}
                  >
                    <Icon name={a.icon} size={15} />
                  </span>
                </div>
                {!vazio && (
                  <div className="mt-2.5 text-[10px] font-semibold" style={{ color: a.color }}>{a.hint} →</div>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Bloco 5 — a receber por canal */}
      <div>
        <SectionTitle>A receber por canal</SectionTitle>
        <Card className="p-4">
        {canais.length === 0 ? (
          <EmptyState title="Nenhuma conta nesta turma" icon="inbox" />
        ) : (
          <div className="space-y-2.5">
            {canais.map((f) => (
              <div key={f.chave} className="min-w-0">
                <div className="flex items-baseline justify-between gap-3">
                  <span className="text-[13px] text-[var(--fg-2)] truncate">{f.chave}</span>
                  <span className="text-[13px] font-semibold tabular text-[var(--fg)] shrink-0">{fmtBRL(f.aReceber)}</span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 h-1.5 rounded-[var(--r-pill)] bg-[var(--surface-4)] overflow-hidden">
                    <div className="h-full rounded-[var(--r-pill)] bg-[var(--accent)]" style={{ width: `${(f.aReceber / maxCanal) * 100}%` }} />
                  </div>
                  <span className="text-[10px] text-[var(--fg-3)] tabular shrink-0 w-14 text-right">{f.alunos} {f.alunos === 1 ? 'aluno' : 'alunos'}</span>
                </div>
              </div>
            ))}
          </div>
        )}
        </Card>
      </div>
    </div>
  );
}

/** Mini-KPI da previsão: rótulo pequeno + valor compacto colorido. */
function MiniPrevisao({ label, valor, cor }: { label: string; valor: number; cor: string }) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)] truncate">{label}</div>
      <div className="mt-0.5 text-[15px] font-bold tabular leading-tight break-words" style={{ color: valor > 0 ? cor : 'var(--fg-3)' }}>
        {fmtBRL(valor)}
      </div>
    </div>
  );
}

/** Item da legenda da barra empilhada: bolinha, label curto, contagem. */
function LegendaStatus({ chave, alunos, onClick, morta = false }: {
  chave: string; alunos: number; onClick?: (s: string) => void; morta?: boolean;
}) {
  const clicavel = Boolean(onClick);
  return (
    <button
      type="button"
      disabled={!clicavel}
      onClick={() => onClick?.(chave)}
      className={`flex items-center gap-2 rounded-[var(--r-sm)] px-1.5 py-1 text-left min-w-0 transition-colors ${morta ? 'opacity-45' : ''} ${clicavel ? 'hover:bg-[var(--surface-3)] cursor-pointer' : 'cursor-default'}`}
    >
      <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: TONE_COLOR[statusTone(chave)] }} />
      <span className="text-[11px] text-[var(--fg-2)] truncate">{statusLabel(chave)}</span>
      <span className="ml-auto text-[11px] font-semibold tabular text-[var(--fg)] shrink-0">{alunos}</span>
    </button>
  );
}
