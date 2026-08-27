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
import { useEffect, useMemo, useRef, useState } from 'react';
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

export function BoardView({
  cards, cardsParaContador, hojeISO, onOpen, busca, onBusca, totalSemBusca, atalhoAtivo = true, corFiltro, onCorFiltro,
}: {
  /** Lista plana já filtrada por produto/ação/busca/COR — única fonte do
   *  mosaico. (O agrupamento por coluna deixou de existir; ver cabeçalho do
   *  arquivo.) */
  cards: CardComEfeito[];
  /** Mesmo recorte de `cards`, mas SEM o filtro de cor — alimenta os
   *  contadores por cor (N4). Precisa ser o conjunto pré-cor para as outras
   *  cores continuarem contáveis/clicáveis enquanto uma está filtrada; senão
   *  escolher "amarelo" faria os demais contadores desaparecerem (0 sempre)
   *  e o filtro nunca poderia ser trocado por outra cor num clique só. */
  cardsParaContador: CardComEfeito[];
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
  /** Liga o atalho "/". Falso enquanto a ficha (FichaDrawer) está aberta: o
   *  Drawer não tem focus trap, e "/" moveria o foco para um campo ATRÁS do
   *  overlay — o usuário digitaria às cegas num input que não consegue ver. */
  atalhoAtivo?: boolean;
  /** Quantos cards havia ANTES da busca — o número que o botão de limpar
   *  promete devolver. Vem do pai porque `cards` aqui já chega filtrado. */
  totalSemBusca: number;
  /** Cor selecionada como filtro (N4, 2026-08-27) — null = nenhuma. Estado
   *  CONTROLADO pelo pai, mesma razão de `busca`: o rodapé precisa somar
   *  exatamente o que o mosaico mostra. */
  corFiltro: CorStatus | null;
  onCorFiltro: (c: CorStatus | null) => void;
}) {
  const [eixo, setEixo] = useState<Eixo>('funil');

  // SEM debounce e SEM useDeferredValue, de propósito. O filtro é um
  // `Array.filter` sobre ~308 objetos já em memória (nenhuma query por tecla,
  // ver FinanceiroClient) — trabalho de fração de milissegundo, abaixo do
  // limiar em que adiar melhora alguma coisa.
  //
  // 🔑 Uma tentativa anterior deferia só o TERMO exibido, enquanto a lista
  // continuava sendo filtrada pelo texto atual. O resultado era o contrário do
  // pretendido: a contagem do termo novo aparecia colada ao termo antigo
  // ("3 cards encontrados para «mar»" com 3 sendo a contagem de «mari»), e o
  // live region anunciava esse par inconsistente. Filtrar direto mantém termo
  // e contagem sempre do mesmo instante — que é o que o leitor de tela lê.
  const buscaAplicada = busca;

  const inputRef = useRef<HTMLInputElement>(null);

  // "/" foca a busca e Esc limpa/desfoca — convenção de board denso (Linear,
  // GitHub). Só "/" é interceptado, e apenas fora de campo de texto: roubar a
  // tecla de quem está digitando no drawer da ficha seria pior que não ter
  // atalho. Esc é tratado no próprio input (não global) para não competir com
  // o Esc que fecha o FichaDrawer.
  useEffect(() => {
    if (!atalhoAtivo) return;
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
  }, [atalhoAtivo]);

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

  // Contagem/soma por cor — o que o cabeçalho da coluna dava de graça. Sobre
  // `cardsParaContador` (recorte SEM o filtro de cor, ver prop) — não sobre
  // `cards` — para as cores não filtradas continuarem visíveis e clicáveis
  // enquanto uma está ativa (N4). Só aparece a cor presente NO RECORTE: aqui
  // é resumo do que está na tela, o oposto de LegendaCores (dicionário,
  // mostra as 4 sempre). Mesma regra de saldo do rodapé (saldoEfetivo), nunca
  // soma resíduo de centavos.
  const contadores = useMemo(() => {
    const acc = new Map<CorStatus, { n: number; saldo: number }>();
    for (const c of cardsParaContador) {
      const at = acc.get(c.cor) ?? { n: 0, saldo: 0 };
      at.n += 1;
      at.saldo += saldoEfetivo(c.conta);
      acc.set(c.cor, at);
    }
    return ORDEM_COR.filter((cor) => acc.has(cor)).map((cor) => ({ cor, ...acc.get(cor)! }));
  }, [cardsParaContador]);

  return (
    <div>
      {/* Sticky (N5, 2026-08-27): com 264 cards, rolar perdia busca/ordenação/
          recorte. `position: sticky` no TOPO — empurra o conteúdo, nunca
          cobre um card (o rodapé de totais foi despromovido de sticky em
          19/08 por reclamação do Marcio: "flutuando por cima cortava
          cards" — sticky no topo é o oposto disso).

          ⚠️ `top: 0`, NÃO `var(--header-height)`. O container de scroll é o
          `<main overflow-auto>` de shared/ui/shell/AppShell.tsx:63, e o
          header do app fica FORA dele (irmão, não ancestral) — descontar a
          altura do header prendia a barra 60px abaixo do topo da área de
          scroll, e os cards rolavam VISÍVEIS nessa faixa, exatamente o que
          o fundo sólido abaixo existe para impedir. Achado do
          fable-orchestrator (2026-08-27): a validação anterior foi num
          preview isolado, sem o AppShell, por isso passou.

          Fundo sólido (--surface-0, o mesmo do <main>) para o mosaico não
          aparecer por trás enquanto rola; `pt-1` casa com o padding do
          container. z-index baixo (1) — abaixo de qualquer overlay
          (FichaDrawer etc., que ficam em 900+). */}
      <div className="sticky top-0 z-[1] -mx-1 bg-[var(--surface-0)] px-1 pb-2 pt-1">
      {/* Busca acima dos controles: é o filtro que muda O CONJUNTO, e os
          seletores abaixo só reordenam o que sobrou — a ordem visual espelha
          a ordem de aplicação. */}
      <div className="mb-3">
        <div className="max-w-[420px]">
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
          onLimpar={() => onBusca('')}
          dica="/"
        />
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

        {/* N4 (2026-08-27): contador por cor virou filtro clicável — já
            calculava {cor, n, saldo} e renderizava como texto morto; o
            mosaico não tinha filtro por cor, e a cor é justamente o que ele
            passou a carregar (faixa lateral, ver globals.css). Clicar de
            novo na cor já ativa desliga o filtro (toggle). `role="group"` +
            `aria-pressed` por botão: mesmo padrão de SeletorEixo acima. */}
        <div className="flex flex-wrap items-center gap-x-1.5 gap-y-1" role="group" aria-label="Filtrar o mosaico por cor">
          {contadores.map(({ cor, n, saldo }) => {
            const ativo = corFiltro === cor;
            return (
              <button
                key={cor}
                type="button"
                aria-pressed={ativo}
                onClick={() => onCorFiltro(ativo ? null : cor)}
                title={`${ROTULO_COR[cor]} — ${n} ${n === 1 ? 'card' : 'cards'}${ativo ? ' (clique para remover o filtro)' : ' (clique para filtrar)'}`}
                className={`flex items-center gap-1.5 rounded-[var(--r-sm)] px-1.5 py-0.5 text-[11px] transition-colors focus-visible:ring-2 ${
                  ativo
                    ? 'bg-[var(--surface-3)] text-[var(--fg-2)] font-semibold border border-[var(--border-strong)]'
                    : 'text-[var(--fg-3)] border border-transparent hover:bg-[var(--surface-2)]'
                }`}
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
              </button>
            );
          })}
        </div>
      </div>
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
          // Sem aria-busy nem esmaecimento: a lista é sempre do termo atual
          // (ver nota sobre o deferral removido acima). Marcar como "ocupada"
          // uma lista já correta faria o leitor de tela esperar por uma
          // atualização que nunca vem.
          className="grid auto-rows-min gap-2 [grid-template-columns:repeat(auto-fill,minmax(220px,1fr))]"
          aria-label={`Mosaico do financeiro — ${ordenados.length} ${ordenados.length === 1 ? 'card' : 'cards'}`}
        >
          {ordenados.map((c) => (
            <li key={c.conta.contato_hm_id}>
              <CardBoardView card={c} onOpen={onOpen} hojeISO={hojeISO} />
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
