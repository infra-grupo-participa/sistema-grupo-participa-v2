'use client';

import { memo, useCallback, useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { AUDIT_STEP_TOTAL } from '../../domain/auditoria';
import {
  computeDisplayStatus,
  displayStatusTone,
  getSolicitacaoBucketMatch,
  getSolicitacaoQueuePriority,
  isSolicitacaoSeen,
  isSolicitacaoRegularizacao,
  type SolicitacaoBucket,
} from '../../domain/solicitacao';
import type { Solicitacao, Auditoria } from '../../domain/types';
import * as data from './placas-admin-data';
import * as configData from './placas-config-data';
import { resolveAuditSteps, resolveFormTextos, NIVEL_FAIXA_ORDER, DEFAULT_NIVEL_FAIXAS, type PlacasConfig } from '../../domain/config';
import { Badge, NivelBadge, DataTable, Thead, Th, Tr, Td, EmptyState, MultiSelect, SearchInput, ProgressBar, SkeletonRows, Toast, Toolbar, useFlash, Button } from '@/shared/ui/components';
import { SolicitacaoDrawer } from './SolicitacaoDrawer';
import { ConfigPanel } from './ConfigPanel';
import { AgendaHorarios } from './AgendaHorarios';
import { fmtRelativo } from './relatorio-shared';
import { exportarExcelPlacas } from './placas-export';

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
  // Rótulos dos espaços de instrução (config sobrepõe o default) — valor cru como fallback.
  const espacoMap = useMemo(() => {
    const m: Record<string, string> = {};
    for (const e of resolveFormTextos(cfg?.form_textos).espacos) m[e.v] = e.l;
    return m;
  }, [cfg]);
  const espacoNome = useCallback((v: string | null | undefined) => (v ? espacoMap[v] || v : ''), [espacoMap]);

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

  // Filtros dedicados (porta dos 5 selects do legado) + ordenação clicável.
  const FILTROS_VAZIO = { nivel: [] as string[], turma: [] as string[], uf: [] as string[], status: [] as string[] };
  const [filtros, setFiltros] = useState(FILTROS_VAZIO);
  type SortCol = 'nome' | 'espaco' | 'nivel' | 'status' | 'turma' | 'quando';
  const [sortCol, setSortCol] = useState<SortCol | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const sortBtn = (col: SortCol) => () => {
    if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortCol(col); setSortDir('asc'); }
  };
  const turmaOpts = useMemo(() => Array.from(new Set(sols.map((s) => s.turma).filter(Boolean) as string[])).sort((a, b) => b.localeCompare(a, 'pt-BR', { numeric: true })), [sols]);
  const ufOpts = useMemo(() => Array.from(new Set(sols.map((s) => String(s.estado_uf ?? '').toUpperCase()).filter(Boolean))).sort(), [sols]);
  const statusOpts = useMemo(() => Array.from(new Set(sols.map((s) => computeDisplayStatus(s).label))).sort(), [sols]);
  const temFiltro = Object.values(filtros).some((a) => a.length > 0);

  // Busca adiada: digitar não trava a renderização da tabela.
  const dq = useDeferredValue(q);
  const filtered = useMemo(() => {
    const term = dq.trim().toLowerCase();
    const nivelRank = (n: string | null | undefined) => { const i = (NIVEL_FAIXA_ORDER as readonly string[]).indexOf(String(n ?? '')); return i === -1 ? 99 : i; };
    return sols
      .filter((s) => getSolicitacaoBucketMatch(s, bucket))
      .filter((s) => !term || `${s.nome ?? ''} ${s.email ?? ''} ${s.documento_nf ?? ''} ${s.cidade ?? ''} ${s.estado_uf ?? ''} ${s.turma ?? ''} ${espacoNome(s.espaco_instrucao)}`.toLowerCase().includes(term))
      .filter((s) => !filtros.nivel.length || filtros.nivel.includes(String(s.nivel ?? '')))
      .filter((s) => !filtros.turma.length || filtros.turma.includes(String(s.turma ?? '')))
      .filter((s) => !filtros.uf.length || filtros.uf.includes(String(s.estado_uf ?? '').toUpperCase()))
      .filter((s) => !filtros.status.length || filtros.status.includes(computeDisplayStatus(s).label))
      .sort((a, b) => {
        if (sortCol) {
          const dir = sortDir === 'asc' ? 1 : -1;
          if (sortCol === 'nome') return dir * String(a.nome ?? '').localeCompare(String(b.nome ?? ''), 'pt-BR');
          if (sortCol === 'espaco') return dir * espacoNome(a.espaco_instrucao).localeCompare(espacoNome(b.espaco_instrucao), 'pt-BR');
          if (sortCol === 'nivel') return dir * (nivelRank(a.nivel) - nivelRank(b.nivel));
          if (sortCol === 'status') return dir * computeDisplayStatus(a).label.localeCompare(computeDisplayStatus(b).label, 'pt-BR');
          if (sortCol === 'turma') return dir * String(a.turma ?? '').localeCompare(String(b.turma ?? ''), 'pt-BR', { numeric: true });
          return dir * String(a.updated_at ?? '').localeCompare(String(b.updated_at ?? ''));
        }
        // Não-vistos (ação nova do aluno) sempre no topo — estilo caixa de WhatsApp.
        const sa = isSolicitacaoSeen(a) ? 1 : 0;
        const sb = isSolicitacaoSeen(b) ? 1 : 0;
        if (sa !== sb) return sa - sb;
        return getSolicitacaoQueuePriority(a) - getSolicitacaoQueuePriority(b);
      });
  }, [sols, bucket, dq, filtros, sortCol, sortDir, espacoNome]);

  const open = openId ? sols.find((s) => s.id === openId) ?? null : null;
  // Abrir = visto automático (estilo WhatsApp): otimista no estado local + persistência
  // em segundo plano. O "Não visto" do drawer continua disponível para re-marcar.
  const abrir = useCallback(
    (id: string) => {
      setOpenId(id);
      const s = sols.find((x) => x.id === id);
      if (!canEdit || !s || isSolicitacaoSeen(s)) return;
      setSols((prev) => prev.map((x) => (x.id === id ? { ...x, admin_seen_at: new Date().toISOString() } : x)));
      void data.marcarVisto(s, true);
    },
    [sols, canEdit],
  );

  const [exportando, setExportando] = useState(false);
  const exportar = useCallback(async () => {
    setExportando(true);
    try {
      // Exporta exatamente o recorte visível (gaveta + filtros + busca), como o legado —
      // a elegibilidade (entrevista finalizada+) é aplicada dentro de exportarExcelPlacas.
      const n = await exportarExcelPlacas(filtered);
      flash(n ? `${n} ${n === 1 ? 'solicitação exportada' : 'solicitações exportadas'}.` : 'Nenhum registro elegível para exportar (entrevista finalizada em diante).');
    } catch {
      flash('Não foi possível gerar a planilha.');
    } finally {
      setExportando(false);
    }
  }, [filtered, flash]);
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
                onClick={exportar}
                disabled={exportando}
                title="Exportar solicitações elegíveis (.xlsx)"
                className="inline-flex items-center justify-center gap-1.5 rounded-[var(--r-md)] px-3 py-1.5 text-xs font-semibold bg-transparent border transition-colors text-[var(--fg-2)] border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] disabled:opacity-50"
              >
                <Icon name="download" size={14} /> {exportando ? 'Gerando…' : 'Exportar Excel'}
              </button>
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
                badge={b.key === 'processo' && counts.naoVistos > 0 ? `${counts.naoVistos} ação do aluno` : undefined}
                onClick={() => setBucket(b.key)}
              />
            ))}
          </div>

          {/* Busca + filtros dedicados */}
          <Toolbar className="mb-3">
            <SearchInput value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar nome, e-mail, documento, cidade, UF, turma…" />
            <MultiSelect values={filtros.nivel} onChange={(v) => setFiltros((f) => ({ ...f, nivel: v }))} placeholder="Todos os níveis" options={NIVEL_FAIXA_ORDER.map((n) => ({ value: n, label: DEFAULT_NIVEL_FAIXAS[n].nm }))} />
            <MultiSelect values={filtros.turma} onChange={(v) => setFiltros((f) => ({ ...f, turma: v }))} placeholder="Todas as turmas" options={turmaOpts.map((t) => ({ value: t, label: t }))} />
            <MultiSelect values={filtros.uf} onChange={(v) => setFiltros((f) => ({ ...f, uf: v }))} placeholder="Todas as UFs" options={ufOpts.map((u) => ({ value: u, label: u }))} />
            <MultiSelect values={filtros.status} onChange={(v) => setFiltros((f) => ({ ...f, status: v }))} placeholder="Todos os status" options={statusOpts.map((s) => ({ value: s, label: s }))} />
            {(temFiltro || dq.trim()) && (
              <>
                <Button variant="ghost" size="sm" onClick={() => { setFiltros(FILTROS_VAZIO); setQ(''); }}>Limpar</Button>
                <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{filtered.length} {filtered.length === 1 ? 'resultado' : 'resultados'}</span>
              </>
            )}
          </Toolbar>

          {/* Layout fixo: larguras definidas aqui; células truncam em vez de forçar scroll lateral. */}
          <DataTable fixed>
            <Thead>
              <Th sortable active={sortCol === 'nome'} dir={sortDir} onClick={sortBtn('nome')}>Aluno</Th>
              <Th sortable active={sortCol === 'espaco'} dir={sortDir} onClick={sortBtn('espaco')} className="w-[170px]">Espaço de Instrução</Th>
              <Th sortable active={sortCol === 'nivel'} dir={sortDir} onClick={sortBtn('nivel')} className="w-[130px]">Nível</Th>
              <Th sortable active={sortCol === 'status'} dir={sortDir} onClick={sortBtn('status')} className="w-[190px]">Status</Th>
              <Th className="w-[105px]">Progresso</Th>
              <Th sortable active={sortCol === 'turma'} dir={sortDir} onClick={sortBtn('turma')} className="w-[70px]">Turma</Th>
              <Th sortable active={sortCol === 'quando'} dir={sortDir} onClick={sortBtn('quando')} className="w-[100px]">Atualizado</Th>
            </Thead>
            <tbody>
              {loading && !sols.length
                ? <SkeletonRows cols={[96, 64, 80, 96, 40, 56]} />
                : filtered.map((s) => <LinhaSolicitacao key={s.id} s={s} espaco={espacoNome(s.espaco_instrucao)} onOpen={abrir} />)}
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
const LinhaSolicitacao = memo(function LinhaSolicitacao({ s, espaco, onOpen }: { s: Solicitacao; espaco: string; onOpen: (id: string) => void }) {
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
            {!seen && <span className="absolute -top-0.5 -right-0.5 w-3 h-3 rounded-full bg-[var(--accent)] ring-2 ring-[var(--surface-2)] animate-pulse" title="Ação nova do aluno" />}
          </span>
          <div className="min-w-0">
            <div className={`truncate flex items-center gap-1.5 ${!seen ? 'text-[var(--fg)] font-bold' : 'text-[var(--fg)] font-medium'}`}>
              {s.nome || '—'}
              {!seen && <span className="shrink-0 text-[10px] font-bold uppercase tracking-wide rounded-[var(--r-pill)] bg-[var(--accent)] text-black px-1.5 py-px">Novo</span>}
              {s.central_match === 'nenhum' && <span title="Sem registro na central — possível ex-aluno" className="shrink-0 text-[10px] font-bold uppercase tracking-wide rounded-[var(--r-pill)] bg-[var(--red-subtle)] text-[var(--red)] px-1.5 py-px">NÃO ALUNO?</span>}
            </div>
            <div className={`text-xs truncate ${!seen ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>{s.email}</div>
          </div>
        </div>
      </Td>
      <Td className="overflow-hidden">
        {espaco ? <span className="block truncate text-xs text-[var(--fg-2)]" title={espaco}>{espaco}</span> : <span className="text-[var(--fg-3)]">—</span>}
      </Td>
      <Td className="overflow-hidden"><NivelBadge nivel={s.nivel} /></Td>
      <Td className="overflow-hidden"><span title={ds.label}><Badge tone={displayStatusTone(ds.cls)} dot>{ds.label}</Badge></span></Td>
      <Td>
        <div className="flex items-center gap-2">
          <div className="flex-1"><ProgressBar value={pr.pct * 100} height={6} tone={pr.tone} /></div>
          <span className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap">{pr.label}</span>
        </div>
      </Td>
      <Td>{s.turma ? <span className="text-xs font-semibold rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)] px-2 py-0.5">{s.turma}</span> : <span className="text-[var(--fg-3)]">—</span>}</Td>
      <Td className="text-xs text-[var(--fg-3)] tabular whitespace-nowrap"><span title={quando.title}>{quando.label}</span></Td>
    </Tr>
  );
});
