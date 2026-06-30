'use client';

import { useEffect, useMemo, useState } from 'react';
import { applyDashFilters, computeAlunosMetrics, computeTurmaNivelMatrix, type DashFiltros, type DashView, type Distribuicao } from '../domain/metrics';
import type { Aluno360 } from '../domain/aluno-360';
import { nivelOptions } from '@/shared/domain/nivel-resultado';
import { Card, StatCard, SectionTitle, Button } from '@/shared/ui/components';

const VIEWS_KEY = 'gp_dash_views';
const DONUT_COLORS = ['#f29725', '#60a5fa', '#a78bfa', '#34d399', '#f87171', '#fbbf24', '#22d3ee', '#c084fc'];

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
    try { setViews(JSON.parse(localStorage.getItem(VIEWS_KEY) || '[]')); } catch { /* ignore */ } // eslint-disable-line react-hooks/set-state-in-effect
  }, []);

  const m = useMemo(() => computeAlunosMetrics(alunos, view, filtros), [alunos, view, filtros]);
  const matrix = useMemo(() => computeTurmaNivelMatrix(applyDashFilters(alunos, view, filtros)), [alunos, view, filtros]);

  const estados = useMemo(() => Array.from(new Set(alunos.map((a) => String(a.estado ?? '').toUpperCase()).filter(Boolean))).sort(), [alunos]);
  const turmas = useMemo(() => Array.from(new Set(alunos.map((a) => a.turma_codigo).filter(Boolean) as string[])).sort(), [alunos]);
  const temFiltro = Boolean(filtros.nivel || filtros.estado || filtros.turma || view === 'socios');

  const persistViews = (next: SavedView[]) => { setViews(next); localStorage.setItem(VIEWS_KEY, JSON.stringify(next)); };
  const salvarVisao = () => {
    const name = prompt('Nome da visão rápida:')?.trim();
    if (!name) return;
    persistViews([...views.filter((v) => v.name !== name), { name, view, filtros }]);
  };

  const set = (k: keyof DashFiltros, v: string) => setFiltros((f) => ({ ...f, [k]: v || undefined }));

  return (
    <div>
      {/* Toggle + filtros */}
      <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
        <div className="inline-flex rounded-[var(--r-md)] border border-[var(--border)] p-0.5 bg-[var(--surface-2)]">
          {(['alunos', 'socios'] as DashView[]).map((v) => (
            <button key={v} onClick={() => setView(v)} className={`px-3.5 py-1.5 rounded-[var(--r-sm)] text-sm font-medium transition-colors ${view === v ? 'bg-[var(--accent)] text-black' : 'text-[var(--fg-2)] hover:text-[var(--fg)]'}`}>
              {v === 'alunos' ? 'Alunos' : 'Sócios'}
            </button>
          ))}
        </div>
        <span className="text-xs text-[var(--fg-3)] tabular">{m.total.toLocaleString('pt-BR')} registros</span>
      </div>

      <div className="flex flex-wrap gap-2 mb-3">
        <Filtro value={filtros.nivel || ''} onChange={(v) => set('nivel', v)} placeholder="Todos os níveis" options={nivelOptions().map((n) => ({ value: n.id, label: n.label }))} />
        <Filtro value={filtros.turma || ''} onChange={(v) => set('turma', v)} placeholder="Todas as turmas" options={turmas.map((t) => ({ value: t, label: t }))} />
        <Filtro value={filtros.estado || ''} onChange={(v) => set('estado', v)} placeholder="Todos os estados" options={estados.map((e) => ({ value: e, label: e }))} />
        {temFiltro && <Button variant="ghost" size="sm" onClick={() => { setFiltros({}); setView('alunos'); }}>Limpar</Button>}
        <Button variant="subtle" size="sm" onClick={salvarVisao}>★ Salvar visão</Button>
      </div>

      {views.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          {views.map((v) => (
            <span key={v.name} className="inline-flex items-center gap-1 rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-2)] pl-3 pr-1.5 py-1 text-xs">
              <button onClick={() => { setView(v.view); setFiltros(v.filtros); }} className="text-[var(--fg-2)] hover:text-[var(--accent)] font-medium">{v.name}</button>
              <button onClick={() => persistViews(views.filter((x) => x.name !== v.name))} className="text-[var(--fg-4)] hover:text-[var(--red)]">✕</button>
            </span>
          ))}
        </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-5">
        <StatCard label="Total" value={m.total.toLocaleString('pt-BR')} hint={`${m.pctAtivos}% ativos`} />
        <StatCard label="Ativos" value={m.ativos.toLocaleString('pt-BR')} tone="var(--green)" />
        <StatCard label="Holding Total" value={m.ht.toLocaleString('pt-BR')} tone="var(--nivel-platina)" />
        <StatCard label="Holding Masters" value={m.hm.toLocaleString('pt-BR')} tone="var(--accent)" />
        <StatCard label="Aurum" value={m.aurum.toLocaleString('pt-BR')} tone="var(--nivel-ouro)" />
        <StatCard label="Sócios" value={m.socios.toLocaleString('pt-BR')} tone="var(--nivel-diamante)" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="p-5">
          <SectionTitle>Funil por nível</SectionTitle>
          <Bars data={m.porNivel} total={m.total} />
        </Card>
        <Card className="p-5">
          <SectionTitle>Distribuição por turma</SectionTitle>
          <Donut data={m.porTurma} total={m.total} />
        </Card>
        <Card className="p-5">
          <SectionTitle>Jornada no programa</SectionTitle>
          <Bars
            data={[
              { key: 'ht', label: 'Holding Total', count: m.ht, color: 'var(--nivel-platina)' },
              { key: 'hm', label: 'Holding Masters', count: m.hm, color: 'var(--accent)' },
              { key: 'placa', label: 'Com placa', count: m.placa, color: 'var(--nivel-ouro)' },
              { key: 'dep', label: 'Com depoimento', count: m.depoimento, color: 'var(--green)' },
              { key: 'sip', label: 'Com SIP (Time Holding Brasil)', count: m.sip, color: 'var(--nivel-diamante-vermelho)' },
            ]}
            total={m.total}
          />
        </Card>
        <Card className="p-5">
          <SectionTitle>Top estados</SectionTitle>
          <Bars data={m.porEstado} total={m.total} />
        </Card>
        {matrix.turmas.length > 0 && (
          <Card className="p-5 lg:col-span-2 overflow-x-auto">
            <SectionTitle>Matriz turma × nível</SectionTitle>
            <Matrix matrix={matrix} />
          </Card>
        )}
        {m.porAno.length > 0 && (
          <Card className="p-5 lg:col-span-2">
            <SectionTitle>Ingresso por ano</SectionTitle>
            <ColumnChart data={m.porAno} />
          </Card>
        )}
      </div>
    </div>
  );
}

function Filtro({ value, onChange, placeholder, options }: { value: string; onChange: (v: string) => void; placeholder: string; options: { value: string; label: string }[] }) {
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-1.5 text-sm text-[var(--fg)]">
      <option value="">{placeholder}</option>
      {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  );
}

function Bars({ data, total }: { data: Distribuicao[]; total: number }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  if (!data.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  return (
    <div className="space-y-2.5">
      {data.map((d) => (
        <div key={d.key}>
          <div className="flex justify-between text-xs mb-1">
            <span className="text-[var(--fg-2)]">{d.label}</span>
            <span className="text-[var(--fg-3)] tabular">{d.count.toLocaleString('pt-BR')}{total ? <span className="text-[var(--fg-4)]"> · {Math.round((d.count / total) * 100)}%</span> : null}</span>
          </div>
          <div className="h-2 rounded-full bg-[var(--surface-3)] overflow-hidden">
            <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${(d.count / max) * 100}%`, background: d.color || 'var(--accent)' }} />
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
      <div className="flex-1 min-w-[140px] space-y-1.5">
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

function Matrix({ matrix }: { matrix: ReturnType<typeof computeTurmaNivelMatrix> }) {
  return (
    <table className="text-sm border-collapse min-w-full">
      <thead>
        <tr>
          <th className="text-left px-2 py-1.5 text-[11px] font-semibold uppercase text-[var(--fg-3)]">Turma</th>
          {matrix.niveis.map((n) => (
            <th key={n.key} className="px-2 py-1.5 text-center">
              <span className="inline-flex items-center gap-1 text-[10px] text-[var(--fg-3)]"><span className="w-2 h-2 rounded-full" style={{ background: n.color }} />{n.label.split(' ')[0]}</span>
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {matrix.turmas.map((t) => (
          <tr key={t} className="border-t border-[var(--border-faint)]">
            <td className="px-2 py-1.5 font-medium text-[var(--fg)] whitespace-nowrap">{t}</td>
            {matrix.niveis.map((n) => {
              const c = matrix.cells[t][n.key];
              const intensity = matrix.max ? c / matrix.max : 0;
              return (
                <td key={n.key} className="px-2 py-1.5 text-center tabular" style={{ background: c ? `color-mix(in srgb, ${n.color} ${Math.round(8 + intensity * 55)}%, transparent)` : 'transparent', color: c ? 'var(--fg)' : 'var(--fg-4)' }}>
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

function ColumnChart({ data }: { data: Distribuicao[] }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  return (
    <div className="flex items-end gap-2 h-32 pt-2">
      {data.map((d) => (
        <div key={d.key} className="flex-1 flex flex-col items-center justify-end gap-1">
          <span className="text-[10px] text-[var(--fg-3)] tabular">{d.count}</span>
          <div className="w-full rounded-t bg-[var(--accent)] transition-[height] duration-500" style={{ height: `${(d.count / max) * 100}%`, minHeight: 2 }} />
          <span className="text-[10px] text-[var(--fg-3)]">{d.label}</span>
        </div>
      ))}
    </div>
  );
}
