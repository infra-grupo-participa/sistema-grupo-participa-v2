'use client';

import { useEffect, useMemo, useState } from 'react';
import { applyDashFilters, computeAlunosMetrics, computeTurmaEspacoMatrix, type DashFiltros, type DashView, type Distribuicao, type AnoEspaco } from '../domain/metrics';
import type { Aluno360 } from '../domain/aluno-360';
import { ESPACO_LABEL } from '../domain/aluno-360';
import { Card, SectionTitle, Button, Input, Modal, MultiSelect } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

// Coage valor de filtro para array (visões salvas no formato antigo eram string única).
const asArr = (v: unknown): string[] => (Array.isArray(v) ? (v as string[]) : typeof v === 'string' && v ? [v] : []);
const normFiltros = (f: DashFiltros): DashFiltros => ({ espaco: asArr(f.espaco), estado: asArr(f.estado), turma: asArr(f.turma) });

const VIEWS_KEY = 'gp_dash_views';
/* viz-colors: paleta de fatias do donut por turma — cores de gráfico, não da UI */
const DONUT_COLORS = ['#f29725', '#60a5fa', '#a78bfa', '#34d399', '#f87171', '#fbbf24', '#22d3ee', '#c084fc']; /* viz-colors */

interface SavedView {
  name: string;
  view: DashView;
  filtros: DashFiltros;
}

export function DashboardAlunos({ alunos }: { alunos: Aluno360[] }) {
  const [view, setView] = useState<DashView>('alunos');
  const [filtros, setFiltros] = useState<DashFiltros>({});
  const [views, setViews] = useState<SavedView[]>([]);
  useEffect(() => {
    try {
      const raw = JSON.parse(localStorage.getItem(VIEWS_KEY) || '[]') as SavedView[];
      setViews(raw.map((v) => ({ ...v, filtros: normFiltros(v.filtros) }))); // eslint-disable-line react-hooks/set-state-in-effect
    } catch { /* ignore */ }
  }, []);

  const m = useMemo(() => computeAlunosMetrics(alunos, view, filtros), [alunos, view, filtros]);
  const matrix = useMemo(() => computeTurmaEspacoMatrix(applyDashFilters(alunos, view, filtros)), [alunos, view, filtros]);

  const estados = useMemo(() => Array.from(new Set(alunos.map((a) => String(a.estado ?? '').toUpperCase()).filter(Boolean))).sort(), [alunos]);
  const turmas = useMemo(() => Array.from(new Set(alunos.map((a) => a.turma_codigo).filter(Boolean) as string[])).sort((a, b) => b.localeCompare(a, 'pt-BR', { numeric: true, sensitivity: 'base' })), [alunos]);
  const temFiltro = Boolean(filtros.espaco?.length || filtros.estado?.length || filtros.turma?.length || view === 'socios');

  const persistViews = (next: SavedView[]) => { setViews(next); localStorage.setItem(VIEWS_KEY, JSON.stringify(next)); };
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const salvarVisao = () => {
    const name = saveName.trim();
    if (!name) return;
    persistViews([...views.filter((v) => v.name !== name), { name, view, filtros }]);
    setSaveOpen(false);
    setSaveName('');
  };

  const set = (k: keyof DashFiltros, v: string[]) => setFiltros((f) => ({ ...f, [k]: v.length ? v : undefined }));

  return (
    <div>
      <div className="flex items-center justify-end mb-3">
        <span className="text-xs text-[var(--fg-3)] tabular">{m.total.toLocaleString('pt-BR')} registros</span>
      </div>

      <div className="flex flex-wrap gap-2 mb-3">
        <MultiSelect values={filtros.espaco || []} onChange={(v) => set('espaco', v)} placeholder="Todos os espaços" options={Object.entries(ESPACO_LABEL).map(([value, label]) => ({ value, label }))} />
        <MultiSelect values={filtros.turma || []} onChange={(v) => set('turma', v)} placeholder="Todas as turmas" options={turmas.map((t) => ({ value: t, label: t }))} />
        <MultiSelect values={filtros.estado || []} onChange={(v) => set('estado', v)} placeholder="Todos os estados" options={estados.map((e) => ({ value: e, label: e }))} />
        {temFiltro && <Button variant="ghost" size="sm" onClick={() => { setFiltros({}); setView('alunos'); }}>Limpar</Button>}
        <Button variant="subtle" size="sm" onClick={() => setSaveOpen(true)}><Icon name="star" size={13} /> Salvar visão</Button>
      </div>

      {saveOpen && (
        <Modal
          title="Salvar visão rápida"
          width="max-w-sm"
          onClose={() => setSaveOpen(false)}
          footer={
            <>
              <Button variant="ghost" size="sm" onClick={() => setSaveOpen(false)}>Cancelar</Button>
              <Button size="sm" onClick={salvarVisao} disabled={!saveName.trim()}>Salvar</Button>
            </>
          }
        >
          <label className="block">
            <span className="text-xs text-[var(--fg-3)]">Nome da visão</span>
            <Input autoFocus value={saveName} onChange={(e) => setSaveName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && salvarVisao()} placeholder="Ex.: THB GO ativos" className="mt-1" />
          </label>
        </Modal>
      )}

      {views.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          {views.map((v) => (
            <span key={v.name} className="inline-flex items-center gap-1 rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-2)] pl-3 pr-1.5 py-1 text-xs">
              <button onClick={() => { setView(v.view); setFiltros(v.filtros); }} className="text-[var(--fg-2)] hover:text-[var(--accent)] font-medium">{v.name}</button>
              <button onClick={() => persistViews(views.filter((x) => x.name !== v.name))} aria-label={`Excluir visão ${v.name}`} className="text-[var(--fg-4)] hover:text-[var(--red)] inline-flex"><Icon name="x" size={12} /></button>
            </span>
          ))}
        </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-5">
        <KpiBreak label="Total de alunos" total={m.total} titulares={m.totalTitulares} socios={m.totalSocios} color="var(--accent)" i={0} />
        {m.espacoKpi.map((e, i) => <KpiBreak key={e.key} label={e.label} total={e.total} titulares={e.titulares} socios={e.socios} color={e.color} i={i + 1} />)}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="p-5 gp-rise" style={{ animationDelay: '0ms' }}>
          <SectionTitle right={<LegendaTS />}>Por espaço de instrução</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Titulares × sócios por espaço de instrução.</p>
          <Bars data={m.porEspaco} total={m.total} />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '60ms' }}>
          <SectionTitle>Distribuição por turma</SectionTitle>
          <Donut data={m.porTurma} total={m.total} />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '120ms' }}>
          <SectionTitle>Jornada no programa</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Nº de alunos do recorte que atingiram cada marco.</p>
          <Bars
            data={[
              { key: 'placa', label: 'Com placa', count: m.placa, color: 'var(--nivel-ouro)' },
              { key: 'dep', label: 'Com depoimento', count: m.depoimento, color: 'var(--green)' },
              { key: 'sip', label: 'Com SIP (Time Holding Brasil)', count: m.sip, color: 'var(--nivel-diamante-vermelho)' },
            ]}
            total={m.total}
          />
        </Card>
        <Card className="p-5 gp-rise" style={{ animationDelay: '180ms' }}>
          <SectionTitle right={<LegendaTS />}>Top estados</SectionTitle>
          <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Passe o mouse para ver o detalhe titular/sócio.</p>
          <Bars data={m.porEstado} total={m.total} />
        </Card>
        {matrix.turmas.length > 0 && (
          <Card className="p-5 lg:col-span-2 gp-rise" style={{ animationDelay: '240ms' }}>
            <SectionTitle>Matriz turma × espaço de instrução</SectionTitle>
            <div className="max-h-[420px] overflow-auto">
              <Matrix matrix={matrix} />
            </div>
          </Card>
        )}
        {m.porAnoEspaco.length > 0 && (
          <Card className="p-5 lg:col-span-2 gp-rise" style={{ animationDelay: '300ms' }}>
            <SectionTitle right={<LegendaEspacos itens={m.espacoKpi} />}>Linha do tempo de entrada no THB</SectionTitle>
            <p className="text-[11px] text-[var(--fg-3)] -mt-1 mb-3">Ingressos por ano, empilhados por espaço de instrução.</p>
            <StackedColumn data={m.porAnoEspaco} />
          </Card>
        )}
      </div>
    </div>
  );
}

function Bars({ data, total }: { data: Distribuicao[]; total: number }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  if (!data.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  return (
    <div className="space-y-2.5">
      {data.map((d) => (
        <div key={d.key} title={d.titulares != null ? `${d.titulares} titulares · ${d.socios} sócios` : undefined}>
          <div className="flex justify-between text-xs mb-1">
            <span className="text-[var(--fg-2)]">{d.label}</span>
            <span className="text-[var(--fg-3)] tabular">{d.count.toLocaleString('pt-BR')}{total ? <span className="text-[var(--fg-4)]"> · {Math.round((d.count / total) * 100)}%</span> : null}</span>
          </div>
          <div className="h-2 rounded-full bg-[var(--surface-3)] overflow-hidden flex">
            {d.titulares != null ? (
              <>
                <div className="h-full transition-[width] duration-500" style={{ width: `${(d.titulares / max) * 100}%`, background: 'var(--accent)' }} />
                <div className="h-full transition-[width] duration-500" style={{ width: `${((d.socios ?? 0) / max) * 100}%`, background: 'var(--nivel-diamante)' }} />
              </>
            ) : (
              <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${(d.count / max) * 100}%`, background: d.color || 'var(--accent)' }} />
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

function Donut({ data, total }: { data: Distribuicao[]; total: number }) {
  const sum = data.reduce((s, d) => s + d.count, 0);
  const outros = total - sum;
  const segs = [...data.map((d, i) => ({ label: d.label, count: d.count, color: DONUT_COLORS[i % DONUT_COLORS.length] })), ...(outros > 0 ? [{ label: 'Outros', count: outros, color: 'var(--fg-4)' }] : [])];
  const totalSeg = Math.max(1, segs.reduce((s, x) => s + x.count, 0));
  const R = 54, C = 2 * Math.PI * R;
  let offset = 0;
  if (!segs.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  return (
    <div className="flex items-center gap-5 flex-wrap">
      <svg width="132" height="132" viewBox="0 0 132 132" className="shrink-0">
        <circle cx="66" cy="66" r={R} fill="none" stroke="var(--surface-3)" strokeWidth="16" />
        {segs.map((s) => {
          const len = (s.count / totalSeg) * C;
          const el = (
            <circle key={s.label} cx="66" cy="66" r={R} fill="none" stroke={s.color} strokeWidth="16" strokeDasharray={`${len} ${C - len}`} strokeDashoffset={-offset} transform="rotate(-90 66 66)" />
          );
          offset += len;
          return el;
        })}
        <text x="66" y="62" textAnchor="middle" className="tabular" style={{ fill: 'var(--fg)', fontSize: 22, fontWeight: 700 }}>{total.toLocaleString('pt-BR')}</text>
        <text x="66" y="80" textAnchor="middle" style={{ fill: 'var(--fg-3)', fontSize: 10 }}>registros</text>
      </svg>
      <div className="flex-1 min-w-[140px] space-y-1.5 max-h-56 overflow-y-auto pr-1">
        {segs.map((s) => (
          <div key={s.label} className="flex items-center gap-2 text-xs">
            <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: s.color }} />
            <span className="text-[var(--fg-2)] flex-1 truncate">{s.label}</span>
            <span className="text-[var(--fg-3)] tabular">{s.count.toLocaleString('pt-BR')}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function Matrix({ matrix }: { matrix: ReturnType<typeof computeTurmaEspacoMatrix> }) {
  return (
    <table className="text-sm border-collapse min-w-full">
      <thead className="sticky top-0 z-10 bg-[var(--surface-1)]">
        <tr>
          <th className="text-left px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)] sticky left-0 bg-[var(--surface-1)]">Turma</th>
          {matrix.colunas.map((col) => (
            <th key={col.key} className="px-2 py-1.5 text-center">
              <span className="inline-flex items-center gap-1 text-[10px] text-[var(--fg-3)] whitespace-nowrap"><span className="w-2 h-2 rounded-full" style={{ background: col.color }} />{col.label}</span>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {matrix.turmas.map((t) => (
          <tr key={t} className="border-t border-[var(--border-faint)]">
            <td className="px-2 py-1.5 font-medium text-[var(--fg)] whitespace-nowrap sticky left-0 bg-[var(--surface-1)]">{t}</td>
            {matrix.colunas.map((col) => {
              const c = matrix.cells[t][col.key];
              const intensity = matrix.max ? c / matrix.max : 0;
              return (
                <td key={col.key} className="px-2 py-1.5 text-center tabular" style={{ background: c ? `color-mix(in srgb, ${col.color} ${Math.round(8 + intensity * 55)}%, transparent)` : 'transparent', color: c ? 'var(--fg)' : 'var(--fg-4)' }}>
                  {c || '·'}
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function KpiBreak({ label, total, titulares, socios, color, i = 0 }: { label: string; total: number; titulares: number; socios: number; color?: string; i?: number }) {
  return (
    <Card className="p-4 min-w-0 overflow-hidden gp-rise" style={{ borderTop: `2px solid ${color || 'var(--accent)'}`, animationDelay: `${i * 45}ms` }}>
      <div className="text-[11px] font-medium uppercase tracking-wide text-[var(--fg-3)] truncate">{label}</div>
      <div className="mt-1 text-2xl font-bold tabular leading-none text-[var(--fg)]">{total.toLocaleString('pt-BR')}</div>
      <div className="mt-1.5 flex items-center gap-2 text-[11px] tabular text-[var(--fg-3)]">
        <span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: 'var(--accent)' }} />{titulares.toLocaleString('pt-BR')} tit.</span>
        <span className="inline-flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full" style={{ background: 'var(--nivel-diamante)' }} />{socios.toLocaleString('pt-BR')} sóc.</span>
      </div>
    </Card>
  );
}

function LegendaTS() {
  return (
    <span className="flex items-center gap-3 text-[10px] text-[var(--fg-3)]">
      <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--accent)' }} /> Titulares</span>
      <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: 'var(--nivel-diamante)' }} /> Sócios</span>
    </span>
  );
}

function LegendaEspacos({ itens }: { itens: { key: string; label: string; color: string; total: number }[] }) {
  return (
    <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-[var(--fg-3)]">
      {itens.filter((e) => e.total !== 0).map((e) => (
        <span key={e.key} className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: e.color }} /> {e.label}</span>
      ))}
    </span>
  );
}

function StackedColumn({ data }: { data: AnoEspaco[] }) {
  const max = Math.max(1, ...data.map((d) => d.total));
  return (
    <div className="flex items-end gap-2 h-40 pt-2">
      {data.map((d) => (
        <div key={d.year} className="flex-1 flex flex-col items-center justify-end gap-1" title={d.segs.map((s) => `${ESPACO_LABEL[s.key] || s.key}: ${s.count}`).join(' · ')}>
          <span className="text-[10px] text-[var(--fg-3)] tabular">{d.total}</span>
          <div className="w-full rounded-t overflow-hidden flex flex-col-reverse" style={{ height: `${(d.total / max) * 100}%`, minHeight: 2 }}>
            {d.segs.map((s) => <div key={s.key} style={{ height: `${(s.count / d.total) * 100}%`, background: s.color }} />)}
          </div>
          <span className="text-[10px] text-[var(--fg-3)]">{d.year}</span>
        </div>
      ))}
    </div>
  );
}
