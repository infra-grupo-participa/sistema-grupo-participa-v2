'use client';

// Linha do tempo vertical — só apresentação (sem repositório, sem query). Quem usa carrega os dados e mapeia
// para ItemLinhaDoTempo. Nasceu da Trajetória do financeiro e é reusada pela Trajetória do aluno.
import { useState, type ReactNode } from 'react';
import { Badge } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import {
  chipsDeDimensao, filtrarPorDimensao,
  type DimensaoLinhaDoTempo, type ItemLinhaDoTempo, type TomMarcador,
} from './linha-do-tempo';

const MARCADOR: Record<TomMarcador, string> = {
  neutral: 'bg-[var(--fg-4)]',
  accent: 'bg-[var(--accent)]',
  success: 'bg-[var(--green)]',
  warning: 'bg-[var(--yellow)]',
  danger: 'bg-[var(--red)]',
};

export function LinhaDoTempo({ itens, dimensoes, resumo, vazio = 'Nenhum registro.', rotuloLista = 'Linha do tempo' }: {
  itens: ItemLinhaDoTempo[];
  /** Com dimensões, aparecem os chips-filtro ("Todas" + uma por dimensão, com contagem). Filtro feito aqui, no cliente. */
  dimensoes?: DimensaoLinhaDoTempo[];
  /** Slot do topo (números de resumo). */
  resumo?: ReactNode;
  vazio?: string;
  rotuloLista?: string;
}) {
  const [ativa, setAtiva] = useState<string | null>(null);
  const visiveis = filtrarPorDimensao(itens, ativa);
  const chips = dimensoes?.length ? chipsDeDimensao(itens, dimensoes) : null;

  return (
    <div className="space-y-3">
      {resumo}
      {chips && itens.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Filtrar por dimensão">
          {chips.map((c) => {
            const on = ativa === c.chave;
            return (
              <button
                key={c.chave ?? '__todas'}
                type="button"
                aria-pressed={on}
                disabled={c.chave != null && c.total === 0}
                onClick={() => setAtiva(c.chave)}
                className={`inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-3 py-1.5 text-xs font-medium whitespace-nowrap disabled:cursor-not-allowed disabled:opacity-50 ${on ? 'border-[var(--border-accent)] bg-[var(--accent-subtle)] text-[var(--accent)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:border-[var(--border-strong)]'}`}
              >
                {c.rotulo}
                <span className="tabular rounded-[var(--r-sm)] bg-[var(--surface-3)] px-1 text-[10px]">{c.total}</span>
              </button>
            );
          })}
        </div>
      )}
      {visiveis.length === 0 ? (
        <p className="text-xs text-[var(--fg-3)]">{vazio}</p>
      ) : (
        <ol aria-label={rotuloLista} className="relative space-y-2 border-l border-[var(--border)] pl-4">
          {visiveis.map((it) => (
            <li key={it.id} className="relative">
              <span aria-hidden className={`absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full ${MARCADOR[it.tom ?? 'accent']}`} />
              <div className="flex flex-wrap items-baseline gap-x-2">
                <span className="text-sm font-semibold text-[var(--fg)]">{it.titulo}</span>
                <span className="tabular text-[11px] text-[var(--fg-3)]">{fmtData(it.dia)}</span>
                {it.valor != null && <span className="tabular text-[11px] text-[var(--fg-2)]">{it.valor}</span>}
                {it.badges?.map((b) => <Badge key={b.rotulo} tone={b.tom ?? 'neutral'}>{b.rotulo}</Badge>)}
              </div>
              {/* Texto ganha o estilo padrão; nó (ex.: lista de passos do financeiro) entra como veio. */}
              {typeof it.detalhe === 'string' ? <div className="text-[11px] text-[var(--fg-2)]">{it.detalhe}</div> : it.detalhe}
              {it.nota && <div className="text-[10px] text-[var(--fg-4)]" title={it.nota}>regra: {it.nota}</div>}
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

/** Quadro de número do resumo (rótulo pequeno em maiúsculas + valor). Mesmo visual da Trajetória do financeiro. */
export function NumeroResumo({ rotulo, valor, dica }: { rotulo: string; valor: string; dica?: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2" title={dica}>
      <div className="text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular text-sm font-bold text-[var(--fg)]">{valor}</div>
    </div>
  );
}
