'use client';

// Mosaico de cards — SEM colunas (redesign 2026-08-24, pedido do Marcio).
//
// O board era kanban: a POSIÇÃO do card (coluna) carregava a situação, e a cor
// era reforço. Isso custava duas leituras — achar a coluna, depois ler o card —
// e desperdiçava largura com colunas vazias colapsadas em faixa fina.
//
// Agora a situação é carregada 100% pela COR: os cards fluem lado a lado num
// grid único, misturando verdes, azuis, amarelos e vermelhos. A leitura vira
// densidade visual — "quanto amarelo tem na tela" responde antes de ler um
// card sequer. Ordem não é semântica: nenhuma posição significa nada.
//
// A cor NÃO é decidida aqui. Vem de domain/cor-status.ts (decisão do João,
// 2026-08-23, vinculante) projetada por ui/cor.ts — este componente só ordena
// e conta. Zero Record<> de cor nasce neste arquivo, mesma regra que ui/cor.ts
// impõe a CardBoard/FichaDrawer/Relatorios.
//
// O seletor deixou de AGRUPAR (não há mais grupos) e passou a ORDENAR: escolhe
// qual eixo desempata os cards dentro do mosaico. Os eixos continuam paralelos,
// documentados em ../domain/types.ts (FaixaFunil, do SQL) e ../domain/prazo.ts
// (FaixaPrazo) — trocar a ordem nunca esconde nem reagrupa card nenhum.
//
// O dicionário de cores continua sendo LegendaCores.tsx, renderizado pelo pai
// (FinanceiroClient) acima do mosaico — sem cabeçalho de coluna, é ele que
// ensina o que cada cor quer dizer. Aqui entra só o CONTADOR por cor (quantos
// cards, quanto saldo), que era o que o cabeçalho da coluna dava.
import { useMemo, useState } from 'react';
import { EmptyState } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { saldoEfetivo } from '../domain/financeiro';
import { faixaPrazoDe, FAIXAS_PRAZO_ORDEM } from '../domain/prazo';
import { ROTULO_COR, type CorStatus } from '../domain/cor-status';
import { VAR_COR } from './cor';
import { CardBoardView } from './CardBoard';
import { FAIXAS_FUNIL, type CardComEfeito } from '../application/carregar-board';
import type { FaixaFunil } from '../domain/types';

type Eixo = 'funil' | 'prazo' | 'valor';

/** Peso de cada faixa do funil na ordenação — mesma ordem canônica das antigas
 *  colunas (FAIXAS_FUNIL), preservada agora como desempate, não como grupo. */
const PESO_FUNIL: Record<FaixaFunil, number> = Object.fromEntries(
  FAIXAS_FUNIL.map(({ chave }, i) => [chave, i]),
) as Record<FaixaFunil, number>;

/** Peso de cada faixa de prazo — ordem canônica de FAIXAS_PRAZO_ORDEM
 *  (vencidas → vencem_7d → a_vencer → sem_data). `null` (conta morta ou
 *  quitada sem saldo) cai para o fim: não está em nenhuma fila de cobrança. */
const PESO_PRAZO = Object.fromEntries(
  FAIXAS_PRAZO_ORDEM.map((f, i) => [f, i]),
) as Record<string, number>;

/** Ordem do contador — a mesma de LegendaCores (CORES_BASE + neutro no fim),
 *  para legenda e contador nunca listarem as cores em ordens diferentes. */
const ORDEM_COR: CorStatus[] = ['verde', 'azul', 'amarelo', 'vermelho', 'neutro'];

export function BoardView({ cards, hojeISO, onOpen }: {
  /** Lista plana já filtrada por produto/ação — única fonte do mosaico.
   *  (O agrupamento por coluna deixou de existir; ver cabeçalho do arquivo.) */
  cards: CardComEfeito[];
  /** Data de referência (ISO) para faixaPrazoDe — injetada pelo chamador,
   *  mesma disciplina de proximaAcao()/preverRecebimento() em ../domain/cobranca.ts. */
  hojeISO: string;
  onOpen: (id: string) => void;
}) {
  const [eixo, setEixo] = useState<Eixo>('funil');

  // Ordena sobre uma CÓPIA: `cards` é prop do pai (FinanceiroClient) e sort()
  // muta o array no lugar — ordenar o original reordenaria a lista dele.
  const ordenados = useMemo(() => {
    const saldo = (c: CardComEfeito) => c.conta.saldo_a_pagar ?? 0;
    const lista = [...cards];

    if (eixo === 'valor') return lista.sort((a, b) => saldo(b) - saldo(a));

    if (eixo === 'prazo') {
      const peso = (c: CardComEfeito) => {
        const f = faixaPrazoDe(c.conta, hojeISO);
        return f == null ? FAIXAS_PRAZO_ORDEM.length : PESO_PRAZO[f];
      };
      return lista.sort((a, b) => peso(a) - peso(b) || saldo(b) - saldo(a));
    }

    return lista.sort(
      (a, b) => (PESO_FUNIL[a.faixaFunil] ?? 0) - (PESO_FUNIL[b.faixaFunil] ?? 0) || saldo(b) - saldo(a),
    );
  }, [cards, eixo, hojeISO]);

  // Contagem/soma por cor — o que o cabeçalho da coluna dava de graça. Só
  // aparece a cor presente NO RECORTE: aqui é resumo do que está na tela, o
  // oposto de LegendaCores (dicionário, mostra as 4 sempre). Mesma regra de
  // saldo do rodapé (saldoEfetivo), nunca soma resíduo de centavos.
  const contadores = useMemo(() => {
    const acc = new Map<CorStatus, { n: number; saldo: number }>();
    for (const c of cards) {
      const at = acc.get(c.cor) ?? { n: 0, saldo: 0 };
      at.n += 1;
      at.saldo += saldoEfetivo(c.conta);
      acc.set(c.cor, at);
    }
    return ORDEM_COR.filter((cor) => acc.has(cor)).map((cor) => ({ cor, ...acc.get(cor)! }));
  }, [cards]);

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <div className="flex items-center gap-1.5" role="group" aria-label="Ordenar o mosaico por">
          <span className="text-[11px] font-medium uppercase tracking-wide text-[var(--fg-4)]">Ordenar por</span>
          <SeletorEixo ativo={eixo === 'funil'} onClick={() => setEixo('funil')}>Estágio do funil</SeletorEixo>
          <SeletorEixo ativo={eixo === 'prazo'} onClick={() => setEixo('prazo')}>Prazo de pagamento</SeletorEixo>
          <SeletorEixo ativo={eixo === 'valor'} onClick={() => setEixo('valor')}>Valor</SeletorEixo>
        </div>

        <ul className="flex flex-wrap items-center gap-x-3 gap-y-1" aria-label="Cards por cor no recorte atual">
          {contadores.map(({ cor, n, saldo }) => (
            <li
              key={cor}
              className="flex items-center gap-1.5 text-[11px] text-[var(--fg-3)]"
              title={`${ROTULO_COR[cor]} — ${n} ${n === 1 ? 'card' : 'cards'}`}
            >
              <span
                className="h-2 w-2 shrink-0 rounded-[var(--r-pill)]"
                style={{ background: VAR_COR[cor] }}
                aria-hidden
              />
              <span className="tabular">
                {n}
                {saldo > 0 && ` · ${fmtBRL(saldo)}`}
              </span>
            </li>
          ))}
        </ul>
      </div>

      {!ordenados.length ? (
        <EmptyState title="Nenhum card no board" hint="Sem contas para os filtros aplicados." icon="wallet" />
      ) : (
        // Grid fluido: os cards se encaixam lado a lado e quebram sozinhos por
        // largura de viewport (auto-fill), sem coluna fixa nem scroll horizontal.
        // `auto-rows-min` mantém cada card na altura do próprio conteúdo — sem
        // esticar para casar com o vizinho mais alto da linha.
        <ul
          className="grid auto-rows-min gap-2 [grid-template-columns:repeat(auto-fill,minmax(220px,1fr))]"
          aria-label={`Mosaico do financeiro — ${ordenados.length} ${ordenados.length === 1 ? 'card' : 'cards'}`}
        >
          {ordenados.map((c) => (
            <li key={c.conta.contato_hm_id}>
              <CardBoardView card={c} onOpen={onOpen} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function SeletorEixo({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      onClick={onClick}
      className={`rounded-[var(--r-sm)] px-2 py-1 text-xs font-semibold transition-colors focus-visible:ring-2 ${
        ativo
          ? 'bg-[var(--accent-subtle)] text-[var(--accent)] border border-[var(--accent-border)]'
          : 'text-[var(--fg-3)] border border-transparent hover:bg-[var(--surface-2)]'
      }`}
    >
      {children}
    </button>
  );
}
