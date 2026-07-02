'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { HorarioSlot } from '../../domain/types';
import * as data from './placas-admin-data';
import { Button, Input, ConfirmDialog, EmptyState } from '@/shared/ui/components';
import { fmtDataExtenso } from './relatorio-shared';

export interface Agendamento { data: string; hora: string; nome: string | null; email: string | null }

interface CellItem { hora: string; slot?: HorarioSlot; ag?: Agendamento }
interface DiaAgenda { data: string; passado: boolean; itens: CellItem[]; agendados: number; disponiveis: number }

const hojeISO = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export function AgendaHorarios({ canEdit, flash, agendamentos }: { canEdit: boolean; flash: (m: string) => void; agendamentos: Agendamento[] }) {
  const [slots, setSlots] = useState<HorarioSlot[]>([]);
  const [novaData, setNovaData] = useState('');
  const [novaHora, setNovaHora] = useState('');
  const [excluirId, setExcluirId] = useState<number | null>(null);
  const [aba, setAba] = useState<'agenda' | 'historico'>('agenda');
  const dataRef = useRef<HTMLInputElement>(null);

  const reload = useCallback(async () => setSlots(await data.loadHorarios()), []);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { reload(); }, [reload]);

  // Agenda combinada por data → horários (slot disponível e/ou agendamento), classificada em passado/futuro.
  const dias = useMemo<DiaAgenda[]>(() => {
    const hoje = hojeISO();
    const byDate = new Map<string, Map<string, CellItem>>();
    const cell = (d: string, h: string) => {
      if (!byDate.has(d)) byDate.set(d, new Map());
      const md = byDate.get(d)!;
      if (!md.has(h)) md.set(h, { hora: h });
      return md.get(h)!;
    };
    for (const s of slots) cell(s.slot_data, String(s.hora).slice(0, 5)).slot = s;
    for (const a of agendamentos) cell(a.data, a.hora).ag = a;
    return Array.from(byDate.entries())
      .sort((x, y) => x[0].localeCompare(y[0]))
      .map(([d, horas]) => {
        const itens = Array.from(horas.values()).sort((x, y) => x.hora.localeCompare(y.hora));
        return {
          data: d,
          passado: d < hoje,
          itens,
          agendados: itens.filter((i) => i.ag).length,
          disponiveis: itens.filter((i) => i.slot?.ativo && !i.ag).length,
        };
      });
  }, [slots, agendamentos]);

  const futuros = useMemo(() => dias.filter((d) => !d.passado), [dias]);
  const passados = useMemo(() => [...dias.filter((d) => d.passado)].reverse(), [dias]); // mais recente primeiro

  // Métricas do topo + próxima entrevista.
  const proximas = useMemo(() => {
    const hoje = hojeISO();
    return agendamentos
      .filter((a) => a.data >= hoje)
      .sort((x, y) => (x.data + x.hora).localeCompare(y.data + y.hora));
  }, [agendamentos]);
  const proxima = proximas[0] || null;
  const slotsFuturos = useMemo(() => futuros.reduce((n, d) => n + d.disponiveis, 0), [futuros]);
  const realizadas = useMemo(() => {
    const hoje = hojeISO();
    return agendamentos.filter((a) => a.data < hoje).length;
  }, [agendamentos]);

  const focarNovo = () => { setAba('agenda'); setTimeout(() => dataRef.current?.focus(), 50); };
  const listaAtiva = aba === 'agenda' ? futuros : passados;

  return (
    <div>
      {/* Resumo + próxima entrevista */}
      <div className="grid gap-3 sm:grid-cols-3 mb-4">
        <Stat icon="calendar" tone="var(--accent)" value={proximas.length} label="Entrevistas agendadas" />
        <Stat icon="clipboard" tone="var(--green)" value={slotsFuturos} label="Horários livres à frente" />
        <Stat icon="check-circle" tone="var(--fg-2)" value={realizadas} label="Entrevistas realizadas" />
      </div>

      {proxima && (
        <div className="mb-4 rounded-[var(--r-lg)] border border-[var(--accent-border)] bg-[var(--accent-subtle)] p-4 flex items-center gap-3 flex-wrap">
          <span className="grid place-items-center w-10 h-10 rounded-[var(--r-md)] bg-[var(--accent)] text-black shrink-0"><Icon name="calendar" size={20} /></span>
          <div className="min-w-0 flex-1">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--accent)]">Próxima entrevista</div>
            <div className="text-sm font-bold text-[var(--fg)] capitalize truncate">{fmtDataExtenso(proxima.data)} · {proxima.hora}</div>
            <div className="text-xs text-[var(--fg-2)] truncate">{proxima.nome || 'Candidato'}{proxima.email ? ` · ${proxima.email}` : ''}</div>
          </div>
        </div>
      )}

      {/* Adicionar horário */}
      {canEdit && (
        <div className="flex flex-wrap gap-2 mb-4 items-end rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Data</label><Input ref={dataRef} type="date" value={novaData} onChange={(e) => setNovaData(e.target.value)} className="w-auto" /></div>
          <div><label className="block text-xs text-[var(--fg-3)] mb-1">Hora</label><Input type="time" value={novaHora} onChange={(e) => setNovaHora(e.target.value)} className="w-auto" /></div>
          <Button onClick={async () => { if (novaData && novaHora && (await data.criarHorario(novaData, novaHora))) { flash('Horário disponibilizado.'); setNovaHora(''); reload(); } }}><Icon name="plus" size={14} /> Disponibilizar horário</Button>
          <span className="ml-auto hidden sm:flex items-center gap-3 text-[11px] text-[var(--fg-3)] self-center">
            <Legenda cor="var(--accent)" txt="Agendado" />
            <Legenda cor="var(--green)" txt="Disponível" />
            <Legenda cor="var(--fg-4)" txt="Inativo" />
          </span>
        </div>
      )}

      {/* Abas: agenda (futuro) x histórico (passado) */}
      <div className="flex gap-1 border-b border-[var(--border)] mb-4">
        <TabBtn active={aba === 'agenda'} onClick={() => setAba('agenda')} icon="calendar" label="Agenda" count={futuros.length} />
        <TabBtn active={aba === 'historico'} onClick={() => setAba('historico')} icon="rotate" label="Histórico" count={passados.length} />
      </div>

      {listaAtiva.length === 0 ? (
        aba === 'agenda' ? (
          <div className="rounded-[var(--r-lg)] border border-dashed border-[var(--accent-border)] bg-[var(--accent-subtle)] py-10 px-6 text-center">
            <div className="flex justify-center text-[var(--accent)] mb-2"><Icon name="calendar" size={32} strokeWidth={1.5} /></div>
            <div className="text-sm font-semibold text-[var(--fg)]">Nenhum horário disponível à frente</div>
            <div className="text-xs text-[var(--fg-3)] mt-1 mb-4 max-w-sm mx-auto">Disponibilize horários para que os candidatos aprovados possam agendar a entrevista.</div>
            {canEdit && <Button variant="primary" size="sm" onClick={focarNovo}><Icon name="plus" size={14} /> Disponibilizar horário</Button>}
          </div>
        ) : (
          <EmptyState title="Sem histórico ainda" hint="Entrevistas realizadas e horários passados aparecerão aqui." icon="rotate" />
        )
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {listaAtiva.map((dia) => (
            <DiaCard key={dia.data} dia={dia} canEdit={canEdit} onToggle={async (id, ativo) => { if (await data.toggleHorario(id, ativo)) reload(); }} onExcluir={setExcluirId} />
          ))}
        </div>
      )}

      {excluirId !== null && (
        <ConfirmDialog
          title="Excluir slot"
          message="Excluir este horário disponível?"
          confirmLabel="Excluir"
          danger
          onConfirm={async () => { const id = excluirId; setExcluirId(null); if (id !== null && (await data.excluirHorario(id))) { flash('Horário removido.'); reload(); } }}
          onCancel={() => setExcluirId(null)}
        />
      )}
    </div>
  );
}

function DiaCard({ dia, canEdit, onToggle, onExcluir }: {
  dia: DiaAgenda; canEdit: boolean; onToggle: (id: number, ativo: boolean) => void; onExcluir: (id: number) => void;
}) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] overflow-hidden">
      <div className="px-3 py-2.5 border-b border-[var(--border)] bg-[var(--surface-3)] flex items-center gap-2">
        <Icon name="calendar" size={14} className="text-[var(--accent)] shrink-0" />
        <span className="text-sm font-semibold text-[var(--fg)] capitalize truncate flex-1">{fmtDataExtenso(dia.data)}</span>
        {dia.agendados > 0 && <span className="text-[10px] font-bold rounded-[var(--r-pill)] bg-[var(--accent-subtle)] text-[var(--accent)] px-2 py-0.5 shrink-0">{dia.agendados} agend.</span>}
      </div>
      <div className="divide-y divide-[var(--border-faint)]">
        {dia.itens.map((it) => {
          const booked = !!it.ag;
          const inativo = !!it.slot && !it.slot.ativo;
          const passadoSemUso = dia.passado && !booked && !inativo;
          const cor = booked ? 'var(--accent)' : passadoSemUso ? 'var(--fg-4)' : inativo ? 'var(--fg-4)' : 'var(--green)';
          return (
            <div key={it.hora} className="flex items-center gap-2 px-3 py-2">
              <span className="w-2 h-2 rounded-full shrink-0" style={{ background: cor }} />
              <span className={`text-sm tabular font-medium ${inativo ? 'text-[var(--fg-3)] line-through' : 'text-[var(--fg)]'}`}>{it.hora}</span>
              <span className="text-xs flex-1 min-w-0 truncate">
                {booked ? (
                  <span className={dia.passado ? 'text-[var(--green)] font-medium inline-flex items-center gap-1' : 'text-[var(--accent)] font-medium'} title={it.ag!.email || ''}>
                    {dia.passado && <Icon name="check" size={11} />}{it.ag!.nome || 'Candidato'}{dia.passado ? ' · realizada' : ''}
                  </span>
                ) : passadoSemUso ? (
                  <span className="text-[var(--fg-3)]">Não agendado</span>
                ) : inativo ? (
                  <span className="text-[var(--fg-3)]">Inativo</span>
                ) : (
                  <span className="text-[var(--green)]">Disponível</span>
                )}
                {booked && !it.slot && <span className="ml-1 text-[10px] text-[var(--yellow)]" title="Agendamento sem slot correspondente">· sem slot</span>}
              </span>
              {canEdit && it.slot && !dia.passado && (
                <>
                  <button onClick={() => onToggle(it.slot!.id, !it.slot!.ativo)} className="text-[var(--fg-3)] hover:text-[var(--fg)] inline-flex" title={it.slot.ativo ? 'Desativar' : 'Ativar'}><Icon name={it.slot.ativo ? 'pause' : 'play'} size={13} /></button>
                  <button onClick={() => onExcluir(it.slot!.id)} className="text-[var(--red)] inline-flex" title="Excluir"><Icon name="x" size={13} /></button>
                </>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Stat({ icon, tone, value, label }: { icon: string; tone: string; value: number; label: string }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-3 flex items-center gap-3">
      <span className="grid place-items-center w-9 h-9 rounded-[var(--r-md)] shrink-0" style={{ background: `color-mix(in srgb, ${tone} 14%, transparent)`, color: tone }}><Icon name={icon} size={17} /></span>
      <div className="min-w-0">
        <div className="text-xl font-bold tabular leading-none text-[var(--fg)]">{value}</div>
        <div className="text-[11px] text-[var(--fg-3)] truncate">{label}</div>
      </div>
    </div>
  );
}

function TabBtn({ active, onClick, icon, label, count }: { active: boolean; onClick: () => void; icon: string; label: string; count: number }) {
  return (
    <button onClick={onClick} className={`px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors inline-flex items-center gap-2 ${active ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:text-[var(--fg-2)]'}`}>
      <Icon name={icon} size={14} /> {label}
      <span className={`text-[11px] rounded-[var(--r-pill)] px-1.5 py-0.5 ${active ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'bg-[var(--surface-3)] text-[var(--fg-3)]'}`}>{count}</span>
    </button>
  );
}

function Legenda({ cor, txt }: { cor: string; txt: string }) {
  return <span className="inline-flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: cor }} /> {txt}</span>;
}
