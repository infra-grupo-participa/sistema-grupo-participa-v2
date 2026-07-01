'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { AUDIT_STEP_TOTAL, AUDIT_STEP_INDEX, type AuditStep } from '../../domain/auditoria';
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
import * as configData from './placas-config-data';
import {
  resolveAuditSteps,
  auditStepsToEditable,
  EMAIL_TIPOS_CONFIG,
  DEFAULT_NIVEL_FAIXAS,
  DEFAULT_FORM_TEXTOS,
  NIVEL_FAIXA_ORDER,
  type PlacasConfig,
  type EmailTemplateOverride,
  type NivelFaixa,
  type EspacoOption,
} from '../../domain/config';
import { Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState, Drawer, AvatarInicial, Card, Button, SearchInput, Input, FilterSelect, ProgressBar, ConfirmDialog } from '@/shared/ui/components';

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

type Tab = 'solicitacoes' | 'agenda-horarios' | 'config';
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
  const [cfg, setCfg] = useState<PlacasConfig | null>(null);

  const steps = useMemo(() => resolveAuditSteps(cfg?.audit_steps), [cfg]);

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
      configData.loadPlacasConfig().then(setCfg).catch(() => {});
      setLoading(false);
    })();
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'agenda-horarios') setTab('agenda-horarios');
      else if (h === 'config') setTab('config');
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
      .sort((a, b) => {
        // Não-vistos (ação nova do cliente) sempre no topo — estilo caixa de WhatsApp.
        const sa = isSolicitacaoSeen(a) ? 1 : 0;
        const sb = isSolicitacaoSeen(b) ? 1 : 0;
        if (sa !== sb) return sa - sb;
        return getSolicitacaoQueuePriority(a) - getSolicitacaoQueuePriority(b);
      });
  }, [sols, bucket, q]);
  const naoVistos = useMemo(() => sols.filter((s) => !isSolicitacaoSeen(s)).length, [sols]);

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
            <div className="flex items-center gap-2">
              {canEdit && (
                <button onClick={() => { window.location.hash = 'config'; setTab('config'); }} className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="settings" size={14} /> Configurações</button>
              )}
              <a href="/sistema/admin-dev" className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="notebook" size={14} /> Logs</a>
            </div>
          </div>
          <p className="text-sm text-[var(--fg-3)] mb-4">Candidatos que iniciaram o processo via formulário público · Atualizado em {hoje}{loading && ' · carregando…'}{naoVistos > 0 && <span className="ml-1 font-semibold text-[var(--accent)]">· {naoVistos} com ação nova do cliente</span>}</p>

          {/* Stat cards com acento + ícone */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <StatBox value={stats.total} label="Total de processos" icon="clipboard" tone="var(--fg-2)" />
            <StatBox value={stats.finalizadas} label="Finalizadas" icon="check" tone="var(--green)" />
            <StatBox value={stats.emAndamento} label="Em andamento" icon="rotate" tone="var(--accent)" />
            <StatBox value={stats.rascunhos} label="Rascunhos" icon="file" tone="var(--nivel-platina)" />
          </div>

          {/* Link do questionário público */}
          <Card className="p-3 mb-4 flex items-center gap-3 flex-wrap">
            <span className="text-[var(--fg-3)]"><Icon name="link" size={15} /></span>
            <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Link de envio do questionário</span>
            <Input readOnly value={linkPublico} className="flex-1 min-w-[200px] !text-[var(--accent)] font-mono" />
            <Button variant="subtle" size="sm" onClick={() => { navigator.clipboard?.writeText(linkPublico); setCopiado(true); setTimeout(() => setCopiado(false), 1500); }}>
              {copiado ? <><Icon name="check" size={14} /> Copiado</> : <><Icon name="copy" size={14} /> Copiar link</>}
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
                  <Tr
                    key={s.id}
                    onClick={() => setOpenId(s.id)}
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
          {!filtered.length && !loading && <EmptyState title="Nenhuma solicitação neste filtro" icon="trophy" />}
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
        <SolDetail
          sol={open}
          auditoria={open.aluno_id ? auds[open.aluno_id] : undefined}
          canEdit={canEdit}
          steps={steps}
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
        <span className="grid place-items-center w-8 h-8 rounded-[var(--r-md)]" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}><Icon name={icon} size={16} /></span>
      </div>
    </Card>
  );
}

function SolDetail({
  sol,
  auditoria,
  canEdit,
  steps,
  onClose,
  act,
}: {
  sol: Solicitacao;
  auditoria?: Auditoria;
  canEdit: boolean;
  steps: AuditStep[];
  onClose: () => void;
  act: (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => Promise<void>;
}) {
  const [rastreio, setRastreio] = useState(sol.codigo_rastreio || '');
  const [motivo, setMotivo] = useState('');
  const [showCorrecao, setShowCorrecao] = useState(false);
  const [confirmExcluir, setConfirmExcluir] = useState(false);
  const [editando, setEditando] = useState(false);
  const step = sol.auditoria_step ?? -1;
  const dates = (auditoria?.dates as Record<string, string>) || {};
  const regular = isSolicitacaoRegularizacao(sol);
  const reenvioCompleto = regular && Boolean(sol.proof_url) && Boolean(sol.declaracao_url);

  return (
    <Drawer
      width="max-w-5xl"
      onClose={onClose}
      avatar={<AvatarInicial nome={sol.nome} />}
      title={sol.nome || '—'}
      subtitle={`${sol.email ?? ''}${sol.telefone ? ' · ' + sol.telefone : ''}`}
      badges={
        <>
          <NivelBadge nivel={sol.nivel} />
          <Badge tone="accent" dot>{step >= 0 && !regular ? `${step + 1}/${AUDIT_STEP_TOTAL} · ` : ''}{computeDisplayStatus(sol).label}</Badge>
          {sol.admin_seen_at && <Badge tone="neutral">Visto</Badge>}
        </>
      }
      actions={canEdit ? (
        <div className="hidden sm:flex gap-1.5">
          <Button size="sm" variant={editando ? 'primary' : 'subtle'} onClick={() => setEditando((v) => !v)}><Icon name="pencil" size={13} /> {editando ? 'Fechar edição' : 'Editar dados'}</Button>
          <Button size="sm" variant="subtle" onClick={() => act(() => data.marcarVisto(sol, true))}>Marcar visto</Button>
          <Button size="sm" variant="ghost" onClick={() => act(() => data.marcarVisto(sol, false))}>Não visto</Button>
        </div>
      ) : undefined}
      footer={canEdit ? (
        <>
          {step > 0 && step < AUDIT_STEP_TOTAL - 1 && <Button size="sm" variant="ghost" onClick={() => act(() => data.voltarEtapa(sol))}><Icon name="arrow-left" size={13} /> Etapa anterior</Button>}
          {step >= 0 && step < AUDIT_STEP_TOTAL - 1 && <Button size="sm" variant="success" onClick={() => act(() => data.confirmarJaPossuiPlaca(sol))}><Icon name="check" size={13} /> Já possui placa — avançar para o final</Button>}
          <Button size="sm" variant="ghost" onClick={() => setShowCorrecao((v) => !v)}><Icon name="rotate" size={13} /> Correção</Button>
          <div className="ml-auto"><Button size="sm" variant="danger" onClick={() => setConfirmExcluir(true)}><Icon name="trash" size={13} /> Excluir</Button></div>
        </>
      ) : undefined}
    >
      <div className="grid gap-4 lg:grid-cols-[1fr_300px] items-start">
        {/* Coluna principal */}
        <div className="space-y-4 min-w-0">
          {canEdit && editando && (
            <EditarDados sol={sol} act={act} onDone={() => setEditando(false)} />
          )}

          {sol.regularizacao_pendente && sol.motivo_retorno && (
            <Panel icon="alert" title="Motivo do retorno" accent="var(--yellow)">
              <p className="text-sm text-[var(--fg-2)] leading-relaxed whitespace-pre-wrap">{sol.motivo_retorno}</p>
            </Panel>
          )}

          <Panel icon="arrow-right" title="Próxima ação">
            {!canEdit ? (
              <p className="text-sm text-[var(--fg-3)]">Somente leitura.</p>
            ) : regular && !reenvioCompleto ? (
              <div className="rounded-[var(--r-md)] bg-[var(--yellow-subtle)] p-3 text-sm flex items-start gap-2">
                <Icon name="alert" size={16} className="text-[var(--yellow)] mt-0.5 shrink-0" />
                <div><div className="font-semibold text-[var(--yellow)]">Cliente em correção</div><div className="text-[var(--fg-2)] mt-0.5">Aguardando novo envio de documentação ou correção do questionário pelo cliente. Quando ele reenviar, o processo volta para a fila ativa.</div></div>
              </div>
            ) : regular && reenvioCompleto ? (
              <>
                <div className="rounded-[var(--r-md)] bg-[var(--green-subtle)] p-3 text-sm mb-3 flex items-start gap-2">
                  <Icon name="check-circle" size={16} className="text-[var(--green)] mt-0.5 shrink-0" />
                  <div><div className="font-semibold text-[var(--green)]">Reenvio recebido</div><div className="text-[var(--fg-2)] mt-0.5">A cliente reenviou os documentos da correção. Se estiverem corretos, aprove para enviar o link de agendamento.</div></div>
                </div>
                <BigAction variant="success" icon="check" onClick={() => act(() => data.aprovarReenvio(sol))}>Aprovar reenvio</BigAction>
              </>
            ) : step < 0 || sol.status === 'enviado' ? (
              <BigAction icon="play" onClick={() => act(() => data.bootstrapAuditoria(sol).then(() => true))}>Iniciar auditoria</BigAction>
            ) : step === AUDIT_STEP_INDEX.DOCS_APROVADOS ? (
              <p className="text-sm text-[var(--fg-2)]">Aguardando o cliente agendar a entrevista.</p>
            ) : step >= AUDIT_STEP_INDEX.PLACA_RECEBIDA ? (
              <div className="rounded-[var(--r-md)] bg-[var(--green-subtle)] text-[var(--green)] p-3 text-sm inline-flex items-center gap-2"><Icon name="check-circle" size={16} /> Processo concluído — placa recebida.</div>
            ) : (
              <>
                <p className="text-sm text-[var(--fg-2)] mb-3 leading-relaxed">{steps[step]?.desc}</p>
                {step === AUDIT_STEP_INDEX.PLACA_EM_CONFECCAO && (
                  <div className="flex gap-2 mb-2">
                    <Input value={rastreio} onChange={(e) => setRastreio(e.target.value)} placeholder="Código de rastreio" className="flex-1" />
                    <Button variant="subtle" onClick={() => act(() => data.salvarRastreio(sol, rastreio))}>Salvar</Button>
                  </div>
                )}
                <BigAction icon="check" onClick={() => act(() => data.avancarEtapa(sol))}>{steps[step]?.actionLabel || 'Avançar etapa'}</BigAction>
                {step === AUDIT_STEP_INDEX.ENTREVISTA_AGENDADA && (
                  <button onClick={() => act(() => data.marcarNaoCompareceu(sol))} className="w-full mt-2 inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-2 text-sm font-medium text-[var(--red)] border border-[var(--red-border)] hover:bg-[var(--red-subtle)] transition-colors"><Icon name="x" size={14} /> Não compareceu — reabrir agendamento</button>
                )}
              </>
            )}
            {showCorrecao && canEdit && (
              <div className="mt-3 space-y-2 pt-3 border-t border-[var(--border)]">
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="O que precisa ser corrigido?" rows={3} className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
                <Button variant="subtle" onClick={() => act(() => data.solicitarCorrecao(sol, motivo).then((ok) => { if (ok) setShowCorrecao(false); return ok; }))}>Enviar pedido de correção</Button>
              </div>
            )}
          </Panel>

          {sol.entrevista_data && (
            <Panel icon="calendar" title="Entrevista agendada">
              <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-4 text-center mb-3">
                <div className="text-lg font-bold text-[var(--fg)] capitalize">{fmtDataExtenso(sol.entrevista_data)}</div>
                {sol.entrevista_hora && <div className="text-sm text-[var(--info)] mt-1 inline-flex items-center gap-1.5"><Icon name="calendar" size={14} /> Às {String(sol.entrevista_hora).slice(0, 5)}</div>}
              </div>
              {(sol.meet_link || sol.entrevista_link) && (
                <a href={sol.meet_link || sol.entrevista_link!} target="_blank" rel="noopener" className="w-full inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 transition-[filter]" style={{ background: 'var(--info)' }}><Icon name="camera" size={15} /> Abrir sala da entrevista</a>
              )}
            </Panel>
          )}

          <Panel icon="coins" title="Faturamento & Comprovação" accent="var(--accent)">
            <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-4 mb-3">
              <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Faturamento declarado</div>
              <div className="text-2xl font-bold tabular text-[var(--fg)] mt-1">{fmtBRL(sol.faturamento_declarado)}</div>
            </div>
            <div className="grid sm:grid-cols-2 gap-2 mb-3">
              <DocLink url={sol.proof_url} label="Comprovante financeiro" />
              <DocLink url={sol.declaracao_url} label="Declaração assinada" />
            </div>
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              <Row2 k="Nível atual" v={<NivelBadge nivel={sol.nivel} />} />
              <Row2 k="Espaço de instrução" v={sol.espaco_instrucao} />
              <Row2 k="Interesse" v={sol.interesse} />
            </div>
          </Panel>

          {!editando && (
          <Panel icon="user" title="Dados Pessoais">
            <div className="grid sm:grid-cols-2 sm:gap-x-6">
              <Row2 k="Nome" v={sol.nome} />
              <Row2 k="E-mail" v={sol.email} />
              <Row2 k="Telefone" v={sol.telefone} />
              <Row2 k="Profissão" v={sol.profissao} />
              <Row2 k="Endereço" v={[sol.logradouro, sol.numero, sol.bairro, sol.cidade, sol.estado_uf].filter(Boolean).join(', ') || null} />
              <Row2 k="CEP" v={sol.cep} />
              <Row2 k="Documento (NF)" v={sol.documento_nf} />
              <Row2 k="E-mail de entrega" v={sol.email_entrega} />
              {sol.codigo_rastreio && <Row2 k="Código de rastreio" v={sol.codigo_rastreio} />}
            </div>
          </Panel>
          )}
        </div>

        {/* Coluna lateral: status + remanejamento */}
        <div className="space-y-4">
          <Panel icon="check-circle" title="Status da auditoria">
            <ol className="space-y-1">
              {steps.map((s, i) => {
                const done = i < step;
                const current = i === step;
                return (
                  <li key={s.key} className={`flex items-center gap-2.5 rounded-[var(--r-md)] px-2 py-1.5 ${current ? 'bg-[var(--accent-subtle)] border border-[var(--accent-border)]' : ''}`}>
                    <span className="grid place-items-center w-6 h-6 rounded-full text-[11px] font-bold shrink-0" style={{ background: done ? 'var(--green)' : current ? 'var(--accent)' : 'var(--surface-4)', color: done || current ? '#fff' /* hex-ok: contraste */ : 'var(--fg-3)' }}>{done ? <Icon name="check" size={12} strokeWidth={3} /> : i + 1}</span>
                    <span className={`text-sm ${current ? 'font-semibold text-[var(--fg)]' : done ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>{s.name}</span>
                    {dates[s.key] && <span className="ml-auto text-[10px] tabular text-[var(--fg-3)] shrink-0">{dates[s.key]}</span>}
                  </li>
                );
              })}
            </ol>
          </Panel>

          {canEdit && step >= 0 && (
            <Panel title="Remanejamento rápido">
              <div className="flex flex-wrap gap-1.5">
                {steps.map((s, i) => {
                  const done = i < step;
                  const current = i === step;
                  return (
                    <button key={s.key} title={s.name} onClick={() => act(() => data.setAuditStep(sol, i))} className="grid place-items-center w-8 h-8 rounded-full text-xs font-bold border border-[var(--border)] transition-[filter] hover:brightness-125" style={{ background: done ? 'var(--green)' : current ? 'var(--accent)' : 'var(--surface-3)', color: done || current ? '#fff' /* hex-ok: contraste */ : 'var(--fg-2)' }}>{i + 1}</button>
                  );
                })}
              </div>
              <p className="text-[11px] text-[var(--fg-3)] mt-2">Clique para posicionar a auditoria na etapa (não dispara e-mails).</p>
            </Panel>
          )}
        </div>
      </div>

      {confirmExcluir && (
        <ConfirmDialog
          title="Excluir solicitação"
          message="Excluir esta solicitação e a auditoria vinculada? Ação irreversível."
          confirmLabel="Excluir"
          danger
          onConfirm={() => { setConfirmExcluir(false); act(() => data.excluirSolicitacao(sol)); }}
          onCancel={() => setConfirmExcluir(false)}
        />
      )}
    </Drawer>
  );
}

// ── Edição inline dos dados do aluno (drawer) ──────────────────────────────
const NIVEL_OPCOES = NIVEL_FAIXA_ORDER.map((v) => ({ v, l: DEFAULT_NIVEL_FAIXAS[v].nm }));

function CampoEdit({ label, children, full }: { label: string; children: React.ReactNode; full?: boolean }) {
  return (
    <label className={`block ${full ? 'sm:col-span-2' : ''}`}>
      <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}</span>
      <div className="mt-1">{children}</div>
    </label>
  );
}

function EditarDados({
  sol,
  act,
  onDone,
}: {
  sol: Solicitacao;
  act: (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => Promise<void>;
  onDone: () => void;
}) {
  const [f, setF] = useState<Record<string, string>>({
    nome: sol.nome ?? '',
    email: sol.email ?? '',
    telefone: sol.telefone ?? '',
    turma: sol.turma ?? '',
    profissao: sol.profissao ?? '',
    nivel: sol.nivel ?? '',
    interesse: sol.interesse ?? '',
    espaco_instrucao: sol.espaco_instrucao ?? '',
    faturamento_declarado: sol.faturamento_declarado != null ? String(sol.faturamento_declarado) : '',
    documento_nf: sol.documento_nf ?? '',
    email_entrega: sol.email_entrega ?? '',
    cep: sol.cep ?? '',
    logradouro: sol.logradouro ?? '',
    numero: sol.numero ?? '',
    complemento: sol.complemento ?? '',
    bairro: sol.bairro ?? '',
    cidade: sol.cidade ?? '',
    estado_uf: sol.estado_uf ?? '',
  });
  const set = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));

  async function salvar() {
    const fatDigits = f.faturamento_declarado.replace(/\D/g, '');
    const campos: data.DadosEditaveis = {
      nome: f.nome,
      email: f.email,
      telefone: f.telefone,
      turma: f.turma,
      profissao: f.profissao,
      nivel: f.nivel,
      interesse: f.interesse,
      espaco_instrucao: f.espaco_instrucao,
      faturamento_declarado: fatDigits ? Number(fatDigits) : null,
      documento_nf: f.documento_nf,
      email_entrega: f.email_entrega,
      cep: f.cep,
      logradouro: f.logradouro,
      numero: f.numero,
      complemento: f.complemento,
      bairro: f.bairro,
      cidade: f.cidade,
      estado_uf: f.estado_uf,
    };
    await act(() => data.atualizarDadosSolicitacao(sol, campos));
    onDone();
  }

  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--accent-border)] bg-[var(--surface-2)] p-4" style={{ borderLeft: '3px solid var(--accent)' }}>
      <div className="flex items-center gap-2 mb-3 text-[11px] font-bold uppercase tracking-wider text-[var(--accent)]">
        <Icon name="pencil" size={14} /> Editando dados do aluno
      </div>
      <div className="grid sm:grid-cols-2 gap-3">
        <CampoEdit label="Nome"><Input value={f.nome} onChange={(e) => set('nome', e.target.value)} /></CampoEdit>
        <CampoEdit label="E-mail"><Input value={f.email} onChange={(e) => set('email', e.target.value)} /></CampoEdit>
        <CampoEdit label="Telefone"><Input value={f.telefone} onChange={(e) => set('telefone', e.target.value)} /></CampoEdit>
        <CampoEdit label="Profissão"><Input value={f.profissao} onChange={(e) => set('profissao', e.target.value)} /></CampoEdit>
        <CampoEdit label="Turma"><Input value={f.turma} onChange={(e) => set('turma', e.target.value)} placeholder="T1, A2…" /></CampoEdit>
        <CampoEdit label="Nível">
          <FilterSelect value={f.nivel} onChange={(e) => set('nivel', e.target.value)}>
            <option value="">— sem nível —</option>
            {NIVEL_OPCOES.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
          </FilterSelect>
        </CampoEdit>
        <CampoEdit label="Espaço de instrução"><Input value={f.espaco_instrucao} onChange={(e) => set('espaco_instrucao', e.target.value)} /></CampoEdit>
        <CampoEdit label="Interesse"><Input value={f.interesse} onChange={(e) => set('interesse', e.target.value)} /></CampoEdit>
        <CampoEdit label="Faturamento declarado (R$)"><Input value={f.faturamento_declarado} onChange={(e) => set('faturamento_declarado', e.target.value)} inputMode="numeric" placeholder="0" /></CampoEdit>
        <CampoEdit label="Documento (NF)"><Input value={f.documento_nf} onChange={(e) => set('documento_nf', e.target.value)} /></CampoEdit>
        <CampoEdit label="E-mail de entrega"><Input value={f.email_entrega} onChange={(e) => set('email_entrega', e.target.value)} /></CampoEdit>
        <CampoEdit label="CEP"><Input value={f.cep} onChange={(e) => set('cep', e.target.value)} /></CampoEdit>
        <CampoEdit label="Logradouro" full><Input value={f.logradouro} onChange={(e) => set('logradouro', e.target.value)} /></CampoEdit>
        <CampoEdit label="Número"><Input value={f.numero} onChange={(e) => set('numero', e.target.value)} /></CampoEdit>
        <CampoEdit label="Complemento"><Input value={f.complemento} onChange={(e) => set('complemento', e.target.value)} /></CampoEdit>
        <CampoEdit label="Bairro"><Input value={f.bairro} onChange={(e) => set('bairro', e.target.value)} /></CampoEdit>
        <CampoEdit label="Cidade"><Input value={f.cidade} onChange={(e) => set('cidade', e.target.value)} /></CampoEdit>
        <CampoEdit label="UF"><Input value={f.estado_uf} onChange={(e) => set('estado_uf', e.target.value.toUpperCase().slice(0, 2))} maxLength={2} /></CampoEdit>
      </div>
      <div className="flex gap-2 mt-4">
        <Button variant="primary" onClick={salvar}><Icon name="check" size={14} /> Salvar alterações</Button>
        <Button variant="ghost" onClick={onDone}>Cancelar</Button>
      </div>
    </div>
  );
}

/** Bloco de seção com cabeçalho de ícone (linguagem do card legado). */
function Panel({ icon, title, accent, children }: { icon?: string; title: string; accent?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4" style={accent ? { borderLeft: `3px solid ${accent}` } : undefined}>
      <div className="flex items-center gap-2 mb-3 text-[11px] font-bold uppercase tracking-wider text-[var(--fg-3)]">
        {icon && <Icon name={icon} size={14} className="text-[var(--accent)]" />} {title}
      </div>
      {children}
    </div>
  );
}

/** Botão de ação primária, grande e destacado (Próxima Ação). */
function BigAction({ children, onClick, variant = 'accent', icon }: { children: React.ReactNode; onClick: () => void; variant?: 'accent' | 'success'; icon?: string }) {
  return (
    <button onClick={onClick} className="w-full inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-3 text-sm font-bold text-black hover:brightness-110 transition-[filter]" style={{ background: variant === 'success' ? 'var(--green)' : 'var(--accent)' }}>
      {icon && <Icon name={icon} size={16} />}{children}
    </button>
  );
}

/** Cartão de documento (comprovante/declaração). */
function DocLink({ url, label }: { url: string | null; label: string }) {
  if (!url) {
    return <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border)] p-3 text-xs text-[var(--fg-4)]">{label}: —</div>;
  }
  return (
    <a href={url} target="_blank" rel="noopener" className="block rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 hover:border-[var(--border-strong)] transition-colors">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--green)] flex items-center gap-1.5"><Icon name="file" size={13} /> {label}</div>
      <div className="text-sm text-[var(--fg)] mt-1 inline-flex items-center gap-1.5"><Icon name="arrow-up-right" size={13} /> Abrir arquivo</div>
    </a>
  );
}

/** Linha rótulo-em-cima / valor (leitura densa nas seções). */
function Row2({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="py-1.5 border-b border-[var(--border-faint)]">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{k}</div>
      <div className="text-sm text-[var(--fg)] mt-0.5">{v || '—'}</div>
    </div>
  );
}

function fmtBRL(n: number | null): string {
  return n == null ? '—' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
}

function fmtDataExtenso(d: string): string {
  try {
    const [y, m, dd] = d.split('-').map(Number);
    return new Date(y, m - 1, dd).toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' });
  } catch {
    return d;
  }
}

// ── Aba Configurações (editável pelo admin, sem dev) ───────────────────────
function Area(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const { className = '', ...rest } = props;
  return <textarea {...rest} className={`w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)] placeholder:text-[var(--fg-4)] ${className}`} />;
}

function CfgLabel({ children }: { children: React.ReactNode }) {
  return <span className="block text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mb-1">{children}</span>;
}

function ConfigPanel({
  canEdit,
  cfg,
  onSaved,
  onBack,
  flash,
}: {
  canEdit: boolean;
  cfg: PlacasConfig | null;
  onSaved: (next: PlacasConfig) => void;
  onBack: () => void;
  flash: (m: string) => void;
}) {
  const base: PlacasConfig = cfg ?? { audit_steps: null, email_templates: {}, nivel_faixas: {}, form_textos: {} };

  const [sec, setSec] = useState<'emails' | 'etapas' | 'faixas' | 'form'>('emails');
  const [emails, setEmails] = useState<Record<string, EmailTemplateOverride>>(base.email_templates || {});
  const [etapas, setEtapas] = useState(() => auditStepsToEditable(resolveAuditSteps(base.audit_steps)));
  const [faixas, setFaixas] = useState<Record<string, NivelFaixa>>(() => {
    const m: Record<string, NivelFaixa> = {};
    for (const v of NIVEL_FAIXA_ORDER) m[v] = { ...DEFAULT_NIVEL_FAIXAS[v], ...(base.nivel_faixas?.[v] || {}) };
    return m;
  });
  const [textos, setTextos] = useState<{ upload_info: string; cadastro_info: string; espacos: EspacoOption[] }>(() => ({
    upload_info: base.form_textos?.upload_info || DEFAULT_FORM_TEXTOS.upload_info,
    cadastro_info: base.form_textos?.cadastro_info || DEFAULT_FORM_TEXTOS.cadastro_info,
    espacos: base.form_textos?.espacos?.length ? base.form_textos.espacos : DEFAULT_FORM_TEXTOS.espacos,
  }));
  const seeded = useRef(false);

  // Reseed quando a config termina de carregar (cfg null → carregado).
  useEffect(() => {
    if (!cfg || seeded.current) return;
    seeded.current = true;
    setEmails(cfg.email_templates || {});
    setEtapas(auditStepsToEditable(resolveAuditSteps(cfg.audit_steps)));
    const m: Record<string, NivelFaixa> = {};
    for (const v of NIVEL_FAIXA_ORDER) m[v] = { ...DEFAULT_NIVEL_FAIXAS[v], ...(cfg.nivel_faixas?.[v] || {}) };
    setFaixas(m);
    setTextos({
      upload_info: cfg.form_textos?.upload_info || DEFAULT_FORM_TEXTOS.upload_info,
      cadastro_info: cfg.form_textos?.cadastro_info || DEFAULT_FORM_TEXTOS.cadastro_info,
      espacos: cfg.form_textos?.espacos?.length ? cfg.form_textos.espacos : DEFAULT_FORM_TEXTOS.espacos,
    });
  }, [cfg]);

  const [busy, setBusy] = useState(false);
  async function persist(key: 'email_templates' | 'audit_steps' | 'nivel_faixas' | 'form_textos', value: unknown) {
    if (!canEdit) return;
    setBusy(true);
    const ok = await configData.savePlacasConfig(key, value);
    setBusy(false);
    if (!ok) { flash('Não foi possível salvar.'); return; }
    onSaved({ ...base, [key]: value } as PlacasConfig);
    flash('Configuração salva!');
  }

  const setEmail = (tipo: string, campo: keyof EmailTemplateOverride, v: string) =>
    setEmails((p) => ({ ...p, [tipo]: { ...p[tipo], [campo]: v } }));
  const setEtapa = (i: number, campo: 'name' | 'desc' | 'actionLabel', v: string) =>
    setEtapas((p) => p.map((e, idx) => (idx === i ? { ...e, [campo]: v } : e)));
  const setFaixa = (v: string, campo: keyof NivelFaixa, val: string) =>
    setFaixas((p) => ({ ...p, [v]: { ...p[v], [campo]: val } }));

  const SECOES: { k: typeof sec; label: string; icon: string }[] = [
    { k: 'emails', label: 'E-mails automáticos', icon: 'mail' },
    { k: 'etapas', label: 'Etapas da auditoria', icon: 'check-circle' },
    { k: 'faixas', label: 'Faixas de faturamento', icon: 'coins' },
    { k: 'form', label: 'Textos do formulário', icon: 'clipboard' },
  ];

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">Configurações de <span className="text-[var(--accent)]">Placas</span></h1>
        <button onClick={onBack} className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"><Icon name="arrow-left" size={14} /> Voltar às solicitações</button>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">Ajuste textos, etapas, e-mails e faixas sem depender de um desenvolvedor. Campos em branco usam o texto padrão.</p>

      {!canEdit && <div className="rounded-[var(--r-md)] bg-[var(--surface-3)] p-3 text-sm text-[var(--fg-3)] mb-4">Somente leitura — você não tem permissão para editar.</div>}

      <div className="flex gap-1 border-b border-[var(--border)] mb-4 overflow-x-auto">
        {SECOES.map((s) => (
          <button key={s.k} onClick={() => setSec(s.k)} className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 -mb-px transition-colors inline-flex items-center gap-2 ${sec === s.k ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'}`}>
            <Icon name={s.icon} size={14} /> {s.label}
          </button>
        ))}
      </div>

      {sec === 'emails' && (
        <div className="space-y-4">
          {EMAIL_TIPOS_CONFIG.map((t) => (
            <Card key={t.tipo} className="p-4">
              <div className="font-semibold text-[var(--fg)]">{t.label}</div>
              <div className="text-xs text-[var(--fg-3)] mb-3">{t.descricao}</div>
              <div className="space-y-2">
                <div><CfgLabel>Assunto</CfgLabel><Input value={emails[t.tipo]?.assunto ?? ''} onChange={(e) => setEmail(t.tipo, 'assunto', e.target.value)} placeholder="(padrão do sistema)" disabled={!canEdit} /></div>
                <div><CfgLabel>Introdução</CfgLabel><Area rows={2} value={emails[t.tipo]?.introducao ?? ''} onChange={(e) => setEmail(t.tipo, 'introducao', e.target.value)} placeholder="(padrão do sistema)" disabled={!canEdit} /></div>
                <div><CfgLabel>Corpo (aceita HTML)</CfgLabel><Area rows={3} value={emails[t.tipo]?.corpo_extra ?? ''} onChange={(e) => setEmail(t.tipo, 'corpo_extra', e.target.value)} placeholder="(padrão do sistema)" disabled={!canEdit} /></div>
              </div>
            </Card>
          ))}
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('email_templates', emails)}><Icon name="check" size={14} /> Salvar e-mails</Button>}
        </div>
      )}

      {sec === 'etapas' && (
        <div className="space-y-3">
          {etapas.map((e, i) => (
            <Card key={i} className="p-4">
              <div className="text-[11px] font-bold uppercase tracking-wide text-[var(--accent)] mb-2">Etapa {i + 1}</div>
              <div className="grid sm:grid-cols-2 gap-2">
                <div><CfgLabel>Nome</CfgLabel><Input value={e.name ?? ''} onChange={(ev) => setEtapa(i, 'name', ev.target.value)} disabled={!canEdit} /></div>
                <div><CfgLabel>Rótulo do botão de avanço</CfgLabel><Input value={e.actionLabel ?? ''} onChange={(ev) => setEtapa(i, 'actionLabel', ev.target.value)} disabled={!canEdit} /></div>
                <div className="sm:col-span-2"><CfgLabel>Descrição</CfgLabel><Area rows={2} value={e.desc ?? ''} onChange={(ev) => setEtapa(i, 'desc', ev.target.value)} disabled={!canEdit} /></div>
              </div>
            </Card>
          ))}
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('audit_steps', etapas)}><Icon name="check" size={14} /> Salvar etapas</Button>}
        </div>
      )}

      {sec === 'faixas' && (
        <div className="space-y-3">
          <Card className="p-4">
            <div className="grid gap-2">
              {NIVEL_FAIXA_ORDER.map((v) => (
                <div key={v} className="grid sm:grid-cols-[1fr_2fr] gap-2 items-center">
                  <Input value={faixas[v]?.nm ?? ''} onChange={(e) => setFaixa(v, 'nm', e.target.value)} placeholder="Nome do nível" disabled={!canEdit} />
                  <Input value={faixas[v]?.fx ?? ''} onChange={(e) => setFaixa(v, 'fx', e.target.value)} placeholder="Faixa (ex.: R$ 500k em 12 meses)" disabled={!canEdit} />
                </div>
              ))}
            </div>
          </Card>
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('nivel_faixas', faixas)}><Icon name="check" size={14} /> Salvar faixas</Button>}
        </div>
      )}

      {sec === 'form' && (
        <div className="space-y-3">
          <Card className="p-4 space-y-3">
            <div><CfgLabel>Instrução de upload (comprovação)</CfgLabel><Area rows={2} value={textos.upload_info} onChange={(e) => setTextos((p) => ({ ...p, upload_info: e.target.value }))} disabled={!canEdit} /></div>
            <div><CfgLabel>Aviso de cadastro (nível não elegível)</CfgLabel><Area rows={2} value={textos.cadastro_info} onChange={(e) => setTextos((p) => ({ ...p, cadastro_info: e.target.value }))} disabled={!canEdit} /></div>
          </Card>
          <Card className="p-4">
            <div className="flex items-center justify-between mb-2">
              <CfgLabel>Espaços de instrução</CfgLabel>
              {canEdit && <button onClick={() => setTextos((p) => ({ ...p, espacos: [...p.espacos, { v: '', l: '' }] }))} className="text-xs font-semibold text-[var(--accent)] inline-flex items-center gap-1"><Icon name="plus" size={13} /> Adicionar</button>}
            </div>
            <div className="space-y-2">
              {textos.espacos.map((o, i) => (
                <div key={i} className="grid grid-cols-[1fr_1.4fr_auto] gap-2 items-center">
                  <Input value={o.v} onChange={(e) => setTextos((p) => ({ ...p, espacos: p.espacos.map((x, idx) => idx === i ? { ...x, v: e.target.value } : x) }))} placeholder="chave" disabled={!canEdit} />
                  <Input value={o.l} onChange={(e) => setTextos((p) => ({ ...p, espacos: p.espacos.map((x, idx) => idx === i ? { ...x, l: e.target.value } : x) }))} placeholder="Rótulo exibido" disabled={!canEdit} />
                  {canEdit && <button onClick={() => setTextos((p) => ({ ...p, espacos: p.espacos.filter((_, idx) => idx !== i) }))} className="text-[var(--red)] p-1.5" title="Remover"><Icon name="x" size={14} /></button>}
                </div>
              ))}
            </div>
          </Card>
          {canEdit && <Button variant="primary" disabled={busy} onClick={() => persist('form_textos', { upload_info: textos.upload_info, cadastro_info: textos.cadastro_info, espacos: textos.espacos.filter((e) => e.v && e.l) })}><Icon name="check" size={14} /> Salvar textos</Button>}
        </div>
      )}
    </div>
  );
}

interface Agendamento { data: string; hora: string; nome: string | null; email: string | null }

function AgendaHorarios({ canEdit, flash, agendamentos }: { canEdit: boolean; flash: (m: string) => void; agendamentos: Agendamento[] }) {
  const [slots, setSlots] = useState<HorarioSlot[]>([]);
  const [novaData, setNovaData] = useState('');
  const [novaHora, setNovaHora] = useState('');
  const [excluirId, setExcluirId] = useState<number | null>(null);

  const reload = useCallback(async () => setSlots(await data.loadHorarios()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);

  // Agenda combinada: por data → horários (slot disponível e/ou agendamento).
  const agenda = useMemo(() => {
    const byDate = new Map<string, Map<string, { slot?: HorarioSlot; ag?: Agendamento }>>();
    const cell = (d: string, h: string) => {
      if (!byDate.has(d)) byDate.set(d, new Map());
      const md = byDate.get(d)!;
      if (!md.has(h)) md.set(h, {});
      return md.get(h)!;
    };
    for (const s of slots) cell(s.slot_data, String(s.hora).slice(0, 5)).slot = s;
    for (const a of agendamentos) cell(a.data, a.hora).ag = a;
    return Array.from(byDate.entries())
      .sort((x, y) => x[0].localeCompare(y[0]))
      .map(([d, horas]) => ({
        data: d,
        itens: Array.from(horas.entries()).sort((x, y) => x[0].localeCompare(y[0])).map(([hora, v]) => ({ hora, slot: v.slot, ag: v.ag })),
      }));
  }, [slots, agendamentos]);

  return (
    <div>
      {canEdit && (
        <div className="flex flex-wrap gap-2 mb-4 items-end rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Data</label><Input type="date" value={novaData} onChange={(e) => setNovaData(e.target.value)} className="w-auto" /></div>
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Hora</label><Input type="time" value={novaHora} onChange={(e) => setNovaHora(e.target.value)} className="w-auto" /></div>
          <Button onClick={async () => { if (novaData && novaHora && (await data.criarHorario(novaData, novaHora))) { flash('Horário criado.'); setNovaHora(''); reload(); } }}><Icon name="plus" size={14} /> Adicionar slot</Button>
          <span className="ml-auto flex items-center gap-3 text-[11px] text-[var(--fg-3)] self-center">
            <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--green)' }} /> Disponível</span>
            <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--accent)' }} /> Agendado</span>
            <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--fg-4)' }} /> Inativo</span>
          </span>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {agenda.map(({ data: d, itens }) => (
          <div key={d} className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] overflow-hidden">
            <div className="px-3 py-2 border-b border-[var(--border)] bg-[var(--surface-3)] text-sm font-semibold text-[var(--fg)] capitalize flex items-center gap-2">
              <Icon name="calendar" size={14} className="text-[var(--accent)]" /> {fmtDataExtenso(d)}
            </div>
            <div className="divide-y divide-[var(--border-faint)]">
              {itens.map((it) => {
                const booked = !!it.ag;
                const inativo = !!it.slot && !it.slot.ativo;
                const cor = booked ? 'var(--accent)' : inativo ? 'var(--fg-4)' : 'var(--green)';
                return (
                  <div key={it.hora} className="flex items-center gap-2 px-3 py-2">
                    <span className="w-2 h-2 rounded-full shrink-0" style={{ background: cor }} />
                    <span className={`text-sm tabular font-medium ${inativo ? 'text-[var(--fg-3)] line-through' : 'text-[var(--fg)]'}`}>{it.hora}</span>
                    <span className="text-xs flex-1 min-w-0 truncate">
                      {booked ? <span className="text-[var(--accent)] font-medium" title={it.ag!.email || ''}>{it.ag!.nome || 'Agendado'}</span> : inativo ? <span className="text-[var(--fg-3)]">Inativo</span> : <span className="text-[var(--green)]">Disponível</span>}
                      {booked && !it.slot && <span className="ml-1 text-[10px] text-[var(--yellow)]" title="Agendamento sem slot correspondente">· sem slot</span>}
                    </span>
                    {canEdit && it.slot && (
                      <>
                        <button onClick={async () => { if (await data.toggleHorario(it.slot!.id, !it.slot!.ativo)) reload(); }} className="text-[var(--fg-3)] hover:text-[var(--fg)] inline-flex" title={it.slot.ativo ? 'Desativar' : 'Ativar'}><Icon name={it.slot.ativo ? 'pause' : 'play'} size={13} /></button>
                        <button onClick={() => setExcluirId(it.slot!.id)} className="text-[var(--red)] inline-flex" title="Excluir"><Icon name="x" size={13} /></button>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
      {!agenda.length && <p className="text-[var(--fg-3)] text-sm">Nenhum horário cadastrado.</p>}
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
