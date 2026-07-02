'use client';

import { memo, useCallback, useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { AUDIT_STEP_TOTAL } from '../../domain/auditoria';
import {
  computeDisplayStatus,
  getSolicitacaoBucketMatch,
  getSolicitacaoQueuePriority,
  isSolicitacaoSeen,
  isSolicitacaoRegularizacao,
  type SolicitacaoBucket,
} from '../../domain/solicitacao';
import type { Solicitacao, Auditoria } from '../../domain/types';
import * as data from './placas-admin-data';
import * as configData from './placas-config-data';
import { resolveAuditSteps, type PlacasConfig } from '../../domain/config';
import { Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState, SearchInput, ProgressBar, Toast, useFlash } from '@/shared/ui/components';
import { SolicitacaoDrawer } from './SolicitacaoDrawer';
import { ConfigPanel } from './ConfigPanel';
import { AgendaHorarios } from './AgendaHorarios';
import { fmtRelativo } from './relatorio-shared';

const APP_URL = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';

/** Progresso visual da solicitação: fração 0–1 + rótulo + tom semântico. */
function progresso(s: Solicitacao): { pct: number; label: string; tone: 'accent' | 'green' | 'yellow' | 'red' } {
  if (isSolicitacaoRegularizacao(s)) return { pct: 0.15, label: 'Correção', tone: 'yellow' };
  if (s.status === 'concluido') return { pct: 1, label: 'Concluído', tone: 'green' };
  if (s.status === 'rejeitado') return { pct: 1, label: 'Rejeitado', tone: 'red' };
  const step = Number(s.auditoria_step ?? -1);
  if (step >= 0) return { pct: (step + 1) / AUDIT_STEP_TOTAL, label: `${step + 1}/${AUDIT_STEP_TOTAL}`, tone: 'accent' };
  if (s.status === 'cadastro_concluido') return { pct: 1, label: 'Cadastro', tone: 'green' };
  const form = Math.max(0, Math.min(Number(s.step_index ?? 0), 9));
  return { pct: (form / 9) * 0.4, label: 'Rascunho', tone: 'accent' };
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

type Tab = 'solicitacoes' | 'agenda-horarios' | 'config';

/** Gavetas da fila — os cards de KPI são o próprio seletor (substituem a fita de abas). */
const BUCKETS: { key: SolicitacaoBucket; label: string; hint: string; icon: string; tone: string }[] = [
  { key: 'processo', label: 'Em processo', hint: 'auditoria e ações em aberto', icon: 'rotate', tone: 'var(--accent)' },
  { key: 'rascunhos', label: 'Rascunhos', hint: 'formulário não enviado', icon: 'file', tone: 'var(--nivel-platina)' },
  { key: 'cadastro', label: 'Somente cadastro', hint: 'cadastro sem auditoria', icon: 'clipboard', tone: 'var(--fg-2)' },
  { key: 'questionarios', label: 'Finalizados', hint: 'concluídos e rejeitados', icon: 'check', tone: 'var(--green)' },
];

export function RelatorioPlacasClient({ canEdit }: { canEdit: boolean }) {
  const [tab, setTab] = useState<Tab>('solicitacoes');
  const [sols, setSols] = useState<Solicitacao[]>([]);
  const [auds, setAuds] = useState<Record<string, Auditoria>>({});
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState<SolicitacaoBucket>('processo');
  const [q, setQ] = useState('');
  const [openId, setOpenId] = useState<string | null>(null);
  const { toast, flash } = useFlash();
  const [cfg, setCfg] = useState<PlacasConfig | null>(null);
  const [copiado, setCopiado] = useState(false);
  // Origem real do deploy (ex.: domínio da Hostinger) — resolvida no cliente p/ o link ficar fiel.
  const [origin, setOrigin] = useState(APP_URL);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setOrigin(window.location.origin), []);

  const steps = useMemo(() => resolveAuditSteps(cfg?.audit_steps), [cfg]);

  const indexAuditorias = (a: Auditoria[]) => {
    const map: Record<string, Auditoria> = {};
    for (const au of a) if (au.aluno_id) map[au.aluno_id] = au;
    return map;
  };

  const reload = useCallback(async () => {
    const [s, a] = await Promise.all([data.loadSolicitacoes(), data.loadAuditorias()]);
    setSols(s);
    setAuds(indexAuditorias(a));
  }, []);

  useEffect(() => {
    (async () => {
      // Uma única carga no mount; só recarrega se o auto-start alterou algo no banco.
      const [initialSols, auditorias] = await Promise.all([data.loadSolicitacoes(), data.loadAuditorias()]);
      if (canEdit && (await data.autoStartPending(initialSols))) {
        await reload();
      } else {
        setSols(initialSols);
        setAuds(indexAuditorias(auditorias));
      }
      configData.loadPlacasConfig().then(setCfg).catch(() => {});
      setLoading(false);
    })();
    // A sidebar dispara 'hashchange' nativo ao trocar de aba na mesma rota (ver Sidebar.tsx),
    // então basta escutar hashchange/popstate + ler o hash no mount.
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'agenda-horarios') setTab('agenda-horarios');
      else if (h === 'config') setTab('config');
      else setTab('solicitacoes');
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    window.addEventListener('popstate', applyHash);
    return () => {
      window.removeEventListener('hashchange', applyHash);
      window.removeEventListener('popstate', applyHash);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const act = useCallback(async (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => {
    const r = await fn();
    const ok = typeof r === 'boolean' ? r : r.ok;
    const msg = typeof r === 'boolean' ? (ok ? 'Feito!' : 'Falhou.') : r.msg || (ok ? 'Feito!' : 'Falhou.');
    flash(msg);
    await reload();
  }, [reload, flash]);

  // Contagens por gaveta + não-vistos em um único passe.
  const counts = useMemo(() => {
    const c: Record<SolicitacaoBucket, number> = { processo: 0, rascunhos: 0, cadastro: 0, questionarios: 0 };
    let naoVistos = 0;
    for (const s of sols) {
      for (const b of BUCKETS) if (getSolicitacaoBucketMatch(s, b.key)) c[b.key]++;
      if (!isSolicitacaoSeen(s)) naoVistos++;
    }
    return { ...c, naoVistos };
  }, [sols]);

  // Busca adiada: digitar não trava a renderização da tabela.
  const dq = useDeferredValue(q);
  const filtered = useMemo(() => {
    const term = dq.trim().toLowerCase();
    return sols
      .filter((s) => getSolicitacaoBucketMatch(s, bucket))
      .filter((s) => !term || `${s.nome ?? ''} ${s.email ?? ''} ${s.documento_nf ?? ''}`.toLowerCase().includes(term))
      .sort((a, b) => {
        // Não-vistos (ação nova do cliente) sempre no topo — estilo caixa de WhatsApp.
        const sa = isSolicitacaoSeen(a) ? 1 : 0;
        const sb = isSolicitacaoSeen(b) ? 1 : 0;
        if (sa !== sb) return sa - sb;
        return getSolicitacaoQueuePriority(a) - getSolicitacaoQueuePriority(b);
      });
  }, [sols, bucket, dq]);

  const open = openId ? sols.find((s) => s.id === openId) ?? null : null;
  const abrir = useCallback((id: string) => setOpenId(id), []);
  const linkPublico = `${origin}/solicitar-placa`;
  const hoje = new Date().toLocaleDateString('pt-BR', { day: '2-digit', month: 'long', year: 'numeric' });

  return (
    <div>
      {tab === 'solicitacoes' ? (
        <>
          <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
            <h1 className="text-2xl font-bold text-[var(--fg)]">
              Solicitações de <span className="text-[var(--accent)]">Placas</span>
              <span className="ml-2 align-middle text-xs font-semibold rounded-[var(--r-pill)] bg-[var(--accent-subtle)] text-[var(--accent)] px-2 py-0.5 tabular">{sols.length}</span>
            </h1>
            <div className="flex items-center gap-2">
              <button
                title={linkPublico}
                onClick={() => { navigator.clipboard?.writeText(linkPublico); setCopiado(true); setTimeout(() => setCopiado(false), 1500); }}
                className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent border transition-colors text-[var(--fg-2)] border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]"
              >
                {copiado ? <><Icon name="check" size={14} className="text-[var(--green)]" /> Copiado!</> : <><Icon name="link" size={14} /> Copiar link do formulário</>}
              </button>
              {canEdit && (
                <button onClick={() => { window.location.hash = 'config'; setTab('config'); }} className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="settings" size={14} /> Configurações</button>
              )}
              <a href="/sistema/admin-dev" className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="notebook" size={14} /> Logs</a>
            </div>
          </div>
          <p className="text-sm text-[var(--fg-3)] mb-4">Candidatos que iniciaram o processo via formulário público · Atualizado em {hoje}</p>

          {/* Fila em gavetas: os cards filtram a tabela (substituem a fita de abas) */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4" role="tablist" aria-label="Filas de solicitações">
            {BUCKETS.map((b) => (
              <QueueCard
                key={b.key}
                label={b.label}
                hint={b.hint}
                icon={b.icon}
                tone={b.tone}
                value={counts[b.key]}
                active={bucket === b.key}
                badge={b.key === 'processo' && counts.naoVistos > 0 ? `${counts.naoVistos} ação do cliente` : undefined}
                onClick={() => setBucket(b.key)}
              />
            ))}
          </div>

          {/* Busca */}
          <div className="mb-3 flex items-center gap-3">
            <div className="flex-1"><SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por nome, e-mail ou documento…" /></div>
            {dq.trim() && <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{filtered.length} {filtered.length === 1 ? 'resultado' : 'resultados'}</span>}
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
              {loading && !sols.length
                ? <SkeletonRows />
                : filtered.map((s) => <LinhaSolicitacao key={s.id} s={s} onOpen={abrir} />)}
            </tbody>
          </DataTable>
          {!filtered.length && !loading && (
            <EmptyState
              title={dq.trim() ? 'Nenhuma solicitação encontrada na busca' : 'Nenhuma solicitação nesta fila'}
              hint={dq.trim() ? 'Confira a grafia ou limpe a busca.' : 'Selecione outra fila acima para ver as demais.'}
              icon="trophy"
            />
          )}
        </>
      ) : tab === 'agenda-horarios' ? (
        <>
          <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Agenda de <span className="text-[var(--accent)]">Horários</span></h1>
          <p className="text-sm text-[var(--fg-3)] mb-4">Slots de entrevista abertos e agendamentos dos candidatos.{loading && ' · carregando…'}</p>
          <AgendaHorarios
            canEdit={canEdit}
            flash={flash}
            agendamentos={sols
              .filter((s) => s.entrevista_data && s.entrevista_hora)
              .map((s) => ({ data: s.entrevista_data as string, hora: String(s.entrevista_hora).slice(0, 5), nome: s.nome, email: s.email }))}
          />
        </>
      ) : (
        <ConfigPanel canEdit={canEdit} cfg={cfg} onSaved={(next) => setCfg(next)} onBack={() => { window.location.hash = ''; setTab('solicitacoes'); }} flash={flash} />
      )}

      {open && (
        <SolicitacaoDrawer
          sol={open}
          auditoria={open.aluno_id ? auds[open.aluno_id] : undefined}
          canEdit={canEdit}
          steps={steps}
          onClose={() => setOpenId(null)}
          act={act}
        />
      )}

      <Toast>{toast}</Toast>
    </div>
  );
}

/** Card-gaveta da fila: KPI clicável que filtra a tabela. Ativo = borda âmbar + rótulo aceso. */
function QueueCard({ label, hint, icon, tone, value, active, badge, onClick }: {
  label: string; hint: string; icon: string; tone: string; value: number; active: boolean; badge?: string; onClick: () => void;
}) {
  return (
    <button
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`text-left rounded-[var(--r-lg)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-4 border transition-colors ${active ? 'border-[var(--border-accent)]' : 'border-[var(--border)] hover:border-[var(--border-strong)]'}`}
      style={{ borderTopWidth: 2, borderTopColor: tone }}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-2xl font-bold tabular leading-none text-[var(--fg)]">{value.toLocaleString('pt-BR')}</div>
          <div className={`mt-2 text-[11px] font-semibold uppercase tracking-wide ${active ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>{label}</div>
          {badge ? (
            <div className="mt-1 inline-flex items-center gap-1.5 text-[11px] font-semibold text-[var(--accent)]">
              <span className="w-1.5 h-1.5 rounded-full bg-[var(--accent)] animate-pulse" /> {badge}
            </div>
          ) : (
            <div className="mt-1 text-[11px] text-[var(--fg-3)] truncate">{hint}</div>
          )}
        </div>
        <span className="grid place-items-center w-8 h-8 rounded-[var(--r-md)] shrink-0" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}><Icon name={icon} size={16} /></span>
      </div>
    </button>
  );
}

/** Linha da fila — memoizada: digitar na busca não re-renderiza linhas que não mudaram. */
const LinhaSolicitacao = memo(function LinhaSolicitacao({ s, onOpen }: { s: Solicitacao; onOpen: (id: string) => void }) {
  const ds = computeDisplayStatus(s);
  const seen = isSolicitacaoSeen(s);
  const pr = progresso(s);
  const quando = fmtRelativo(s.updated_at);
  return (
    <Tr
      onClick={() => onOpen(s.id)}
      className={!seen ? '!bg-[var(--accent-subtle)] hover:!bg-[var(--accent-subtle)]' : ''}
      style={!seen ? { boxShadow: 'inset 3px 0 0 0 var(--accent)' } : undefined}
    >
      <Td>
        <div className="flex items-center gap-2.5">
          <span className={`relative grid place-items-center w-8 h-8 rounded-full font-bold text-sm shrink-0 ${!seen ? 'bg-[var(--accent)] text-black' : 'bg-[var(--surface-4)] text-[var(--fg-2)]'}`}>
            {initial(s.nome)}
            {!seen && <span className="absolute -top-0.5 -right-0.5 w-3 h-3 rounded-full bg-[var(--accent)] ring-2 ring-[var(--surface-2)] animate-pulse" title="Ação nova do cliente" />}
          </span>
          <div className="min-w-0">
            <div className={`truncate flex items-center gap-1.5 ${!seen ? 'text-[var(--fg)] font-bold' : 'text-[var(--fg)] font-medium'}`}>
              {s.nome || '—'}
              {!seen && <span className="shrink-0 text-[10px] font-bold uppercase tracking-wide rounded-[var(--r-pill)] bg-[var(--accent)] text-black px-1.5 py-px">Novo</span>}
            </div>
            <div className={`text-xs truncate ${!seen ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>{s.email}</div>
          </div>
        </div>
      </Td>
      <Td><NivelBadge nivel={s.nivel} /></Td>
      <Td><Badge tone={STATUS_TONE[ds.cls] || 'neutral'} dot>{ds.label}</Badge></Td>
      <Td>
        <div className="flex items-center gap-2 min-w-[120px]">
          <div className="flex-1"><ProgressBar value={pr.pct * 100} height={6} tone={pr.tone} /></div>
          <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{pr.label}</span>
        </div>
      </Td>
      <Td>{s.turma ? <span className="text-xs font-semibold rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)] px-2 py-0.5">{s.turma}</span> : <span className="text-[var(--fg-3)]">—</span>}</Td>
      <Td className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap"><span title={quando.title}>{quando.label}</span></Td>
    </Tr>
  );
});

/** Esqueleto da tabela durante a primeira carga — mesma métrica das linhas reais. */
function SkeletonRows() {
  return (
    <>
      {Array.from({ length: 6 }).map((_, i) => (
        <tr key={i} className="border-t border-[var(--border-faint)]">
          <td className="px-3 py-2.5">
            <div className="flex items-center gap-2.5">
              <span className="w-8 h-8 rounded-full bg-[var(--surface-3)] animate-pulse shrink-0" />
              <div className="space-y-1.5">
                <div className="h-3 w-36 rounded bg-[var(--surface-3)] animate-pulse" />
                <div className="h-2.5 w-44 rounded bg-[var(--surface-3)] animate-pulse" />
              </div>
            </div>
          </td>
          {[16, 20, 24, 10, 14].map((w, j) => (
            <td key={j} className="px-3 py-2.5"><div className={`h-3 rounded bg-[var(--surface-3)] animate-pulse`} style={{ width: `${w * 4}px` }} /></td>
          ))}
        </tr>
      ))}
    </>
  );
}
