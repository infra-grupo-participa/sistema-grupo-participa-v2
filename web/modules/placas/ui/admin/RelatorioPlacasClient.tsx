'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AUDIT_STEPS } from '../../domain/auditoria';
import {
  computeDisplayStatus,
  getSolicitacaoBucketMatch,
  getSolicitacaoQueuePriority,
  isSolicitacaoSeen,
  isSolicitacaoRegularizacao,
  type SolicitacaoBucket,
} from '../../domain/solicitacao';
import { nivelLabel } from '@/shared/domain/nivel-resultado';
import type { Solicitacao, Auditoria, HorarioSlot } from '../../domain/types';
import * as data from './placas-admin-data';
import { Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState } from '@/shared/ui/components';

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

  return (
    <div>
      <div className="flex items-center gap-2 mb-4">
        <h1 className="text-2xl font-bold text-[var(--fg)]">Relatório de Placas</h1>
        {loading && <span className="text-sm text-[var(--fg-3)]">carregando…</span>}
      </div>

      <div className="flex gap-2 mb-4 border-b border-[var(--border)]">
        {(['solicitacoes', 'agenda-horarios'] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => { setTab(t); window.location.hash = t; }}
            className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === t ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)]'}`}
          >
            {t === 'solicitacoes' ? 'Solicitações' : 'Agenda de Horários'}
          </button>
        ))}
      </div>

      {tab === 'solicitacoes' && (
        <>
          <div className="flex flex-wrap gap-2 mb-3">
            {BUCKETS.map((b) => (
              <button key={b.key} onClick={() => setBucket(b.key)} className={`px-3 py-1.5 rounded-[var(--r-pill)] text-sm ${bucket === b.key ? 'bg-[var(--accent-subtle)] text-[var(--fg)] border border-[var(--accent-border)]' : 'text-[var(--fg-2)] border border-[var(--border)]'}`}>
                {b.label} ({sols.filter((s) => getSolicitacaoBucketMatch(s, b.key)).length})
              </button>
            ))}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome, e-mail, documento…" className="ml-auto min-w-[220px] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-1.5 text-sm text-[var(--fg)]" />
          </div>

          <DataTable>
            <Thead>
              <Th>Aluno</Th>
              <Th>Nível</Th>
              <Th>Status</Th>
              <Th> </Th>
            </Thead>
            <tbody>
              {filtered.map((s) => {
                const ds = computeDisplayStatus(s);
                const seen = isSolicitacaoSeen(s);
                return (
                  <Tr key={s.id} onClick={() => setOpenId(s.id)}>
                    <Td>
                      <div className="flex items-center gap-2">
                        {!seen && <span className="w-2 h-2 rounded-full bg-[var(--accent)] shrink-0" title="Atualização não vista" />}
                        <div>
                          <div className="text-[var(--fg)] font-medium">{s.nome || '—'}</div>
                          <div className="text-[var(--fg-3)] text-xs">{s.email}</div>
                        </div>
                      </div>
                    </Td>
                    <Td><NivelBadge nivel={s.nivel} /></Td>
                    <Td><Badge tone={STATUS_TONE[ds.cls] || 'neutral'} dot>{ds.label}</Badge></Td>
                    <Td className="text-right text-[var(--fg-3)]">›</Td>
                  </Tr>
                );
              })}
            </tbody>
          </DataTable>
          {!filtered.length && !loading && <EmptyState title="Nenhuma solicitação neste filtro" icon="🏆" />}
        </>
      )}

      {tab === 'agenda-horarios' && <AgendaHorarios canEdit={canEdit} flash={flash} />}

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
  const step = sol.auditoria_step ?? -1;
  const dates = (auditoria?.dates as Record<string, string>) || {};
  const regular = isSolicitacaoRegularizacao(sol);
  const reenvioCompleto = regular && Boolean(sol.proof_url) && Boolean(sol.declaracao_url);

  return (
    <div className="fixed inset-0 z-[1000] flex justify-end">
      <button aria-label="Fechar" onClick={onClose} className="absolute inset-0 bg-black/50" />
      <div className="relative w-full max-w-md h-full overflow-y-auto bg-[var(--surface-1)] border-l border-[var(--border)] p-5">
        <div className="flex justify-between items-start mb-4">
          <div>
            <h2 className="text-lg font-bold text-[var(--fg)]">{sol.nome || '—'}</h2>
            <p className="text-xs text-[var(--fg-3)]">{sol.email} · {sol.telefone}</p>
            <p className="text-xs text-[var(--fg-3)]">{nivelLabel(sol.nivel) || 'sem nível'} · {computeDisplayStatus(sol).label}</p>
          </div>
          <button onClick={onClose} className="text-[var(--fg-3)] hover:text-[var(--fg)]">✕</button>
        </div>

        {/* Timeline de auditoria */}
        <div className="mb-4">
          {AUDIT_STEPS.map((s, i) => {
            const cls = i < step ? 'done' : i === step ? 'current' : 'pending';
            return (
              <div key={s.key} className="flex gap-3 py-1.5">
                <div className={`w-6 h-6 rounded-full grid place-items-center text-xs shrink-0 ${cls === 'done' ? 'bg-[var(--green)] text-black' : cls === 'current' ? 'bg-[var(--accent)] text-black' : 'bg-[var(--surface-3)] text-[var(--fg-3)]'}`}>{i < step ? '✓' : i + 1}</div>
                <div>
                  <div className={`text-sm ${cls === 'pending' ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]'}`}>{s.name}</div>
                  {dates[s.key] && <div className="text-xs text-[var(--fg-3)]">{dates[s.key]}</div>}
                </div>
              </div>
            );
          })}
        </div>

        {/* Documentos */}
        <div className="flex gap-2 mb-4 text-xs">
          {sol.proof_url && <a href={sol.proof_url} target="_blank" rel="noopener" className="px-2 py-1 rounded border border-[var(--border)] text-[var(--accent)]">Comprovante</a>}
          {sol.declaracao_url && <a href={sol.declaracao_url} target="_blank" rel="noopener" className="px-2 py-1 rounded border border-[var(--border)] text-[var(--accent)]">Declaração</a>}
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
                <input value={rastreio} onChange={(e) => setRastreio(e.target.value)} placeholder="Código de rastreio" className="flex-1 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
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
            <ActBtn variant="danger" onClick={() => { if (confirm('Rejeitar esta solicitação?')) act(() => data.rejeitar(sol)); }}>Rejeitar</ActBtn>
            <div className="flex gap-2 pt-2 border-t border-[var(--border)]">
              <ActBtn variant="ghost" onClick={() => act(() => data.marcarVisto(sol, true))}>Marcar visto</ActBtn>
              <ActBtn variant="ghost" onClick={() => act(() => data.marcarVisto(sol, false))}>Não visto</ActBtn>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ActBtn({ children, onClick, variant = 'primary' }: { children: React.ReactNode; onClick: () => void; variant?: 'primary' | 'success' | 'danger' | 'warn' | 'ghost' }) {
  const styles: Record<string, string> = {
    primary: 'bg-[var(--accent)] text-black',
    success: 'bg-[var(--green)] text-black',
    danger: 'bg-transparent text-[var(--red)] border border-[var(--red-border)]',
    warn: 'bg-[var(--yellow)] text-black',
    ghost: 'bg-transparent text-[var(--fg-2)] border border-[var(--border)]',
  };
  return (
    <button onClick={onClick} className={`w-full px-3 py-2 rounded-[var(--r-md)] text-sm font-medium ${styles[variant]}`}>{children}</button>
  );
}

function AgendaHorarios({ canEdit, flash }: { canEdit: boolean; flash: (m: string) => void }) {
  const [slots, setSlots] = useState<HorarioSlot[]>([]);
  const [novaData, setNovaData] = useState('');
  const [novaHora, setNovaHora] = useState('');

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
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Data</label><input type="date" value={novaData} onChange={(e) => setNovaData(e.target.value)} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></div>
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Hora</label><input type="time" value={novaHora} onChange={(e) => setNovaHora(e.target.value)} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" /></div>
          <button onClick={async () => { if (novaData && novaHora && (await data.criarHorario(novaData, novaHora))) { flash('Horário criado.'); setNovaHora(''); reload(); } }} className="px-4 py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black text-sm font-medium">Adicionar slot</button>
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
                    <button onClick={async () => { if (confirm('Excluir slot?') && (await data.excluirHorario(s.id))) reload(); }} className="text-xs text-[var(--red)]" title="Excluir">✕</button>
                  </>
                )}
              </div>
            ))}
          </div>
        </div>
      ))}
      {!grouped.length && <p className="text-[var(--fg-3)] text-sm">Nenhum horário cadastrado.</p>}
    </div>
  );
}
