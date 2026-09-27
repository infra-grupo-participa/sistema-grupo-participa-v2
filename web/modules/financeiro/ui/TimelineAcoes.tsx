'use client';

// Timeline de canais/ações no topo do board — botões que filtram os cards.
// Desde 27/09 (20260928n) TODO card tem ação: a janela do evento, o link de venda (sck) ou a data da 1ª compra dizem de
// onde a pessoa veio (fin.vw_acao_card). Os grupos que não são evento — venda direta do comercial, base antiga, base
// fora de evento, sem pagamento — vão para o fim, sem data. "Sem ação identificada" só aparece se a função antiga voltar.
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
/** Grupos que não são um evento datado (fin.vw_acao_card): ficam no fim, sem data. */
const FORA_DE_EVENTO = /^(Comercial|Base|Sem pagamento)/;

export function agruparPorAcao(cards: CardComEfeito[]): AcaoResumo[] {
  const mapa = new Map<string, AcaoResumo>();
  for (const c of cards) {
    const chave = c.acaoNome ?? SEM_ACAO;
    const fora = !c.acaoNome || FORA_DE_EVENTO.test(c.acaoNome);
    const atual = mapa.get(chave) ?? { chave, nome: c.acaoNome ?? 'Sem ação identificada', data: fora ? null : c.acaoData, total: 0 };
    atual.total += 1;
    mapa.set(chave, atual);
  }
  const lista = [...mapa.values()];
  const eventos = lista.filter((a) => a.data != null).sort((a, b) => String(a.data).localeCompare(String(b.data)));
  const fora = lista.filter((a) => a.data == null && a.chave !== SEM_ACAO).sort((a, b) => b.total - a.total);
  const semAcao = lista.find((a) => a.chave === SEM_ACAO);
  return [...eventos, ...fora, ...(semAcao ? [semAcao] : [])];
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
