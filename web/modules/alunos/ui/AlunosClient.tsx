'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  type Aluno360,
  ESPACO_LABEL,
  NRANK,
  SITUACAO,
  RENOVACAO_LABEL,
  renovacaoStatus,
  searchHaystack,
} from '../domain/aluno-360';
import { nivelLabel, nivelOptions } from '@/shared/domain/nivel-resultado';
import { loadAlunos360, loadTurmas, loadPlacaHistorico, updateAluno, type Turma, type PlacaHistorico } from './alunos-data';
import { AUDIT_STEPS } from '@/modules/placas/domain/auditoria';
import { cursoDesempenhoMock } from '../domain/curso-mock';
import { Badge, NivelBadge, DataTable, Thead, Th as Thx, Tr, Td, EmptyState, Drawer, Tabs, Button } from '@/shared/ui/components';
import { DashboardAlunos } from './DashboardAlunos';

type SortCol = 'nome' | 'nivel' | 'instrucao' | 'turma' | 'vencimento';
interface Filtros { situacao: string; espaco: string; nivel: string; jornada: string; papel: string }

const money = (v: number | null) =>
  v == null ? '—' : Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const dataBR = (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : '—');
const tel = (v: string | null) => v || '—';

type Tone = 'success' | 'danger' | 'warning' | 'neutral' | 'info' | 'accent';
const sitTone = (cls: string): Tone => (cls === 'green' ? 'success' : cls === 'red' ? 'danger' : cls === 'yellow' ? 'warning' : 'neutral');

/** Turma THB + Aurum num só texto (HM e Aurum). */
const turmaCombo = (a: Aluno360) => [a.turma_codigo, a.turma_aurum_codigo].filter(Boolean).join(' · ');

function EspacoBadge({ espaco }: { espaco: string }) {
  const label = ESPACO_LABEL[espaco];
  if (!label) return <span className="text-[var(--fg-2)]">{espaco}</span>;
  return <Badge tone="info">{label}</Badge>;
}

/** Texto com botão de copiar — não propaga o clique para a linha. */
function CopyText({ value, display }: { value: string; display?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard?.writeText(value).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1200); });
      }}
      title="Copiar"
      className="group inline-flex items-center gap-1 text-xs text-[var(--fg-3)] hover:text-[var(--accent)] transition-colors max-w-full"
    >
      <span className="truncate">{display || value}</span>
      <span className="opacity-0 group-hover:opacity-100 transition-opacity shrink-0">{copied ? '✓' : '⧉'}</span>
    </button>
  );
}

export function AlunosClient({ canEdit }: { canEdit: boolean }) {
  const [alunos, setAlunos] = useState<Aluno360[]>([]);
  const [turmas, setTurmas] = useState<Turma[]>([]);
  const [loading, setLoading] = useState(true);
  const [busca, setBusca] = useState('');
  const [filtros, setFiltros] = useState<Filtros>({ situacao: '', espaco: '', nivel: '', jornada: '', papel: '' });
  const [sortCol, setSortCol] = useState<SortCol>('nome');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [editMode, setEditMode] = useState(false);
  const [toast, setToast] = useState('');
  const [topTab, setTopTab] = useState<'dashboard' | 'lista'>('dashboard');

  const reload = useCallback(async () => setAlunos(await loadAlunos360()), []);
  useEffect(() => {
    (async () => {
      const [a, t] = await Promise.all([loadAlunos360(), loadTurmas()]);
      setAlunos(a);
      setTurmas(t);
      setLoading(false);
    })();
  }, []);

  function flash(m: string) {
    setToast(m);
    setTimeout(() => setToast(''), 3000);
  }

  const filtered = useMemo(() => {
    const tokens = busca.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const f = filtros;
    const list = alunos.filter((a) => {
      if (tokens.length) {
        const hay = searchHaystack(a);
        if (!tokens.every((t) => hay.includes(t))) return false;
      }
      if (f.situacao === 'inadimplente') {
        if (!(Number(a.saldo_devedor) > 0)) return false;
      } else if (f.situacao && a.situacao_acesso !== f.situacao) return false;
      if (f.espaco && (a.espaco_instrucao || '') !== f.espaco) return false;
      if (f.nivel && a.nivel_resultado !== f.nivel) return false;
      if (f.papel === 'socio' && !a.eh_socio) return false;
      if (f.papel === 'titular' && a.eh_socio) return false;
      if (f.papel === 'aurum' && a.turma_aurum_id == null) return false;
      if (f.jornada === 'com_ht' && !a.tem_ht) return false;
      if (f.jornada === 'com_hm' && !a.tem_hm) return false;
      if (f.jornada === 'com_placa' && !a.tem_placa) return false;
      if (f.jornada === 'com_depoimento' && !a.tem_depoimento) return false;
      return true;
    });
    list.sort((a, b) => {
      if (sortCol === 'nivel') {
        const ra = a.nivel_resultado ? NRANK[a.nivel_resultado] ?? -1 : -2;
        const rb = b.nivel_resultado ? NRANK[b.nivel_resultado] ?? -1 : -2;
        if (ra !== rb) return sortDir === 'asc' ? ra - rb : rb - ra;
        return (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      }
      if (sortCol === 'instrucao') {
        const cmp = (ESPACO_LABEL[a.espaco_instrucao || ''] || '￿').localeCompare(ESPACO_LABEL[b.espaco_instrucao || ''] || '￿', 'pt-BR');
        return sortDir === 'asc' ? cmp : -cmp;
      }
      if (sortCol === 'turma') {
        const cmp = (turmaCombo(a) || '￿').localeCompare(turmaCombo(b) || '￿', 'pt-BR', { numeric: true });
        return sortDir === 'asc' ? cmp : -cmp;
      }
      if (sortCol === 'vencimento') {
        const ra = a.data_expiracao ? Date.parse(a.data_expiracao) : Infinity;
        const rb = b.data_expiracao ? Date.parse(b.data_expiracao) : Infinity;
        if (ra !== rb) return sortDir === 'asc' ? ra - rb : rb - ra;
        return (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      }
      const cmp = (a.nome || '').localeCompare(b.nome || '', 'pt-BR');
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return list;
  }, [alunos, busca, filtros, sortCol, sortDir]);

  const selected = selectedId ? alunos.find((a) => a.id === selectedId) ?? null : null;
  const sortBtn = (col: SortCol) => () => {
    if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    else { setSortCol(col); setSortDir('asc'); }
  };

  return (
    <div>
      <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Base de Alunos</h1>
      <p className="text-sm text-[var(--fg-3)] mb-4">Centro de controle — ficha 360° do aluno. {loading && 'carregando…'}</p>

      <div className="flex gap-1 border-b border-[var(--border)] mb-5">
        {([['dashboard', 'Dashboard'], ['lista', 'Lista de alunos']] as const).map(([k, l]) => (
          <button
            key={k}
            onClick={() => setTopTab(k)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
              topTab === k ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'
            }`}
          >
            {l}
          </button>
        ))}
      </div>

      {topTab === 'dashboard' && <DashboardAlunos alunos={alunos} />}

      {topTab === 'lista' && (
      <>
      <div className="flex flex-wrap gap-2 mb-3">
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome, e-mail, documento, cidade…" className="flex-1 min-w-[220px] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]" />
        <Sel value={filtros.nivel} onChange={(v) => setFiltros((f) => ({ ...f, nivel: v }))} placeholder="Todos os níveis" options={nivelOptions().map((n) => ({ value: n.id, label: n.label }))} />
        <Sel value={filtros.espaco} onChange={(v) => setFiltros((f) => ({ ...f, espaco: v }))} placeholder="Todos os espaços" options={Object.entries(ESPACO_LABEL).map(([k, l]) => ({ value: k, label: l }))} />
        <Sel value={filtros.jornada} onChange={(v) => setFiltros((f) => ({ ...f, jornada: v }))} placeholder="Toda jornada" options={[{ value: 'com_ht', label: 'Com HT' }, { value: 'com_hm', label: 'Com HM' }, { value: 'com_placa', label: 'Com placa' }, { value: 'com_depoimento', label: 'Com depoimento' }]} />
        <Sel value={filtros.situacao} onChange={(v) => setFiltros((f) => ({ ...f, situacao: v }))} placeholder="Toda situação" options={[...Object.entries(SITUACAO).map(([k, s]) => ({ value: k, label: s.label })), { value: 'inadimplente', label: 'Inadimplente' }]} />
      </div>

      <DataTable>
        <Thead>
          <Thx sortable active={sortCol === 'nome'} dir={sortDir} onClick={sortBtn('nome')}>Aluno</Thx>
          <Thx sortable active={sortCol === 'nivel'} dir={sortDir} onClick={sortBtn('nivel')}>Nível</Thx>
          <Thx>Profissão</Thx>
          <Thx sortable active={sortCol === 'instrucao'} dir={sortDir} onClick={sortBtn('instrucao')}>Espaço</Thx>
          <Thx sortable active={sortCol === 'turma'} dir={sortDir} onClick={sortBtn('turma')}>Turma</Thx>
          <Thx sortable active={sortCol === 'vencimento'} dir={sortDir} onClick={sortBtn('vencimento')}>Vencimento</Thx>
        </Thead>
        <tbody>
          {filtered.slice(0, 500).map((a) => {
            const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
            return (
              <Tr key={a.id} onClick={() => { setSelectedId(a.id); setEditMode(false); }}>
                <Td>
                  <div className="text-[var(--fg)] font-medium">{a.nome || '—'}</div>
                  <div className="flex flex-col gap-0.5 mt-0.5">
                    {a.email && <CopyText value={a.email} />}
                    {a.telefone && <CopyText value={a.telefone} display={tel(a.telefone)} />}
                  </div>
                </Td>
                <Td><NivelBadge nivel={a.nivel_resultado} /></Td>
                <Td className="text-[var(--fg-2)]">{a.profissao || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td>{a.espaco_instrucao ? <EspacoBadge espaco={a.espaco_instrucao} /> : <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="text-[var(--fg-2)] whitespace-nowrap">{turmaCombo(a) || <span className="text-[var(--fg-3)]">—</span>}</Td>
                <Td className="whitespace-nowrap">
                  {a.data_expiracao
                    ? <div><span className="text-[var(--fg-2)]">{dataBR(a.data_expiracao)}</span>{sit && <div className="mt-0.5"><Badge tone={sitTone(sit.cls)} dot>{sit.label}</Badge></div>}</div>
                    : <span className="text-[var(--fg-3)]">—</span>}
                </Td>
              </Tr>
            );
          })}
        </tbody>
      </DataTable>
      {!filtered.length && !loading && <EmptyState title="Nenhum aluno encontrado" hint="Ajuste a busca ou os filtros." icon="👥" />}
      {filtered.length > 500 && <p className="text-xs text-[var(--fg-3)] mt-2">Exibindo 500 de {filtered.length}. Refine a busca.</p>}
      </>
      )}

      {selected && (
        <Drawer360
          a={selected}
          turmas={turmas}
          canEdit={canEdit}
          editMode={editMode}
          onToggleEdit={() => setEditMode((e) => !e)}
          onClose={() => { setSelectedId(null); setEditMode(false); }}
          onSaved={async (msg) => { flash(msg); setEditMode(false); await reload(); }}
        />
      )}
      {toast && <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-[var(--surface-4)] text-[var(--fg)] px-4 py-2 rounded-[var(--r-md)] shadow-[var(--shadow-lg)] text-sm z-[1100]">{toast}</div>}
    </div>
  );
}

function Sel({ value, onChange, placeholder, options }: { value: string; onChange: (v: string) => void; placeholder: string; options: { value: string; label: string }[] }) {
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
      <option value="">{placeholder}</option>
      {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  );
}

// ── Drawer 360 ──
const TABS = [
  { k: 'geral', l: 'Geral' },
  { k: 'acesso', l: 'Acesso' },
  { k: 'curso', l: 'Curso' },
  { k: 'renovacao', l: 'Renovação' },
  { k: 'financeiro', l: 'Financeiro' },
  { k: 'jornada', l: 'Jornada' },
];

function Drawer360({ a, turmas, canEdit, editMode, onToggleEdit, onClose, onSaved }: {
  a: Aluno360;
  turmas: Turma[];
  canEdit: boolean;
  editMode: boolean;
  onToggleEdit: () => void;
  onClose: () => void;
  onSaved: (msg: string) => void;
}) {
  const [tab, setTab] = useState('geral');
  const [placaHist, setPlacaHist] = useState<PlacaHistorico | null>(null);
  const [placaLoading, setPlacaLoading] = useState(false);
  const temPlaca = !!(a.tem_placa || a.tem_solicitacao_placa);
  useEffect(() => {
    if (tab !== 'jornada' || !temPlaca || placaHist !== null) return;
    setPlacaLoading(true); // eslint-disable-line react-hooks/set-state-in-effect
    loadPlacaHistorico(a.id, a.email)
      .then(setPlacaHist)
      .finally(() => setPlacaLoading(false));
  }, [tab, temPlaca, placaHist, a.id, a.email]);
  const saldo = Number(a.saldo_devedor) || 0;
  const sit = a.situacao_acesso ? SITUACAO[a.situacao_acesso] : null;
  const espaco = ESPACO_LABEL[a.espaco_instrucao || ''] || null;
  const sitTone = sit ? (sit.cls === 'green' ? 'success' : sit.cls === 'red' ? 'danger' : sit.cls === 'yellow' ? 'warning' : 'neutral') : 'neutral';

  return (
    <Drawer
      onClose={onClose}
      title={a.nome || 'Sem nome'}
      subtitle={a.email || '—'}
      badges={
        !editMode ? (
          <>
            {sit && <Badge tone={sitTone} dot>{sit.label}</Badge>}
            {a.nivel_resultado && <NivelBadge nivel={a.nivel_resultado} />}
            {espaco && <Badge tone="info">{espaco}</Badge>}
            {a.eh_socio && <Badge tone="accent">Sócio</Badge>}
          </>
        ) : undefined
      }
      actions={canEdit ? <Button size="sm" variant={editMode ? 'ghost' : 'subtle'} onClick={onToggleEdit}>{editMode ? 'Cancelar' : 'Editar'}</Button> : undefined}
    >
      {editMode ? (
          <EditForm a={a} turmas={turmas} onSaved={onSaved} />
        ) : (
          <>
            <Tabs tabs={TABS.map((t) => ({ k: t.k, l: t.l }))} active={tab} onChange={setTab} />

            {tab === 'geral' && (
              <Section>
                {a.profissao && <Row k="Profissão" v={a.profissao} />}
                <Row k="E-mail" v={a.email} />
                <Row k="Telefone" v={tel(a.telefone)} />
                {a.telefone_profissional && <Row k="Tel. profissional" v={tel(a.telefone_profissional)} />}
                {a.documento && <Row k={a.tipo_documento || 'CPF/CNPJ'} v={a.documento} />}
                <Row k="Endereço" v={[a.endereco_logradouro, a.endereco_numero, a.bairro, a.cidade, a.estado].filter(Boolean).join(', ') || '—'} />
                <div className="flex gap-2 flex-wrap mt-2">
                  {[['Facebook', a.link_facebook], ['Instagram', a.instagram_url], ['YouTube', a.youtube_url], ['Site', a.site_profissional]].filter(([, u]) => u).map(([l, u]) => (
                    <a key={l as string} href={u as string} target="_blank" rel="noopener" className="text-xs px-2 py-1 rounded border border-[var(--border)] text-[var(--accent)]">{l}</a>
                  ))}
                </div>
              </Section>
            )}
            {tab === 'acesso' && (
              <Section>
                <Row k="Nível de resultado" v={nivelLabel(a.nivel_resultado) || '—'} />
                <Row k="Espaço de instrução" v={espaco || '—'} />
                <Row k="Turma" v={[a.turma_codigo, a.turma_aurum_codigo].filter(Boolean).join(' · ') || '—'} />
                {a.placa_aurum && <Row k="Placa Aurum" v={a.placa_aurum} />}
                {a.status_acesso_central && <Row k="Status" v={a.status_acesso_central} />}
                {a.produto && <Row k="Produto" v={a.produto} />}
                {a.regra_acesso && <Row k="Regra de acesso" v={a.regra_acesso} />}
                {a.origem_acesso && <Row k="Origem" v={a.origem_acesso} />}
                <Row k="Registrado no SIP" v={a.sip_registrado ? 'Sim ✓' : 'Não'} />
                {(a.cs_estagio || a.cs_responsavel || a.cs_observacoes) && (
                  <><div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Acompanhamento CS</div>
                    {a.cs_estagio && <Row k="Estágio" v={a.cs_estagio} />}
                    {a.cs_responsavel && <Row k="Responsável" v={a.cs_responsavel} />}
                    {a.cs_observacoes && <Row k="Obs (CS)" v={a.cs_observacoes} />}</>
                )}
                {a.tratamento_manual && <div className="mt-3 p-2 rounded bg-[var(--yellow-subtle)] text-[var(--yellow)] text-xs">⚠ {a.tratamento_manual}</div>}
                {a.obs_central && <Row k="Obs" v={a.obs_central} />}
              </Section>
            )}
            {tab === 'curso' && <CursoTab alunoId={a.id} />}
            {tab === 'renovacao' && (
              <Section>
                {(() => {
                  const rs = renovacaoStatus(a.turma_codigo);
                  const info = rs ? RENOVACAO_LABEL[rs] : null;
                  return info ? (
                    <div className={`p-2.5 rounded-[var(--r-md)] mb-2 text-xs ${rs === 'em_renovacao' ? 'bg-[var(--yellow-subtle)] text-[var(--yellow)]' : 'bg-[var(--red-subtle)] text-[var(--red)]'}`}>
                      {rs === 'em_renovacao' ? '🔄' : '⚠'} {info.label}
                      <div className="text-[var(--fg-3)] mt-0.5">
                        {rs === 'em_renovacao'
                          ? `Turma ${a.turma_codigo} (T1–T29): segue o processo de renovação.`
                          : `Turma ${a.turma_codigo} (T30+): acesso vencido, sem processo de renovação (em dia, porém não renovado).`}
                      </div>
                    </div>
                  ) : <div className="text-xs text-[var(--fg-3)] mb-2">Sem turma THB definida — status de renovação indisponível.</div>;
                })()}
                <Row k="Turma" v={a.turma_codigo || '—'} />
                <Row k="Vencimento" v={dataBR(a.data_expiracao)} />
                <Row k="Data da compra" v={dataBR(a.data_compra_importada)} />
                {a.tempo_acesso && <Row k="Tempo de acesso" v={a.tempo_acesso} />}
                {a.oferta && <Row k="Oferta" v={a.oferta} />}
                {a.tipo_oferta && <Row k="Tipo de oferta" v={a.tipo_oferta} />}
              </Section>
            )}
            {tab === 'financeiro' && (
              <Section>
                <div className="grid grid-cols-3 gap-3 mb-3">
                  <Kpi label="Pago" value={money(a.valor_pago)} color="var(--green)" />
                  <Kpi label="Total" value={money(a.valor_total)} />
                  <Kpi label="Saldo devedor" value={money(saldo)} color={saldo > 0 ? 'var(--red)' : undefined} />
                </div>
                {a.status_pagamento && <Row k="Status" v={a.status_pagamento} />}
                <Row k="Último pagamento" v={dataBR(a.ultimo_pagamento)} />
                {a.num_cobrancas != null && <Row k="Nº de cobranças" v={String(a.num_cobrancas)} />}
                {saldo > 0
                  ? <div className="mt-3 p-2 rounded bg-[var(--red-subtle)] text-[var(--red)] text-xs">⚠ Regularização necessária — saldo em aberto: {money(saldo)}</div>
                  : <div className="mt-3 p-2 rounded bg-[var(--green-subtle)] text-[var(--green)] text-xs">✓ Sem pendências financeiras</div>}
              </Section>
            )}
            {tab === 'jornada' && (
              <Section>
                <JornadaCard label="Holding Total" on={!!a.tem_ht} extra={a.ativacao_ht_status ? `Status: ${a.ativacao_ht_status}` : ''} />
                <JornadaCard label="Holding Masters" on={!!a.tem_hm} extra={a.hm_plano ? `Plano: ${a.hm_plano}` : ''} />
                <PlacaJornada on={temPlaca} hist={placaHist} loading={placaLoading} />
                <JornadaCard label="Depoimento" on={!!a.tem_depoimento} extra={a.total_depoimentos ? `${a.total_depoimentos} depoimento(s)` : ''} href={a.tem_depoimento ? '/depoimentos' : undefined} />
                <div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Metadados</div>
                {a.fonte && <Row k="Fonte" v={a.fonte} />}
                <Row k="Importado em" v={dataBR(a.importado_em)} />
                <Row k="Atualizado em" v={dataBR(a.atualizado_em)} />
                {a.hotmart_ucode && <Row k="Hotmart UCode" v={a.hotmart_ucode} />}
              </Section>
            )}
          </>
        )}
    </Drawer>
  );
}

function Section({ children }: { children: React.ReactNode }) {
  return <div className="space-y-1.5">{children}</div>;
}
function Row({ k, v }: { k: string; v: string | null }) {
  return <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]"><span className="text-xs text-[var(--fg-3)]">{k}</span><span className="text-sm text-[var(--fg)] text-right">{v || '—'}</span></div>;
}
function Kpi({ label, value, color }: { label: string; value: string; color?: string }) {
  return <div className="rounded-[var(--r-md)] border border-[var(--border)] p-2 text-center"><div className="font-bold text-sm" style={{ color: color || 'var(--fg)' }}>{value}</div><div className="text-[10px] text-[var(--fg-3)]">{label}</div></div>;
}
function JornadaCard({ label, on, extra, href }: { label: string; on: boolean; extra?: string; href?: string }) {
  const body = (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">{label}</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? '✓ Sim' : '— Não'}</span>
      </div>
      {extra && <div className="text-xs text-[var(--fg-3)] mt-1">{extra}</div>}
    </div>
  );
  return href ? <a href={href}>{body}</a> : body;
}

// ── Placa de Resultado: card + histórico (solicitação + auditoria) ──
function PlacaJornada({ on, hist, loading }: { on: boolean; hist: PlacaHistorico | null; loading: boolean }) {
  const sol = hist?.solicitacao;
  const aud = hist?.auditoria;
  const stepIdx = aud?.step_index ?? sol?.auditoria_step ?? sol?.step_index ?? null;
  const stepNome = stepIdx != null && AUDIT_STEPS[stepIdx] ? AUDIT_STEPS[stepIdx].name : null;
  const dates = aud?.dates || {};
  const carimbos = AUDIT_STEPS.map((s) => ({ nome: s.name, quando: dates[s.key] })).filter((c) => c.quando);

  return (
    <div className={`p-3 rounded-[var(--r-md)] border mb-2 ${on ? 'border-[var(--accent-border)]' : 'border-[var(--border)] opacity-60'}`}>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-[var(--fg)]">Placa de Resultado</span>
        <span className="text-xs" style={{ color: on ? 'var(--green)' : 'var(--fg-3)' }}>{on ? '✓ Sim' : '— Não'}</span>
      </div>

      {on && loading && <div className="text-xs text-[var(--fg-3)] mt-2">Carregando histórico…</div>}

      {on && !loading && hist && (
        <div className="mt-2 space-y-2">
          <div className="flex flex-wrap gap-1.5">
            {stepNome && <Badge tone="info">{stepNome}</Badge>}
            {sol?.status && <Badge tone="neutral">{sol.status}</Badge>}
            {aud?.encerrado && <Badge tone="warning">Encerrado</Badge>}
            {sol?.regularizacao_pendente && <Badge tone="danger">Regularização pendente</Badge>}
          </div>
          <div className="text-xs space-y-0.5 text-[var(--fg-3)]">
            {aud?.protocolo && <div>Protocolo: <span className="text-[var(--fg-2)]">{aud.protocolo}</span></div>}
            {sol?.codigo_rastreio && <div>Rastreio: <span className="text-[var(--fg-2)]">{sol.codigo_rastreio}</span></div>}
            {(aud?.faturamento || sol?.faturamento_declarado) != null && <div>Faturamento: <span className="text-[var(--fg-2)]">{money(aud?.faturamento ?? sol?.faturamento_declarado ?? null)}</span></div>}
            {sol?.entrevista_data && <div>Entrevista: <span className="text-[var(--fg-2)]">{dataBR(sol.entrevista_data)}{sol.entrevista_hora ? ` ${String(sol.entrevista_hora).slice(0, 5)}` : ''}</span></div>}
            {sol?.motivo_retorno && <div className="text-[var(--red)]">Motivo do retorno: {sol.motivo_retorno}</div>}
          </div>

          {carimbos.length > 0 && (
            <div className="mt-2 border-l border-[var(--border)] pl-3 space-y-1.5">
              {carimbos.map((c) => (
                <div key={c.nome} className="relative text-xs">
                  <span className="absolute -left-[15px] top-1 w-1.5 h-1.5 rounded-full bg-[var(--accent)]" />
                  <span className="text-[var(--fg-2)]">{c.nome}</span>
                  <span className="text-[var(--fg-4)]"> · {c.quando}</span>
                </div>
              ))}
            </div>
          )}

          {aud?.obs && <div className="text-xs text-[var(--fg-3)] italic">“{aud.obs}”</div>}
          <a href="/relatorios/placas#solicitacoes" className="inline-block text-xs text-[var(--accent)]">Abrir no Relatório de Placas →</a>
        </div>
      )}

      {on && !loading && hist && !sol && !aud && (
        <div className="text-xs text-[var(--fg-3)] mt-2">Sem registro detalhado de solicitação/auditoria.</div>
      )}
    </div>
  );
}

// ── Curso: desempenho (DADOS ILUSTRATIVOS / MOCK) ──
function CursoTab({ alunoId }: { alunoId: string }) {
  const m = useMemo(() => cursoDesempenhoMock(alunoId), [alunoId]);
  return (
    <Section>
      <div className="p-2 rounded-[var(--r-md)] bg-[var(--surface-3)] text-[10px] text-[var(--fg-3)] mb-2">
        ⓘ Dados ilustrativos — sem integração real de progresso de curso ainda.
      </div>
      <div className="grid grid-cols-3 gap-3 mb-3">
        <Kpi label="Progresso" value={`${m.progressoGeral}%`} color={m.progressoGeral >= 66 ? 'var(--green)' : m.progressoGeral >= 33 ? 'var(--yellow)' : 'var(--red)'} />
        <Kpi label="Módulos" value={`${m.modulosConcluidos}/${m.modulosTotal}`} />
        <Kpi label="Aulas" value={`${m.aulasAssistidas}/${m.aulasTotal}`} />
      </div>
      <Row k="Engajamento" v={m.engajamento} />
      <Row k="Último acesso" v={m.ultimoAcessoDias === 0 ? 'Hoje' : `Há ${m.ultimoAcessoDias} dia(s)`} />
      <div className="text-xs font-semibold text-[var(--fg-3)] mt-3 mb-1">Progresso por módulo</div>
      <div className="space-y-2">
        {m.modulos.map((mod) => (
          <div key={mod.nome}>
            <div className="flex justify-between text-xs mb-1">
              <span className="text-[var(--fg-2)]">{mod.nome}</span>
              <span className="text-[var(--fg-3)] tabular">{mod.progresso}%{mod.concluido ? ' ✓' : ''}</span>
            </div>
            <div className="h-1.5 rounded-full bg-[var(--surface-3)] overflow-hidden">
              <div className="h-full rounded-full" style={{ width: `${mod.progresso}%`, background: mod.concluido ? 'var(--green)' : 'var(--accent)' }} />
            </div>
          </div>
        ))}
      </div>
    </Section>
  );
}

// ── Formulário de edição (porta de saveAlunoEdit) ──
function EditForm({ a, turmas, onSaved }: { a: Aluno360; turmas: Turma[]; onSaved: (m: string) => void }) {
  const [f, setF] = useState<Record<string, string>>(() => ({
    nome: a.nome || '', email: a.email || '', telefone: a.telefone || '', telefone_profissional: a.telefone_profissional || '',
    documento: a.documento && !a.documento.includes('*') ? a.documento : '', tipo_documento: a.tipo_documento || '', profissao: a.profissao || '',
    link_facebook: a.link_facebook || '', instagram_url: a.instagram_url || '', youtube_url: a.youtube_url || '', site_profissional: a.site_profissional || '',
    cep: a.cep || '', endereco_logradouro: a.endereco_logradouro || '', endereco_numero: a.endereco_numero || '', endereco_complemento: a.endereco_complemento || '',
    bairro: a.bairro || '', cidade: a.cidade || '', estado: a.estado || '', pais: a.pais || '',
    nivel_resultado: a.nivel_resultado || '', turma_id: a.turma_id ? String(a.turma_id) : '', turma_aurum_id: a.turma_aurum_id ? String(a.turma_aurum_id) : '',
    espaco_instrucao: a.espaco_instrucao || '', placa_aurum: a.placa_aurum || '', hotmart_ucode: a.hotmart_ucode || '',
    situacao_acesso: a.situacao_acesso || '', status_acesso_central: a.status_acesso_central || '',
    data_expiracao: a.data_expiracao || '', tratamento_manual: a.tratamento_manual || '', obs_central: a.obs_central || '',
  }));
  const [busy, setBusy] = useState(false);
  const s = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));
  const thbTurmas = turmas.filter((t) => t.tipo !== 'aurum');
  const aurumTurmas = turmas.filter((t) => t.tipo === 'aurum');

  async function save() {
    setBusy(true);
    const fields: Record<string, unknown> = {};
    const txt = (k: string) => (f[k]?.trim() ? f[k].trim() : null);
    for (const k of ['nome', 'email', 'telefone', 'telefone_profissional', 'tipo_documento', 'profissao', 'link_facebook', 'instagram_url', 'youtube_url', 'site_profissional', 'cep', 'endereco_logradouro', 'endereco_numero', 'endereco_complemento', 'bairro', 'cidade', 'pais', 'nivel_resultado', 'espaco_instrucao', 'placa_aurum', 'hotmart_ucode', 'situacao_acesso', 'status_acesso_central', 'data_expiracao', 'tratamento_manual', 'obs_central']) fields[k] = txt(k);
    fields.estado = f.estado?.trim() ? f.estado.trim().toUpperCase() : null;
    if (f.documento.trim()) fields.documento = f.documento.trim(); // só sobrescreve se preenchido (mascarado fica vazio)
    fields.turma_id = f.turma_id ? Number(f.turma_id) : null;
    fields.turma_aurum_id = f.turma_aurum_id ? Number(f.turma_aurum_id) : null;
    const r = await updateAluno(a.id, fields);
    setBusy(false);
    onSaved(r.ok ? 'Aluno atualizado!' : 'Erro ao salvar: ' + (r.msg || ''));
  }

  // Função (não componente) — evita recriar tipo de componente a cada render (perda de foco).
  const inp = (k: string, label: string) => (
    <label className="block"><span className="text-xs text-[var(--fg-3)]">{label}</span>
      <input value={f[k]} onChange={(e) => s(k, e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]" /></label>
  );

  return (
    <div className="space-y-2.5">
      <div className="grid grid-cols-2 gap-2">
        {inp('nome', 'Nome')}{inp('email', 'E-mail')}
        {inp('telefone', 'Telefone')}{inp('telefone_profissional', 'Tel. prof.')}
        {inp('documento', 'Documento (vazio mantém)')}{inp('tipo_documento', 'Tipo doc')}
        {inp('profissao', 'Profissão')}
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Nível</span>
          <select value={f.nivel_resultado} onChange={(e) => s('nivel_resultado', e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]">
            <option value="">—</option>{nivelOptions().map((n) => <option key={n.id} value={n.id}>{n.label}</option>)}
          </select></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Turma</span>
          <select value={f.turma_id} onChange={(e) => s('turma_id', e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]">
            <option value="">—</option>{thbTurmas.map((t) => <option key={t.id} value={t.id}>{t.codigo}</option>)}
          </select></label>
        <label className="block"><span className="text-xs text-[var(--fg-3)]">Turma Aurum</span>
          <select value={f.turma_aurum_id} onChange={(e) => s('turma_aurum_id', e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]">
            <option value="">—</option>{aurumTurmas.map((t) => <option key={t.id} value={t.id}>{t.codigo}</option>)}
          </select></label>
        {inp('espaco_instrucao', 'Espaço instrução')}{inp('placa_aurum', 'Placa Aurum')}
        {inp('cep', 'CEP')}{inp('endereco_logradouro', 'Logradouro')}
        {inp('endereco_numero', 'Número')}{inp('endereco_complemento', 'Complemento')}
        {inp('bairro', 'Bairro')}{inp('cidade', 'Cidade')}
        {inp('estado', 'Estado')}{inp('pais', 'País')}
        {inp('situacao_acesso', 'Situação acesso')}{inp('status_acesso_central', 'Status central')}
        {inp('data_expiracao', 'Data expiração (YYYY-MM-DD)')}{inp('hotmart_ucode', 'Hotmart UCode')}
      </div>
      <label className="block"><span className="text-xs text-[var(--fg-3)]">Tratamento manual</span>
        <input value={f.tratamento_manual} onChange={(e) => s('tratamento_manual', e.target.value)} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]" /></label>
      <label className="block"><span className="text-xs text-[var(--fg-3)]">Obs central</span>
        <textarea value={f.obs_central} onChange={(e) => s('obs_central', e.target.value)} rows={3} className="mt-1 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-sm text-[var(--fg)]" /></label>
      <button onClick={save} disabled={busy} className="w-full py-2 rounded-[var(--r-md)] bg-[var(--accent)] text-black font-semibold disabled:opacity-60">{busy ? 'Salvando…' : 'Salvar alterações'}</button>
    </div>
  );
}
