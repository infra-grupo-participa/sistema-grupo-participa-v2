'use client';

// Filtros globais da tela (funil, período, canal), no molde dos filtros do ATM. Gravam na URL pelo pai.
import { PERIODOS, ROTULO_PERIODO, type ChavePeriodo } from '../domain/recorte';
import { FUNIS, ROTULO_CANAL, ROTULO_FUNIL, type FiltroCanal, type FiltroFunil, type Periodo } from '../domain/tipos';

const SELECT = 'min-h-10 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 text-sm text-[var(--fg)]';
const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export function SeletorGlobal({ funil, periodo, canal, datas, onChange }: {
  funil: FiltroFunil; periodo: string; canal: FiltroCanal; datas: Periodo | null;
  onChange: (m: { funil?: FiltroFunil; periodo?: string; canal?: FiltroCanal }) => void;
}) {
  return (
    <div className="flex flex-wrap items-end gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
      <label className="grid min-w-[9rem] flex-1 gap-1 text-xs text-[var(--fg-2)] sm:flex-none">
        Funil
        <select className={SELECT} value={funil} onChange={(e) => onChange({ funil: e.target.value as FiltroFunil })}>
          <option value="todos">Todos</option>
          {FUNIS.map((f) => <option key={f} value={f}>{ROTULO_FUNIL[f]}</option>)}
        </select>
      </label>
      <label className="grid min-w-[9rem] flex-1 gap-1 text-xs text-[var(--fg-2)] sm:flex-none">
        Período
        <select className={SELECT} value={periodo} onChange={(e) => onChange({ periodo: e.target.value })}>
          {PERIODOS.map((p) => <option key={p} value={p}>{ROTULO_PERIODO[p as ChavePeriodo]}</option>)}
        </select>
      </label>
      <label className="grid min-w-[9rem] flex-1 gap-1 text-xs text-[var(--fg-2)] sm:flex-none">
        Canal
        <select className={SELECT} value={canal} onChange={(e) => onChange({ canal: e.target.value as FiltroCanal })}>
          <option value="todos">Todos</option>
          {(['meta', 'google'] as const).map((c) => <option key={c} value={c}>{ROTULO_CANAL[c]}</option>)}
        </select>
      </label>
      {datas && (
        <p className="w-full text-xs text-[var(--fg-3)] sm:w-auto sm:pb-2.5">
          {datas.de === datas.ate ? dataCurta(datas.de) : `${dataCurta(datas.de)} a ${dataCurta(datas.ate)}`}
          {periodo === 'semana' ? ' (semana de segunda a domingo, provisória)' : ''}
        </p>
      )}
    </div>
  );
}
