'use client';

// Rosca clicável (até 6 valores) e barras clicáveis (acima disso) do Perfil dos leads. Componente novo de
// propósito: RoscaCategorias e filtro-cruzado.ts são do ATM e da Clínica (no ar) e não mudam.
// Rótulo = string exata da fonte; "Não informado" sempre cinza e no fim.
import type { Contagem } from '../../domain/perfil';
import { SEM_VALOR } from '../../domain/perfil';
import { inteiro } from '../pecas';

const CORES = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--green)', 'var(--yellow)', 'var(--red)'];
const cor = (c: Contagem, i: number) => (c.valor === SEM_VALOR ? 'var(--fg-3)' : CORES[i % CORES.length]);
const fatia = (q: number, total: number) => (total > 0 ? `${((q / total) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%` : '—');

export const LIMITE_ROSCA = 6;

export function RoscaClicavel({ titulo, nota, itens, selecionado, onSelect }: {
  titulo: string; nota?: string; itens: Contagem[]; selecionado: string | null; onSelect: (valor: string) => void;
}) {
  const total = itens.reduce((s, c) => s + c.quantidade, 0);
  const R = 42; const C = 2 * Math.PI * R;
  let acumulado = 0;
  return (
    <figure className="min-w-0">
      <figcaption className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]" title={nota}>{titulo}{nota ? ' *' : ''}</figcaption>
      <div className="flex items-center gap-4">
        <svg viewBox="0 0 100 100" className="h-24 w-24 shrink-0" role="img" aria-label={`${titulo}: ${itens.map((c) => `${c.rotulo} ${inteiro(c.quantidade)}`).join(', ')}`}>
          <circle cx="50" cy="50" r={R} fill="none" stroke="var(--surface-4)" strokeWidth="14" />
          {total > 0 && itens.map((c, i) => {
            const len = (c.quantidade / total) * C;
            const off = -acumulado; acumulado += len;
            const apagado = selecionado !== null && selecionado !== c.valor;
            return <circle key={c.valor} cx="50" cy="50" r={R} fill="none" stroke={cor(c, i)} strokeWidth={selecionado === c.valor ? 18 : 14}
              strokeDasharray={`${len} ${C - len}`} strokeDashoffset={off} transform="rotate(-90 50 50)"
              opacity={apagado ? 0.3 : 1} className="atm-historico-interativo cursor-pointer" onClick={() => onSelect(c.valor)}>
              <title>{`${c.rotulo}: ${inteiro(c.quantidade)} (${fatia(c.quantidade, total)})`}</title>
            </circle>;
          })}
        </svg>
        <ul className="min-w-0 flex-1 space-y-1">
          {itens.map((c, i) => (
            <li key={c.valor}>
              <button type="button" aria-pressed={selecionado === c.valor} onClick={() => onSelect(c.valor)}
                className={'flex w-full min-w-0 items-center gap-2 rounded-[var(--r-sm)] px-1 py-0.5 text-left text-xs atm-historico-interativo ' + (selecionado !== null && selecionado !== c.valor ? 'opacity-50' : '')}>
                <span aria-hidden="true" className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: cor(c, i) }} />
                <span className="min-w-0 flex-1 break-words text-[var(--fg-2)]">{c.rotulo}</span>
                <span className="tabular text-[var(--fg)]">{inteiro(c.quantidade)}</span>
                <span className="w-12 text-right tabular text-[var(--fg-3)]">{fatia(c.quantidade, total)}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </figure>
  );
}

/** Barras horizontais clicáveis (dimensão com mais de 6 valores). Rótulo inteiro, quebra linha em vez de cortar. */
export function BarrasClicaveis({ titulo, nota, itens, selecionado, onSelect, maximoLinhas = 12 }: {
  titulo: string; nota?: string; itens: Contagem[]; selecionado: string | null; onSelect: (valor: string) => void; maximoLinhas?: number;
}) {
  const max = Math.max(1, ...itens.map((c) => c.quantidade));
  const total = itens.reduce((s, c) => s + c.quantidade, 0);
  const visiveis = itens.slice(0, maximoLinhas);
  const resto = itens.length - visiveis.length;
  return (
    <figure className="min-w-0">
      <figcaption className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]" title={nota}>{titulo}{nota ? ' *' : ''}</figcaption>
      <ul className="space-y-1.5">
        {visiveis.map((c) => (
          <li key={c.valor}>
            <button type="button" aria-pressed={selecionado === c.valor} onClick={() => onSelect(c.valor)} title={`${c.rotulo}: ${inteiro(c.quantidade)} (${fatia(c.quantidade, total)})`}
              className={'block w-full min-w-0 rounded-[var(--r-sm)] text-left atm-historico-interativo ' + (selecionado !== null && selecionado !== c.valor ? 'opacity-50' : '')}>
              <span className="flex items-baseline justify-between gap-2 text-xs">
                <span className="min-w-0 break-words text-[var(--fg-2)]">{c.rotulo}</span>
                <span className="shrink-0 tabular text-[var(--fg)]">{inteiro(c.quantidade)}</span>
              </span>
              <span className="mt-0.5 block h-1.5 overflow-hidden rounded-full bg-[var(--surface-4)]">
                <span className="atm-historico-barra block h-full rounded-full" style={{ width: `${(c.quantidade / max) * 100}%`, background: c.valor === SEM_VALOR ? 'var(--fg-3)' : selecionado === c.valor ? 'var(--accent)' : 'var(--cyan)' }} />
              </span>
            </button>
          </li>
        ))}
      </ul>
      {resto > 0 && <p className="mt-1 text-[11px] text-[var(--fg-3)]">Mais {resto} valor(es) com menos cadastros.</p>}
    </figure>
  );
}
