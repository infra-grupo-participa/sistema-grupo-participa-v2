'use client';

// Timeline de canais/ações no topo do board — botões que filtram os cards.
// acao_nome + acao_data (nome/data da janela de campanha em que o SINAL foi
// pago). Após o fix do backend em 19/08 (comparação de timestamptz que
// comia o 1º dia de toda janela), 89 dos 305 cards têm acao_nome NULL
// (82 HM + 7 Aurum, não mais 133): viram o chip "Sem ação identificada" —
// nunca somem da lista, só ficam agrupados à parte.
import { Icon } from '@/shared/ui/icons';
import { fmtData } from '@/shared/ui/format';
import type { CardComEfeito } from '../application/carregar-board';

export const SEM_ACAO = '__sem_acao__';

export interface AcaoResumo {
  chave: string;
  nome: string;
  data: string | null;
  total: number;
}

/** Agrupa os cards por ação, ordenado por data CRESCENTE (mais antiga primeiro
 *  — pedido explícito: "ordem cronológica entre eles"). Sem ação (null) vai
 *  por último, sempre visível com a contagem — nunca escondido em silêncio.
 *  Cards já vêm filtrados por produto (HM/Aurum) por quem chama — a lista
 *  resultante é só dos canais daquele produto: Aurum tem 1 canal (ETHB SP),
 *  HM tem 4, e essa função não sabe nem precisa saber a diferença. */
export function agruparPorAcao(cards: CardComEfeito[]): AcaoResumo[] {
  const mapa = new Map<string, AcaoResumo>();
  for (const c of cards) {
    const chave = c.acaoNome ?? SEM_ACAO;
    const atual = mapa.get(chave) ?? { chave, nome: c.acaoNome ?? 'Sem ação identificada', data: c.acaoData, total: 0 };
    atual.total += 1;
    mapa.set(chave, atual);
  }
  const lista = [...mapa.values()];
  const comData = lista.filter((a) => a.chave !== SEM_ACAO).sort((a, b) => String(a.data ?? '').localeCompare(String(b.data ?? '')));
  const semAcao = lista.find((a) => a.chave === SEM_ACAO);
  return semAcao ? [...comData, semAcao] : comData;
}

export function TimelineAcoes({ acoes, ativa, onSelecionar }: {
  acoes: AcaoResumo[];
  ativa: string | null;
  onSelecionar: (chave: string | null) => void;
}) {
  if (!acoes.length) return null;
  return (
    <div className="flex items-center gap-2 overflow-x-auto pb-1" role="tablist" aria-label="Filtrar por ação/canal">
      <button
        type="button"
        role="tab"
        aria-selected={ativa === null}
        onClick={() => onSelecionar(null)}
        className={`shrink-0 rounded-[var(--r-pill)] border px-3 py-1.5 text-xs font-medium transition-colors ${ativa === null ? 'border-[var(--border-accent)] bg-[var(--accent-subtle)] text-[var(--accent)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:border-[var(--border-strong)]'}`}
      >
        Todas
      </button>
      {acoes.map((a) => {
        const semAcao = a.chave === SEM_ACAO;
        const active = ativa === a.chave;
        return (
          <button
            key={a.chave}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onSelecionar(a.chave)}
            title={a.data ? fmtData(a.data) : undefined}
            className={`shrink-0 inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-3 py-1.5 text-xs font-medium whitespace-nowrap transition-colors ${
              active ? 'border-[var(--border-accent)] bg-[var(--accent-subtle)] text-[var(--accent)]' : semAcao ? 'border-[var(--border)] text-[var(--fg-3)] hover:border-[var(--border-strong)]' : 'border-[var(--border)] text-[var(--fg-2)] hover:border-[var(--border-strong)]'
            }`}
          >
            {semAcao && <Icon name="alert" size={12} />}
            {a.nome}
            {a.data && <span className="tabular text-[10px] opacity-70">{fmtData(a.data)}</span>}
            <span className="tabular rounded-[var(--r-sm)] bg-[var(--surface-3)] px-1 text-[10px]">{a.total}</span>
          </button>
        );
      })}
    </div>
  );
}
