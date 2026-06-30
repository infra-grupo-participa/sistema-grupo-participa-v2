'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AUDIT_STEPS, AUDIT_STEP_TOTAL } from '../../domain/auditoria';
import {
  computeDisplayStatus,
  getSolicitacaoBucketMatch,
  getSolicitacaoQueuePriority,
  isSolicitacaoSeen,
  isSolicitacaoRegularizacao,
  isSolicitacaoFinalizada,
  isSolicitacaoRascunho,
  type SolicitacaoBucket,
} from '../../domain/solicitacao';
import type { Solicitacao, Auditoria, HorarioSlot } from '../../domain/types';
import * as data from './placas-admin-data';
import { Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState, Drawer, Card, Button, StatCard, SearchInput, Input, Toggle, ProgressBar, Timeline, ConfirmDialog, type TimelineEntry } from '@/shared/ui/components';

const APP_URL = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';

/** Progresso visual da solicitação: fração 0–1 + rótulo. */
function progresso(s: Solicitacao): { pct: number; label: string } {
  if (isSolicitacaoRegularizacao(s)) return { pct: 0.15, label: 'Correção' };
  if (s.status === 'concluido') return { pct: 1, label: 'Concluído' };
  if (s.status === 'rejeitado') return { pct: 1, label: 'Rejeitado' };
  const step = Number(s.auditoria_step ?? -1);
  if (step >= 0) return { pct: (step + 1) / AUDIT_STEP_TOTAL, label: `${step + 1}/${AUDIT_STEP_TOTAL}` };
  if (s.status === 'cadastro_concluido') return { pct: 1, label: 'Cadastro' };
  const form = Math.max(0, Math.min(Number(s.step_index ?? 0), 9));
  return { pct: (form / 9) * 0.4, label: 'Rascunho' };
}

function initial(nome?: string | null): string {
  return (nome || '?').trim().charAt(0).toUpperCase();
}

const STATUS_TONE: Record<string, 'accent' | 'neutral' | 'success' | 'danger' | 'warning' | 'info'> = {
  'sp-andamento': 'info',
  'sp-aguardando': 'neutral',
  'sp-entregue': 'success',
  'sp-encerrado': 'danger',
  'sp-regularizacao': 'warning',
};

type Tab = 'solicitacoes' | 'agenda-horarios';
const BUCKETS: { key: SolicitacaoBucket; label: string }[] = [
  { key: 'processo', label: 'Em processo' },
  { key: 'rascunhos', label: 'Rascunhos' },
  { key: 'cadastro', label: 'Somente cadastro' },
  { key: 'questionarios', label: 'Finalizados' },
];

export function RelatorioPlacasClient({ canEdit }: { canEdit: boolean }) {
  const [tab, setTab] = useState<Tab>('solicitacoes');
  const [sols, setSols] = useState<Solicitacao[]>([]);
  const [auds, setAuds] = useState<Record<string, Auditoria>>({});
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState<SolicitacaoBucket>('processo');
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const [toast, setToast] = useState('');

  const reload = useCallback(async () => {
    const [s, a] = await Promise.all([data.loadSolicitacoes(), data.loadAuditorias()]);
    setSols(s);
    const map: Record<string, Auditoria> = {};
    for (const au of a) if (au.aluno_id) map[au.aluno_id] = au;
    setAuds(map);
  }, []);

  useEffect(() => {
    (async () => {
      const initial = await data.loadSolicitacoes();
      if (canEdit) await data.autoStartPending(initial); // auto-inicia auditorias 'enviado'
      await reload();
      setLoading(false);
    })();
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'agenda-horarios') setTab('agenda-horarios');
      else setTab('solicitacoes');
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    return () => window.removeEventListener('hashchange', applyHash);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function flash(msg: string) {
    setToast(msg);
    setTimeout(() => setToast(''), 3000);
  }

  const act = async (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => {
    const r = await fn();
    const ok = typeof r === 'boolean' ? r : r.ok;
    const msg = typeof r === 'boolean' ? (ok ? 'Feito!' : 'Falhou.') : r.msg || (ok ? 'Feito!' : 'Falhou.');
    flash(msg);
    await reload();
  };

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    return sols
      .filter((s) => getSolicitacaoBucketMatch(s, bucket))
      .filter((s) => !term || `${s.nome ?? ''} ${s.email ?? ''} ${s.documento_nf ?? ''}`.toLowerCase().includes(term))
      .sort((a, b) => getSolicitacaoQueuePriority(a) - getSolicitacaoQueuePriority(b));
  }, [sols, bucket, q]);

  const open = openId ? sols.find((s) => s.id === openId) ?? null : null;
  const stats = useMemo(() => {
    const total = sols.length;
    const finalizadas = sols.filter(isSolicitacaoFinalizada).length;
    const rascunhos = sols.filter(isSolicitacaoRascunho).length;
    return { total, finalizadas, rascunhos, emAndamento: total - finalizadas - rascunhos };
  }, [sols]);
  const linkPublico = `${APP_URL}/solicitar-placa`;
  const [copiado, setCopiado] = useState(false);
  const hoje = new Date().toLocaleDateString('pt-BR', { day: '2-digit', month: 'long', year: 'numeric' });

  return (
    <div>
      {tab === 'solicitacoes' ? (
        <>
          <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
            <h1 className="text-2xl font-bold text-[var(--fg)]">
              Solicitações de <span className="text-[var(--accent)]">Placas</span>
              <span className="ml-2 align-middle text-xs font-semibold rounded-[var(--r-pill)] bg-[var(--accent-subtle)] text-[var(--accent)] px-2 py-0.5">{stats.total}</span>
            </h1>
            <a href="/sistema/admin-dev" className="inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors">🗒️ Logs</a>
          </div>
          <p className="text-sm text-[var(--fg-3)] mb-4">Candidatos que iniciaram o processo via formulário público · Atualizado em {hoje}{loading && ' · carregando…'}</p>

          {/* Stat cards com acento + ícone */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <StatBox value={stats.total} label="Total de processos" icon="≣" tone="var(--fg-2)" />
            <StatBox value={stats.finalizadas} label="Finalizadas" icon="✓" tone="var(--green)" />
            <StatBox value={stats.emAndamento} label="Em andamento" icon="↻" tone="var(--accent)" />
            <StatBox value={stats.rascunhos} label="Rascunhos" icon="🖹" tone="var(--nivel-platina)" />
          </div>

          {/* Link do questionário público */}
          <Card className="p-3 mb-4 flex items-center gap-3 flex-wrap">
            <span className="text-[var(--fg-3)]">🔗</span>
            <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Link de envio do questionário</span>
            <Input readOnly value={linkPublico} className="flex-1 min-w-[200px] !text-[var(--accent)] font-mono" />
            <Button variant="subtle" size="sm" onClick={() => { navigator.clipboard?.writeText(linkPublico); setCopiado(true); setTimeout(() => setCopiado(false), 1500); }}>
              {copiado ? '✓ Copiado' : '⧉ Copiar link'}
            </Button>
          </Card>

          {/* Busca */}
          <div className="mb-3">
            <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nome, e-mail, documento ou cidade…" />
          </div>

          {/* Abas-bucket com contagem */}
          <div className="flex gap-1 border-b border-[var(--border)] mb-3 overflow-x-auto">
            {BUCKETS.map((b) => {
              const n = sols.filter((s) => getSolicitacaoBucketMatch(s, b.key)).length;
              return (
                <button key={b.key} onClick={() => setBucket(b.key)} className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px transition-colors inline-flex items-center gap-2 ${bucket === b.key ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'}`}>
                  {b.label}
                  <span className={`text-[11px] rounded-[var(--r-pill)] px-1.5 py-0.5 ${bucket === b.key ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'bg-[var(--surface-3)] text-[var(--fg-3)]'}`}>{n}</span>
                </button>
              );
            })}
          </div>

          <DataTable>
            <Thead>
              <Th>Aluno</Th>
              <Th>Nível</Th>
              <Th>Status</Th>
              <Th>Progresso</Th>
              <Th>Turma</Th>
              <Th>Última atualização</Th>
            </Thead>
            <tbody>
              {filtered.map((s) => {
                const ds = computeDisplayStatus(s);
                const seen = isSolicitacaoSeen(s);
                const pr = progresso(s);
                return (
                  <Tr key={s.id} onClick={() => setOpenId(s.id)}>
                    <Td>
                      <div className="flex items-center gap-2.5">
                        <span className="relative grid place-items-center w-8 h-8 rounded-full bg-[var(--accent)] text-black font-bold text-sm shrink-0">
                          {initial(s.nome)}
                          {!seen && <span className="absolute -top-0.5 -right-0.5 w-2.5 h-2.5 rounded-full bg-[var(--accent)] ring-2 ring-[var(--surface-2)]" title="Atualização não vista" />}
                        </span>
                        <div className="min-w-0">
                          <div className="text-[var(--fg)] font-medium truncate">{s.nome || '—'}</div>
                          <div className="text-[var(--fg-3)] text-xs truncate">{s.email}</div>
                        </div>
                      </div>
                    </Td>
                    <Td><NivelBadge nivel={s.nivel} /></Td>
                    <Td><Badge tone={STATUS_TONE[ds.cls] || 'neutral'} dot>{ds.label}</Badge></Td>
                    <Td>
                      <div className="flex items-center gap-2 min-w-[120px]">
                        <div className="flex-1"><ProgressBar value={pr.pct * 100} height={6} /></div>
                        <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{pr.label}</span>
                      </div>
                    </Td>
                    <Td>{s.turma ? <span className="text-xs font-semibold rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)] px-2 py-0.5">{s.turma}</span> : <span className="text-[var(--fg-3)]">—</span>}</Td>
                    <Td className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{s.updated_at ? new Date(s.updated_at).toLocaleDateString('pt-BR') : '—'}</Td>
                  </Tr>
                );
              })}
            </tbody>
          </DataTable>
          {!filtered.length && !loading && <EmptyState title="Nenhuma solicitação neste filtro" icon="🏆" />}
        </>
      ) : (
        <>
          <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Agenda de <span className="text-[var(--accent)]">Horários</span></h1>
          <p className="text-sm text-[var(--fg-3)] mb-4">Slots de entrevista abertos para os candidatos.{loading && ' · carregando…'}</p>
          <AgendaHorarios canEdit={canEdit} flash={flash} />
        </>
      )}

      {open && (
        <SolDetail
          sol={open}
          auditoria={open.aluno_id ? auds[open.aluno_id] : undefined}
          canEdit={canEdit}
          onClose={() => setOpenId(null)}
          act={act}
        />
      )}

      {toast && <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]">{toast}</div>}
    </div>
  );
}

/** KPI rico: StatCard do catálogo enriquecido com ícone em container (gap: StatCard sem slot de ícone). */
function StatBox({ value, label, icon, tone }: { value: number; label: string; icon: string; tone: string }) {
  return (
    <Card className="relative p-4 overflow-hidden" style={{ borderTop: `2px solid ${tone}` }}>
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="text-2xl font-bold tabular leading-none text-[var(--fg)]">{value.toLocaleString('pt-BR')}</div>
          <div className="mt-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}</div>
        </div>
        <span className="grid place-items-center w-8 h-8 rounded-[var(--r-md)] text-sm" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}>{icon}</span>
      </div>
    </Card>
  );
}

function SolDetail({
  sol,
  auditoria,
  canEdit,
  onClose,
  act,
}: {
  sol: Solicitacao;
  auditoria?: Auditoria;
  canEdit: boolean;
  onClose: () => void;
  act: (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => Promise<void>;
}) {
  const [rastreio, setRastreio] = useState(sol.codigo_rastreio || '');
  const [motivo, setMotivo] = useState('');
  const [showCorrecao, setShowCorrecao] = useState(false);
  const [confirmRejeitar, setConfirmRejeitar] = useState(false);
  const step = sol.auditoria_step ?? -1;
  const dates = (auditoria?.dates as Record<string, string>) || {};
  const regular = isSolicitacaoRegularizacao(sol);
  const reenvioCompleto = regular && Boolean(sol.proof_url) && Boolean(sol.declaracao_url);

  return (
    <Drawer
      width="max-w-md"
      onClose={onClose}
      title={sol.nome || '—'}
      subtitle={`${sol.email ?? ''}${sol.telefone ? ' · ' + sol.telefone : ''}`}
      badges={
        <>
          <NivelBadge nivel={sol.nivel} />
          <Badge tone="info">{computeDisplayStatus(sol).label}</Badge>
        </>
      }
    >
        {/* Timeline de auditoria */}
        <div className="mb-5">
          <Timeline
            items={AUDIT_STEPS.map((s, i): TimelineEntry => {
              const done = i < step;
              const current = i === step;
              return {
                tone: done ? 'green' : current ? 'accent' : 'base',
                done,
                icon: done ? '✓' : i + 1,
                title: s.name,
                meta: dates[s.key] || undefined,
              };
            })}
          />
        </div>

        {/* Documentos */}
        <div className="flex gap-2 mb-4 text-xs">
          {sol.proof_url && <a href={sol.proof_url} target="_blank" rel="noopener" className="px-2 py-1 rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--accent)] hover:border-[var(--border-strong)] transition-colors">Comprovante</a>}
          {sol.declaracao_url && <a href={sol.declaracao_url} target="_blank" rel="noopener" className="px-2 py-1 rounded-[var(--r-sm)] border border-[var(--border)] text-[var(--accent)] hover:border-[var(--border-strong)] transition-colors">Declaração</a>}
        </div>

        {canEdit && (
          <div className="space-y-2">
            {sol.status === 'enviado' && (
              <ActBtn onClick={() => act(() => data.bootstrapAuditoria(sol).then(() => true))}>Iniciar auditoria</ActBtn>
            )}
            {regular && reenvioCompleto && (
              <ActBtn variant="success" onClick={() => act(() => data.aprovarReenvio(sol))}>Aprovar reenvio</ActBtn>
            )}
            {!regular && step >= 0 && step < 6 && step !== 1 && (
              <ActBtn variant="success" onClick={() => act(() => data.avancarEtapa(sol))}>
                {AUDIT_STEPS[step]?.actionLabel || 'Avançar etapa'}
              </ActBtn>
            )}
            {step === 1 && <p className="text-xs text-[var(--fg-3)]">Aguardando o cliente agendar a entrevista.</p>}
            {step === 2 && (
              <ActBtn variant="danger" onClick={() => act(() => data.marcarNaoCompareceu(sol))}>Não compareceu — reabrir agendamento</ActBtn>
            )}
            {step === 4 && (
              <div className="flex gap-2">
                <Input value={rastreio} onChange={(e) => setRastreio(e.target.value)} placeholder="Código de rastreio" className="flex-1" />
                <ActBtn onClick={() => act(() => data.salvarRastreio(sol, rastreio))}>Salvar</ActBtn>
              </div>
            )}
            {step > 0 && step < 6 && (
              <ActBtn variant="ghost" onClick={() => act(() => data.voltarEtapa(sol))}>← Voltar etapa</ActBtn>
            )}
            {!showCorrecao ? (
              <ActBtn variant="ghost" onClick={() => setShowCorrecao(true)}>Solicitar correção</ActBtn>
            ) : (
              <div className="space-y-2">
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="O que precisa ser corrigido?" rows={3} className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
                <ActBtn variant="warn" onClick={() => act(() => data.solicitarCorrecao(sol, motivo))}>Enviar pedido de correção</ActBtn>
              </div>
            )}
            <ActBtn variant="danger" onClick={() => setConfirmRejeitar(true)}>Rejeitar</ActBtn>
            {confirmRejeitar && (
              <ConfirmDialog
                title="Rejeitar solicitação"
                message="Rejeitar esta solicitação?"
                confirmLabel="Rejeitar"
                danger
                onConfirm={() => { setConfirmRejeitar(false); act(() => data.rejeitar(sol)); }}
                onCancel={() => setConfirmRejeitar(false)}
              />
            )}
            <div className="flex gap-2 pt-2 border-t border-[var(--border)]">
              <ActBtn variant="ghost" onClick={() => act(() => data.marcarVisto(sol, true))}>Marcar visto</ActBtn>
              <ActBtn variant="ghost" onClick={() => act(() => data.marcarVisto(sol, false))}>Não visto</ActBtn>
            </div>
          </div>
        )}
    </Drawer>
  );
}

function ActBtn({ children, onClick, variant = 'primary' }: { children: React.ReactNode; onClick: () => void; variant?: 'primary' | 'success' | 'danger' | 'warn' | 'ghost' }) {
  // gap_catalogo: Button não tem variante "warn" (âmbar/amarelo cheio) — fallback local apenas para esse tom.
  if (variant === 'warn') {
    return (
      <button onClick={onClick} className="w-full inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] font-semibold transition-[filter,background] duration-150 px-4 py-2 text-sm bg-[var(--yellow)] text-black hover:brightness-110">{children}</button>
    );
  }
  return (
    <Button variant={variant} onClick={onClick} className="w-full">{children}</Button>
  );
}

function AgendaHorarios({ canEdit, flash }: { canEdit: boolean; flash: (m: string) => void }) {
  const [slots, setSlots] = useState<HorarioSlot[]>([]);
  const [novaData, setNovaData] = useState('');
  const [novaHora, setNovaHora] = useState('');
  const [excluirId, setExcluirId] = useState<number | null>(null);

  const reload = useCallback(async () => setSlots(await data.loadHorarios()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);

  const grouped = useMemo(() => {
    const m = new Map<string, HorarioSlot[]>();
    for (const s of slots) {
      if (!m.has(s.slot_data)) m.set(s.slot_data, []);
      m.get(s.slot_data)!.push(s);
    }
    return Array.from(m.entries());
  }, [slots]);

  return (
    <div>
      {canEdit && (
        <div className="flex flex-wrap gap-2 mb-4 items-end">
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Data</label><Input type="date" value={novaData} onChange={(e) => setNovaData(e.target.value)} className="w-auto" /></div>
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Hora</label><Input type="time" value={novaHora} onChange={(e) => setNovaHora(e.target.value)} className="w-auto" /></div>
          <Button onClick={async () => { if (novaData && novaHora && (await data.criarHorario(novaData, novaHora))) { flash('Horário criado.'); setNovaHora(''); reload(); } }}>Adicionar slot</Button>
        </div>
      )}
      {grouped.map(([d, arr]) => (
        <div key={d} className="mb-4">
          <div className="text-sm font-semibold text-[var(--fg)] mb-2">{d.split('-').reverse().join('/')}</div>
          <div className="flex flex-wrap gap-2">
            {arr.map((s) => (
              <div key={s.id} className={`flex items-center gap-2 px-3 py-1.5 rounded-[var(--r-md)] border text-sm ${s.ativo ? 'border-[var(--accent-border)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] line-through'}`}>
                {String(s.hora).slice(0, 5)}
                {canEdit && (
                  <>
                    <button onClick={async () => { if (await data.toggleHorario(s.id, !s.ativo)) reload(); }} className="text-xs text-[var(--fg-3)] hover:text-[var(--fg)]" title={s.ativo ? 'Desativar' : 'Ativar'}>{s.ativo ? '⏸' : '▶'}</button>
                    <button onClick={() => setExcluirId(s.id)} className="text-xs text-[var(--red)]" title="Excluir">✕</button>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      ))}
      {!grouped.length && <p className="text-[var(--fg-3)] text-sm">Nenhum horário cadastrado.</p>}
      {excluirId !== null && (
        <ConfirmDialog
          title="Excluir slot"
          message="Excluir slot?"
          confirmLabel="Excluir"
          danger
          onConfirm={async () => { const id = excluirId; setExcluirId(null); if (id !== null && (await data.excluirHorario(id))) reload(); }}
          onCancel={() => setExcluirId(null)}
        />
      )}
    </div>
  );
}
