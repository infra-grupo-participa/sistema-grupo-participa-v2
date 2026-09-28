'use client';

// Aba Relatórios: dropdown com os 6 tipos de relatório.
// "Carteira do board" (seleção de colunas + export XLSX/PDF) vive em ./CarteiraDoBoard.tsx.
// Os outros 5 são leitura do espelho da Hotmart (schema fin), já prontos em ui/hotmart/*.
import { useState } from 'react';
import { FilterSelect } from '@/shared/ui/components';
import type { ContaReceber } from '../domain/types';
import type { FinanceiroRepository } from '../application/ports';
import { FAMILIAS_EM_ORDEM, ROTULO_FAMILIA, type BoardHotmart, type FamiliaHotmart } from '../domain/hotmart';
import { CarteiraDoBoard } from './CarteiraDoBoard';
import { AceleraParaHM } from './hotmart/AceleraParaHM';
import { ProrataHM } from './hotmart/ProrataHM';
import { HotmartConciliacao } from './hotmart/HotmartConciliacao';
import { HotmartIdentidade } from './hotmart/HotmartIdentidade';
import { HotmartPessoas } from './hotmart/HotmartPessoas';

type TipoRelatorio = 'board' | 'pessoas' | 'conciliacao' | 'identidade' | 'acelera' | 'prorata';

const RELATORIOS: { tipo: TipoRelatorio; rotulo: string }[] = [
  { tipo: 'board', rotulo: 'Carteira do board' },
  { tipo: 'pessoas', rotulo: 'Pessoas na Hotmart' },
  { tipo: 'conciliacao', rotulo: 'Conciliação Hotmart × banco' },
  { tipo: 'identidade', rotulo: 'Mesma pessoa?' },
  { tipo: 'acelera', rotulo: 'Acelera → HM' },
  // Saiu do menu lateral na limpeza de 28/09; por pessoa continua na ficha do aluno.
  { tipo: 'prorata', rotulo: 'Pro rata (todos)' },
];

/** Botão do seletor de família — mesmo padrão visual usado em FaturamentoDiario.tsx. */
function BotaoFamilia({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      onClick={onClick}
      className={`rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold disabled:opacity-50 ${ativo ? 'border-[var(--accent)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)]'}`}
    >
      {children}
    </button>
  );
}

/** Seletor de família (HM / Aurum / Acelera Holding) — usado pelos relatórios que leem por família. */
function SeletorFamilia({ familia, onChange }: { familia: FamiliaHotmart; onChange: (f: FamiliaHotmart) => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {FAMILIAS_EM_ORDEM.map((f) => (
        <BotaoFamilia key={f} ativo={familia === f} onClick={() => onChange(f)}>
          {ROTULO_FAMILIA[f]}
        </BotaoFamilia>
      ))}
    </div>
  );
}

export function Relatorios({
  contas, turma, canVerDoc, repo, hotmartPorCard, tipoInicial,
}: {
  tipoInicial?: TipoRelatorio;
  contas: ContaReceber[];
  turma: string | null;
  canVerDoc: boolean;
  repo: FinanceiroRepository;
  hotmartPorCard: Map<string, BoardHotmart> | null;
}) {
  const [tipo, setTipo] = useState<TipoRelatorio>(tipoInicial ?? 'board');
  const [familia, setFamilia] = useState<FamiliaHotmart>('HM');

  return (
    <div className="space-y-4">
      <div className="gp-print-hide">
        <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value as TipoRelatorio)}>
          {RELATORIOS.map((r) => (
            <option key={r.tipo} value={r.tipo}>{r.rotulo}</option>
          ))}
        </FilterSelect>
      </div>

      {tipo === 'board' && <CarteiraDoBoard contas={contas} turma={turma} canVerDoc={canVerDoc} hotmartPorCard={hotmartPorCard} />}

      {tipo === 'pessoas' && (
        <div className="space-y-4">
          <SeletorFamilia familia={familia} onChange={setFamilia} />
          <HotmartPessoas repo={repo} familia={familia} />
        </div>
      )}

      {tipo === 'conciliacao' && (
        <div className="space-y-4">
          <SeletorFamilia familia={familia} onChange={setFamilia} />
          <HotmartConciliacao repo={repo} familia={familia} />
        </div>
      )}

      {tipo === 'identidade' && <HotmartIdentidade repo={repo} />}

      {tipo === 'acelera' && <AceleraParaHM repo={repo} />}

      {tipo === 'prorata' && <ProrataHM repo={repo} />}
    </div>
  );
}
