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
// BUSCA (2026-08-25): sem colunas, o mosaico perdeu o último lugar onde se
// achava uma pessoa específica sem varrer a tela com o olho — 308 cards em
// grid não têm índice. A barra de busca filtra por NOME e VENDEDOR (só o que
// o card já mostra; e-mail/documento ficam fora por LGPD, ver domain/busca.ts)
// e é o filtro mais RASO da pilha: aplica depois de produto e canal, para que
// limpar a busca devolva exatamente o recorte anterior, nunca a carteira toda.
//
// O dicionário de cores continua sendo LegendaCores.tsx, renderizado pelo pai
// (FinanceiroClient) acima do mosaico — sem cabeçalho de coluna, é ele que
// ensina o que cada cor quer dizer. Aqui entra só o CONTADOR por cor (quantos
// cards, quanto saldo), que era o que o cabeçalho da coluna dava.
import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react';
import { EmptyState, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
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

export function BoardView({ cards, hojeISO, onOpen, busca, onBusca, totalSemBusca }: {
  /** Lista plana já filtrada por produto/ação — única fonte do mosaico.
   *  (O agrupamento por coluna deixou de existir; ver cabeçalho do arquivo.) */
  cards: CardComEfeito[];
  /** Data de referência (ISO) para faixaPrazoDe — injetada pelo chamador,
   *  mesma disciplina de proximaAcao()/preverRecebimento() em ../domain/cobranca.ts. */
  hojeISO: string;
  onOpen: (id: string) => void;
  /** Texto da busca. Estado CONTROLADO pelo pai: o rodapé de totais tem que
   *  somar exatamente os cards que estão na tela — se a busca morasse aqui,
   *  o board mostraria 3 cards e o rodapé continuaria somando os 264 do
   *  recorte, que é a classe de bug que `RodapeTotais` existe para evitar
   *  ("os totais são do recorte, não da carteira"). */
  busca: string;
  onBusca: (v: string) => void;
  /** Quantos cards havia ANTES da busca — o número que o botão de limpar
   *  promete devolver. Vem do pai porque `cards` aqui já chega filtrado. */
  totalSemBusca: number;
}) {
  const [eixo, setEixo] = useState<Eixo>('funil');
  // useDeferredValue em vez de debounce por setTimeout: o input responde a
  // CADA tecla (nunca engasga, nunca "come" letra), e o React reprioriza a
  // refiltragem dos 308 cards para depois de pintar o caractere. Debounce
  // manual atrasaria o texto tambem — aqui só a lista chega com atraso.
  const buscaAplicada = useDeferredValue(busca);
  const filtrando = busca !== buscaAplicada;

  const inputRef = useRef<HTMLInputElement>(null);

  // "/" foca a busca e Esc limpa/desfoca — convenção de board denso (Linear,
  // GitHub). Só "/" é interceptado, e apenas fora de campo de texto: roubar a
  // tecla de quem está digitando no drawer da ficha seria pior que não ter
  // atalho. Esc é tratado no próprio input (não global) para não competir com
  // o Esc que fecha o FichaDrawer.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
      const alvo = e.target as HTMLElement | null;
      const tag = alvo?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || alvo?.isContentEditable) return;
      e.preventDefault();
      inputRef.current?.focus();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

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
      {/* Busca acima dos controles: é o filtro que muda O CONJUNTO, e os
          seletores abaixo só reordenam o que sobrou — a ordem visual espelha
          a ordem de aplicação. */}
      <div className="mb-3">
        <div className="relative max-w-[420px]">
        <SearchInput
          ref={inputRef}
          value={busca}
          onChange={(e) => onBusca(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key !== 'Escape') return;
            // Esc com texto limpa (fica no campo, pronto para novo termo);
            // Esc no campo vazio devolve o foco à página. Dois toques nunca
            // fecham nada por acidente.
            if (busca) {
              e.stopPropagation();
              onBusca('');
            } else {
              e.currentTarget.blur();
            }
          }}
          placeholder="Buscar por nome ou vendedor…"
          aria-label="Buscar card por nome do aluno ou vendedor. Atalho: barra para focar, Esc para limpar."
          aria-describedby="board-busca-resultado"
          className="pr-9"
        />
        {/* Dica do atalho quando o campo está vazio; vira botão de limpar
            quando tem texto — o mesmo canto nunca mostra os dois, e o alvo
            de toque (32px + padding do pai) não cai abaixo do mínimo. */}
        {busca ? (
          <button
            type="button"
            onClick={() => { onBusca(''); inputRef.current?.focus(); }}
            aria-label="Limpar busca"
            className="absolute right-1.5 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-[var(--r-sm)] text-[var(--fg-3)] transition-colors hover:bg-[var(--surface-2)] hover:text-[var(--fg)] focus-visible:ring-2"
          >
            <Icon name="x" size={14} />
          </button>
        ) : (
          <kbd
            aria-hidden
            className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-2)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-4)]"
          >
            /
          </kbd>
        )}
        </div>
        {/* role="status" (não aria-live cru num número): anuncia a FRASE
            inteira "12 cards encontrados para maria", nunca "12" solto, e sem
            roubar o foco de quem ainda está digitando. */}
        <p
          id="board-busca-resultado"
          role="status"
          aria-atomic="true"
          className="mt-1.5 min-h-[16px] text-[11px] text-[var(--fg-3)]"
        >
          {/* Zero resultados NÃO é anunciado aqui: o painel de vazio logo
              abaixo já diz "Nenhum card para X" com as sugestões e o botão de
              saída. Repetir "0 cards encontrados" nesta linha faria o leitor
              de tela ouvir a mesma notícia duas vezes, a segunda sem a saída. */}
          {buscaAplicada.trim() && cards.length > 0 ? (
            <>
              <strong className="tabular font-semibold text-[var(--fg-2)]">{cards.length}</strong>
              {cards.length === 1 ? ' card encontrado' : ' cards encontrados'} para
              {' '}<span className="font-semibold text-[var(--fg-2)]">&ldquo;{buscaAplicada.trim()}&rdquo;</span>
              {' · '}
              <button
                type="button"
                onClick={() => onBusca('')}
                className="font-semibold text-[var(--accent)] underline underline-offset-2 hover:opacity-80 focus-visible:ring-2 rounded-[var(--r-sm)]"
              >
                limpar busca
              </button>
            </>
          ) : null}
        </p>
      </div>

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
        // Dois vazios DIFERENTES: "a busca não achou" tem saída (limpar e ver
        // os N que estavam ali); "não há contas" não tem — mandar limpar uma
        // busca vazia seria um beco sem saída. Nunca "0 resultados" seco.
        buscaAplicada.trim() ? (
          <div
            role="status"
            aria-atomic="true"
            className="rounded-[var(--r-lg)] border border-dashed border-[var(--border)] p-8 text-center"
          >
            <Icon name="search" size={22} className="mx-auto text-[var(--fg-3)]" />
            <p className="mt-2 text-sm font-medium text-[var(--fg)]">
              Nenhum card para &ldquo;{buscaAplicada.trim()}&rdquo;
            </p>
            <p className="mt-1 text-xs text-[var(--fg-3)]">
              A busca cobre nome do aluno e vendedor. Tente só o primeiro nome, ou confira se o card
              está na outra aba de produto (HM / Aurum).
            </p>
            <button
              type="button"
              onClick={() => onBusca('')}
              className="mt-3 inline-flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] transition-colors hover:bg-[var(--surface-2)] focus-visible:ring-2"
            >
              <Icon name="x" size={13} /> Limpar busca e ver os {totalSemBusca} cards
            </button>
          </div>
        ) : (
          <EmptyState title="Nenhum card no board" hint="Sem contas para os filtros aplicados." icon="wallet" />
        )
      ) : (
        // Grid fluido: os cards se encaixam lado a lado e quebram sozinhos por
        // largura de viewport (auto-fill), sem coluna fixa nem scroll horizontal.
        // `auto-rows-min` mantém cada card na altura do próprio conteúdo — sem
        // esticar para casar com o vizinho mais alto da linha.
        <ul
          // aria-busy enquanto o useDeferredValue ainda não alcançou o texto:
          // a lista abaixo é do termo ANTERIOR por alguns ms. `opacity` é a
          // única propriedade animada (composta na GPU, sem reflow) — a altura
          // não muda, então não há CLS.
          aria-busy={filtrando}
          className={`grid auto-rows-min gap-2 [grid-template-columns:repeat(auto-fill,minmax(220px,1fr))] transition-opacity duration-150 ${filtrando ? 'opacity-60' : 'opacity-100'}`}
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
