'use client';

import { useMemo, useState } from 'react';
import { computeAlunosMetrics, type DashView, type Distribuicao } from '../domain/metrics';
import type { Aluno360 } from '../domain/aluno-360';
import { Card, StatCard, SectionTitle } from '@/shared/ui/components';

export function DashboardAlunos({ alunos }: { alunos: Aluno360[] }) {
  const [view, setView] = useState<DashView>('alunos');
  const m = useMemo(() => computeAlunosMetrics(alunos, view), [alunos, view]);

  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-4 flex-wrap">
        <div className="inline-flex rounded-[var(--r-md)] border border-[var(--border)] p-0.5 bg-[var(--surface-2)]">
          {(['alunos', 'socios'] as DashView[]).map((v) => (
            <button
              key={v}
              onClick={() => setView(v)}
              className={`px-3.5 py-1.5 rounded-[var(--r-sm)] text-sm font-medium capitalize transition-colors ${
                view === v ? 'bg-[var(--accent)] text-black' : 'text-[var(--fg-2)] hover:text-[var(--fg)]'
              }`}
            >
              {v === 'alunos' ? 'Alunos' : 'Sócios'}
            </button>
          ))}
        </div>
        <span className="text-xs text-[var(--fg-3)] tabular">{m.total.toLocaleString('pt-BR')} registros</span>
      </div>

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
          <SectionTitle>Jornada no programa</SectionTitle>
          <Bars
            data={[
              { key: 'ht', label: 'Holding Total', count: m.ht, color: 'var(--nivel-platina)' },
              { key: 'hm', label: 'Holding Masters', count: m.hm, color: 'var(--accent)' },
              { key: 'placa', label: 'Com placa', count: m.placa, color: 'var(--nivel-ouro)' },
              { key: 'dep', label: 'Com depoimento', count: m.depoimento, color: 'var(--green)' },
            ]}
            total={m.total}
          />
        </Card>
        <Card className="p-5">
          <SectionTitle>Por espaço de instrução</SectionTitle>
          <Bars data={m.porEspaco} total={m.total} />
        </Card>
        <Card className="p-5">
          <SectionTitle>Top estados</SectionTitle>
          <Bars data={m.porEstado} total={m.total} />
        </Card>
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

function Bars({ data, total }: { data: Distribuicao[]; total: number }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  if (!data.length) return <p className="text-sm text-[var(--fg-3)]">Sem dados.</p>;
  return (
    <div className="space-y-2.5">
      {data.map((d) => (
        <div key={d.key}>
          <div className="flex justify-between text-xs mb-1">
            <span className="text-[var(--fg-2)]">{d.label}</span>
            <span className="text-[var(--fg-3)] tabular">
              {d.count.toLocaleString('pt-BR')}
              {total ? <span className="text-[var(--fg-4)]"> · {Math.round((d.count / total) * 100)}%</span> : null}
            </span>
          </div>
          <div className="h-2 rounded-full bg-[var(--surface-3)] overflow-hidden">
            <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${(d.count / max) * 100}%`, background: d.color || 'var(--accent)' }} />
          </div>
        </div>
      ))}
    </div>
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
