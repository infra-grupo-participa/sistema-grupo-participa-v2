'use client';

// Grade de indicadores por pessoa (fechamento por vendedor, ranking da equipe) SEM tabela com rolagem
// horizontal: em tela grande vira linhas com 1 coluna de nome + 6 números (cabeçalho com o (i));
// em tela estreita cada pessoa é um bloco com os números em 3 colunas, rótulo em cima de cada um.
import { Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { MetricaKey } from '../../domain/types';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';

export interface ColunaGrade {
  k: string;
  rotulo: string;
  metrica?: MetricaKey;
  info?: TextoIndicador;
  /** Cabeçalho clicável para ordenar. */
  onOrdenar?: () => void;
  ativa?: boolean;
  dir?: 'asc' | 'desc';
}

export interface CelulaGrade {
  valor: React.ReactNode;
  /** Viola meta (ex.: atrasadas > 0): vermelho. */
  alerta?: boolean;
  /** Linha pequena abaixo do número. */
  sub?: React.ReactNode;
}

export interface LinhaGradeDados {
  id: string;
  cabeca: React.ReactNode;
  celulas: CelulaGrade[];
  /** Linha de total: fundo e peso diferentes. */
  total?: boolean;
}

// Nome + 6 números. As duas telas usam 6 colunas; mudar aqui se uma delas mudar.
const COLS_LG = 'lg:grid-cols-[minmax(160px,1.6fr)_repeat(6,minmax(0,1fr))]';

export function GradeIndicadores({ primeira, colunas, linhas, rotulo }: {
  primeira: string; colunas: ColunaGrade[]; linhas: LinhaGradeDados[]; rotulo: string;
}) {
  return (
    <Card className="min-w-0">
      <div className={`hidden lg:grid ${COLS_LG} gap-x-3 border-b border-[var(--border)] bg-[var(--surface-3)] px-4 py-2 rounded-t-[var(--r-lg)]`}>
        <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{primeira}</span>
        {colunas.map((c) => <Cabecalho key={c.k} c={c} />)}
      </div>
      <ul aria-label={rotulo} className="divide-y divide-[var(--border-faint)]">
        {linhas.map((l) => (
          <li key={l.id} className={`px-4 py-3 lg:grid ${COLS_LG} lg:items-center gap-x-3 ${l.total ? 'bg-[var(--surface-3)] last:rounded-b-[var(--r-lg)]' : ''}`}>
            <div className={`min-w-0 ${l.total ? 'text-sm font-semibold text-[var(--fg)]' : ''}`}>{l.cabeca}</div>
            <dl className="mt-2 grid grid-cols-3 gap-x-3 gap-y-2 sm:grid-cols-6 lg:mt-0 lg:contents">
              {l.celulas.map((cel, i) => (
                <div key={colunas[i]?.k ?? i} className="min-w-0 lg:text-right">
                  <dt className="text-[11px] text-[var(--fg-3)] lg:sr-only">{colunas[i]?.rotulo}</dt>
                  <dd className={`text-sm tabular ${cel.alerta ? 'font-semibold text-[var(--red)]' : l.total ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg)]'}`}>
                    {cel.valor}
                    {cel.alerta && <span className="sr-only"> (fora da meta)</span>}
                    {cel.sub && <span className="block text-[11px] font-normal text-[var(--fg-3)]">{cel.sub}</span>}
                  </dd>
                </div>
              ))}
            </dl>
          </li>
        ))}
      </ul>
    </Card>
  );
}

function Cabecalho({ c }: { c: ColunaGrade }) {
  const rotulo = <span className="truncate text-[11px] font-semibold uppercase tracking-wide">{c.rotulo}</span>;
  return (
    <span className="flex min-w-0 items-center justify-end gap-0.5 text-[var(--fg-3)]">
      {c.onOrdenar ? (
        <button
          type="button"
          onClick={c.onOrdenar}
          aria-label={`Ordenar por ${c.rotulo}`}
          aria-pressed={!!c.ativa}
          className={`inline-flex min-w-0 items-center gap-1 rounded-[var(--r-sm)] px-1 hover:text-[var(--fg)] ${c.ativa ? 'text-[var(--fg)]' : ''}`}
        >
          {rotulo}
          {c.ativa && <Icon name={c.dir === 'asc' ? 'arrow-up' : 'arrow-down'} size={12} className="shrink-0 text-[var(--accent)]" />}
        </button>
      ) : rotulo}
      {(c.metrica || c.info) && <InfoIndicador metrica={c.metrica} texto={c.info} />}
    </span>
  );
}
