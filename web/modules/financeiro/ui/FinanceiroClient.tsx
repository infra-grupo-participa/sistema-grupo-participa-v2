'use client';

import { useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { Loading } from '@/shared/ui/components';
import type { ContaReceber, Oferta, ReguaPasso, TurmaFin } from '../domain/types';
// Mesma função pura de application/carregar-board.ts — reusada aqui para
// recalcular sobre o recorte filtrado pela timeline de ações (sem query nova).
import { calcularTotais as recalcularTotais } from '../domain/totais';
import { casaBusca } from '../domain/busca';
import { SupabaseFinanceiroRepository } from '../infrastructure/supabase-financeiro.repository';
import { carregarBoard, type BoardCarregado, type CardComEfeito } from '../application/carregar-board';
import { carregarFaturamento, type FaturamentoCarregado } from '../application/carregar-faturamento';
import { listarOfertas } from '../application/gerenciar-ofertas';
import { agruparPorAcao, SEM_ACAO, TimelineAcoes } from './TimelineAcoes';
import { ProdutoTabs, type ProdutoChave } from './ProdutoTabs';
import { LegendaCores } from './LegendaCores';
import { BoardView } from './BoardView';
import { BarraRecorte } from './BarraRecorte';
import type { RecorteAtivo } from '../domain/recorte';
import { RodapeTotais } from './RodapeTotais';
import { ROTULO_COR, type CorStatus } from '../domain/cor-status';
import { FichaDrawer } from './FichaDrawer';
import { Faturamento } from './Faturamento';
import { Relatorios } from './Relatorios';
import { Ofertas } from './Ofertas';

type Tab = 'board' | 'faturamento' | 'relatorios' | 'ofertas';

const repo = new SupabaseFinanceiroRepository();

export function FinanceiroClient({ canEdit, canVerDoc }: { canEdit: boolean; canVerDoc: boolean }) {
  const [tab, setTab] = useState<Tab>('board');
  const [board, setBoard] = useState<BoardCarregado | null>(null);
  const [erroBoard, setErroBoard] = useState<string | null>(null);
  // Guardada aqui (e não descartada após montar o board) para alimentar
  // proximaAcao() na ficha — sem query nova por abertura de drawer (F3 do plano).
  const [regua, setRegua] = useState<ReguaPasso[]>([]);
  const [fat, setFat] = useState<FaturamentoCarregado | null>(null);
  const [erroFat, setErroFat] = useState<string | null>(null);
  const [turmas, setTurmas] = useState<TurmaFin[]>([]);
  const [ofertas, setOfertas] = useState<Oferta[]>([]);
  const [erroOfertas, setErroOfertas] = useState<string | null>(null);
  const [turma] = useState<string | null>(null); // sem filtro de turma no board novo — todas reunidas, igual ao legado.
  // Metas por turma (fn_fin_metas) não têm tela própria nesta entrega — o
  // board novo não filtra por turma (todas reunidas), e a UI de metas/régua
  // do legado (ConfiguracoesFinanceiro) foi apagada com o resto da UI antiga.
  // Reintroduzir exige decisão de produto: onde a régua/meta mora na navegação
  // nova (board · faturamento · relatórios · ofertas não têm aba óbvia para
  // isso) — reportado como divergência, não decidido aqui.
  // Aba de produto — nível acima da timeline de canais (pedido do Marcio: HM
  // e Aurum nunca misturados). Trocar de aba reseta o canal ativo: um canal
  // do HM não faz sentido selecionado depois de trocar para Aurum.
  const [produtoAtivo, setProdutoAtivo] = useState<ProdutoChave>('HM');
  const [acaoAtiva, setAcaoAtiva] = useState<string | null>(null);
  // Busca mora AQUI, não no BoardView, porque o rodapé de totais precisa somar
  // exatamente o conjunto que o mosaico mostra (ver comentário da prop `busca`
  // em BoardView.tsx). Trocar de produto ou de canal limpa a busca: um termo
  // que achava 3 cards no HM quase sempre acha 0 no Aurum, e um mosaico vazio
  // logo após clicar numa aba parece aba quebrada, não busca sobrando.
  const [busca, setBusca] = useState('');
  // Filtro por cor (N4, 2026-08-27) — camada mais rasa do funil, depois da
  // busca. Mesmo motivo de `busca` morar aqui (não no BoardView): o rodapé
  // de totais precisa somar exatamente o que o mosaico mostra.
  const [corFiltro, setCorFiltro] = useState<CorStatus | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  const selecionarProduto = (produto: ProdutoChave) => {
    setProdutoAtivo(produto);
    setAcaoAtiva(null);
    setBusca('');
    setCorFiltro(null);
  };

  const selecionarAcao = (acao: string | null) => {
    setAcaoAtiva(acao);
    setBusca('');
    setCorFiltro(null);
  };

  const hojeISO = new Date().toISOString().slice(0, 10);

  /** Busca board+régua (sem tocar estado) — usado pelo mount e pelo retry/callback. */
  const buscarBoard = () => repo.loadRegua().then((rg) => carregarBoard(repo, rg, hojeISO, turma, null).then((b) => ({ b, rg })));

  // Recarrega o board a partir de um evento do usuário (retry do erro,
  // onAcordoSalvo do drawer) — componente já montado, sem guard de unmount.
  const carregarBoardAgora = () =>
    buscarBoard()
      .then(({ b, rg }) => { setBoard(b); setRegua(rg); setErroBoard(null); })
      .catch(() => setErroBoard('Não foi possível carregar o board financeiro. Verifique sua conexão e tente novamente.'));

  useEffect(() => {
    let vivo = true;
    (async () => {
      try {
        const { b, rg } = await buscarBoard();
        if (vivo) { setBoard(b); setRegua(rg); setErroBoard(null); }
      } catch {
        if (vivo) setErroBoard('Não foi possível carregar o board financeiro. Verifique sua conexão e tente novamente.');
      }
    })();
    (async () => {
      const t = await repo.loadTurmas().catch(() => []);
      if (vivo) setTurmas(t);
    })();

    // Deep link (N3, 2026-08-27): só produto e canal — DECISÃO DO MARCIO,
    // a busca fica FORA da URL (termo é quase sempre nome de aluno; URL entra
    // em histórico de navegador e log de proxy, superfície onde esse dado
    // hoje não chega). Formato: "#board?produto=HM&canal=<...>". O `?` mora
    // DENTRO do hash (não é querystring de verdade), então o parse é manual
    // — `URLSearchParams` aceita a parte depois do `?` de boa.
    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      const [base, query] = h.split('?');
      if (base === 'faturamento') setTab('faturamento');
      else if (base === 'relatorios') setTab('relatorios');
      else if (base === 'ofertas') setTab('ofertas');
      else setTab('board');

      if (base === 'board' && query) {
        const params = new URLSearchParams(query);
        const produto = params.get('produto');
        if (produto === 'HM' || produto === 'AURUM') setProdutoAtivo(produto);
        // Guardado cru; a VALIDAÇÃO contra as ações reais acontece no render
        // (`acaoEfetiva`), porque a lista de ações só existe depois que os
        // cards chegam. Ver nota em `acaoEfetiva`.
        setAcaoAtiva(params.get('canal') || null);
      }
    };
    applyHash();
    window.addEventListener('hashchange', applyHash);
    window.addEventListener('popstate', applyHash);
    return () => {
      vivo = false;
      window.removeEventListener('hashchange', applyHash);
      window.removeEventListener('popstate', applyHash);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (tab !== 'faturamento' || fat) return;
    carregarFaturamento(repo, turma, hojeISO)
      .then((f) => { setFat(f); setErroFat(null); })
      .catch(() => setErroFat('Não foi possível carregar o faturamento diário.'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab]);

  useEffect(() => {
    if (tab !== 'ofertas' || ofertas.length) return;
    listarOfertas(repo)
      .then((o) => { setOfertas(o); setErroOfertas(null); })
      .catch(() => setErroOfertas('Não foi possível carregar as ofertas.'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab]);

  // Contagem por produto sobre o board INTEIRO (nunca sobre o recorte de
  // canal) — é o número que a aba mostra, precisa ser estável ao trocar de
  // canal. Aba vazia não pode ficar muda: HM 264 · Aurum 41 aparecem sempre,
  // mesmo que um produto zere após algum filtro futuro ([].every() é true —
  // commit 0814910 — contagem explícita evita a mesma armadilha aqui).
  const contagensProduto = useMemo(() => {
    const base: Record<ProdutoChave, number> = { HM: 0, AURUM: 0 };
    if (!board) return base;
    for (const c of board.cards) base[c.origem] += 1;
    return base;
  }, [board]);

  // Cards do produto ativo — HM e Aurum nunca se misturam a partir daqui.
  const cardsDoProduto: CardComEfeito[] = useMemo(() => {
    if (!board) return [];
    return board.cards.filter((c) => c.origem === produtoAtivo);
  }, [board, produtoAtivo]);

  const acoes = useMemo(() => agruparPorAcao(cardsDoProduto), [cardsDoProduto]);

  // Canal EFETIVO = o que o deep link pediu, mas só se existir de verdade
  // neste produto. Derivado no render (não em efeito): a lista de ações vem
  // dos cards, que chegam depois do parse do hash, e um `setState` em efeito
  // para isso é exatamente o que a regra react-hooks/set-state-in-effect
  // barra — além de causar um frame com filtro inválido aplicado.
  //
  // Canal inexistente é DESCARTADO: melhor abrir a carteira inteira do
  // produto — estado padrão e legível — do que um board vazio sem filtro
  // visível para remover (`rotuloFiltroAtivo` voltaria null, sem chip na
  // BarraRecorte e sem menção no rodapé). Achado do fable-orchestrator,
  // 2026-08-27. Enquanto os cards não chegam, `acoes` é vazio e nada é
  // aplicado — o link só "pega" quando há lista contra a qual validar.
  const acaoEfetiva = useMemo(() => {
    if (acaoAtiva == null) return null;
    // SEM_ACAO NÃO é caso especial: agruparPorAcao só o inclui em `acoes`
    // quando existem cards sem ação, e quando existe já casa no `.some()`
    // abaixo. Um curto-circuito aqui só mudaria o resultado justamente no
    // caso que deve ser descartado — a fila de sem-ação zerou (que é o
    // objetivo da operação) e um link antigo `canal=__sem_acao__` voltaria a
    // abrir board vazio com filtro invisível. Achado do fable-orchestrator.
    return acoes.some((a) => a.chave === acaoAtiva) ? acaoAtiva : null;
  }, [acaoAtiva, acoes]);

  // Escreve produto/canal no hash (N3) — `history.replaceState`, NÃO `push`:
  // trocar de aba/canal não pode entupir o botão voltar do navegador com uma
  // entrada por clique. Só ativo na aba board (não sobrescreve o hash de
  // faturamento/relatórios/ofertas) e só depois do 1º render (o efeito de
  // leitura acima já aplicou o deep link inicial antes deste rodar, mesma
  // ordem de effects do React — sem essa ordem, este efeito reescreveria o
  // hash com os valores default ANTES da leitura aplicar o link recebido).
  useEffect(() => {
    // `!board` é essencial: enquanto o fetch não volta, `acoes` é vazio e
    // `acaoEfetiva` é null — sem este gate o efeito reescreveria o hash SEM o
    // canal durante a janela de carregamento, e um F5 (ou copiar a URL) nesse
    // intervalo destruía o filtro que o próprio link trazia. A feature
    // apagava o próprio deep link a cada load. Achado do fable-orchestrator.
    if (tab !== 'board' || !board) return;
    const params = new URLSearchParams();
    params.set('produto', produtoAtivo);
    if (acaoEfetiva) params.set('canal', acaoEfetiva);
    const novoHash = `#board?${params.toString()}`;
    if (window.location.hash !== novoHash) {
      window.history.replaceState(null, '', novoHash);
    }
  }, [tab, board, produtoAtivo, acaoEfetiva]);

  // Rótulo legível do filtro ativo (nome da ação/canal) — o rodapé usa para
  // deixar explícito que os totais são do recorte, não da carteira (problema 6).
  const rotuloFiltroAtivo = useMemo(() => {
    if (!acaoEfetiva) return null;
    return acoes.find((a) => a.chave === acaoEfetiva)?.nome ?? null;
  }, [acoes, acaoEfetiva]);

  const cardsFiltrados: CardComEfeito[] = useMemo(() => {
    if (!acaoEfetiva) return cardsDoProduto;
    if (acaoEfetiva === SEM_ACAO) return cardsDoProduto.filter((c) => c.acaoNome == null);
    return cardsDoProduto.filter((c) => c.acaoNome === acaoEfetiva);
  }, [cardsDoProduto, acaoEfetiva]);

  // Camada mais rasa do funil de filtros: produto → canal → BUSCA. Sai daqui
  // (e não do BoardView) para alimentar o mesmo array ao mosaico E ao rodapé.
  const cardsVisiveis: CardComEfeito[] = useMemo(
    () => (busca.trim() ? cardsFiltrados.filter((c) => casaBusca(c.conta, busca)) : cardsFiltrados),
    [cardsFiltrados, busca],
  );

  // DOIS arrays de contas, de propósito — não unificar:
  //
  //   contasVisiveis  = produto → canal → busca → COR. Alimenta o rodapé de
  //                     totais, que precisa somar exatamente o que o mosaico
  //                     mostra (mosaico agora também filtra por cor).
  //   contasDoRecorte = produto → canal, SEM busca nem cor. Alimenta a aba
  //                     Relatórios.
  //
  // 🔑 O relatório NÃO herda busca nem cor do board. Esses filtros só existem
  // na aba board; quem filtra e troca para Relatórios não teria como saber
  // que a planilha saiu menor — o filtro que encolheu o arquivo estaria
  // invisível na tela que gerou o arquivo. Export que sai menor sem dizer por
  // quê é dado errado entregue em silêncio.
  // Camada MAIS rasa do funil: produto → canal → busca → COR (N4, 2026-08-27).
  // Fica por último de propósito — limpar a cor devolve exatamente o recorte
  // anterior, nunca a carteira toda, mesma disciplina da busca.
  //
  // `cardsVisiveis` (com cor) alimenta o mosaico e o rodapé; `cardsParaContador`
  // (sem cor) alimenta os contadores por cor do BoardView — senão, ao filtrar
  // por amarelo, os outros contadores zerariam e o filtro se tornaria uma porta
  // sem volta: o usuário não veria mais quantos verdes existem para voltar.
  const cardsComCor: CardComEfeito[] = useMemo(
    () => (corFiltro ? cardsVisiveis.filter((c) => c.cor === corFiltro) : cardsVisiveis),
    [cardsVisiveis, corFiltro],
  );

  const contasVisiveis: ContaReceber[] = useMemo(() => cardsComCor.map((c) => c.conta), [cardsComCor]);
  const contasDoRecorte: ContaReceber[] = useMemo(() => cardsFiltrados.map((c) => c.conta), [cardsFiltrados]);

  // calcularTotais roda sobre o array já filtrado por produto + ação — sem
  // query nova. Nunca reaproveita board.totais aqui: aquele total é da
  // carteira inteira (HM + Aurum somados), e o pedido do Marcio é o oposto —
  // os 4 totais têm que falar SÓ do recorte da aba ativa.
  const totaisFiltrados = useMemo(() => recalcularTotais(contasVisiveis), [contasVisiveis]);

  // Sobre o board INTEIRO (não o recorte filtrado) — a legenda é dicionário,
  // não resumo do que está visível; a 5ª entrada é o alarme de drift, e um
  // filtro que esconde o card neutro não pode apagar o alarme.
  const existeNeutro = useMemo(() => (board?.cards ?? []).some((c) => c.cor === 'neutro'), [board]);

  // Recorte ativo (N1) — mesma fonte que o rodapé usa para o rótulo completo
  // (domain/recorte.ts), para a barra de chips e a frase do rodapé nunca
  // divergirem no texto do mesmo recorte.
  const recorteAtivo: RecorteAtivo = useMemo(
    () => ({
      produtoLabel: produtoAtivo === 'HM' ? 'Holding Masters' : 'Aurum',
      canalLabel: rotuloFiltroAtivo,
      busca,
      // Rótulo pt-BR da cor vem de ROTULO_COR (domain/cor-status.ts), a mesma
      // fonte da legenda — o chip nunca mostra a chave crua ("amarelo").
      corLabel: corFiltro ? ROTULO_COR[corFiltro] : null,
    }),
    [produtoAtivo, rotuloFiltroAtivo, busca, corFiltro],
  );

  const aberta = openId ? board?.cards.find((c) => c.conta.contato_hm_id === openId)?.conta ?? null : null;

  const turmaAtual = turmas.find((t) => t.turma === turma);

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">
          {tab === 'board' ? (
            <>Board <span className="text-[var(--accent)]">Financeiro</span></>
          ) : tab === 'faturamento' ? (
            <>Faturamento <span className="text-[var(--accent)]">Diário</span></>
          ) : tab === 'relatorios' ? (
            <>Relatórios <span className="text-[var(--accent)]">Financeiro</span></>
          ) : (
            <>Ofertas de <span className="text-[var(--accent)]">Cobrança</span></>
          )}
        </h1>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4">
        {tab === 'board'
          ? 'Cards por faixa do funil — cor por status, intensidade por urgência'
          : tab === 'faturamento'
          ? 'Regime de caixa — o que entrou por dia de pagamento'
          : tab === 'relatorios'
          ? 'Selecione colunas e exporte (Excel ou impressão/PDF)'
          : 'Ofertas Hotmart usadas para cobrar o saldo do pacote'}
        {turmaAtual ? ` · turma ${turmaAtual.turma} (${turmaAtual.alunos} alunos)` : ''}
      </p>

      {tab === 'board' && (
        erroBoard ? (
          <ErroCarregamento msg={erroBoard} onRetry={carregarBoardAgora} />
        ) : !board ? (
          <Loading label="Carregando board financeiro…" minHeight={320} />
        ) : (
          <>
            <ProdutoTabs contagens={contagensProduto} ativo={produtoAtivo} onSelecionar={selecionarProduto} />
            <div className="mb-3">
              <TimelineAcoes acoes={acoes} ativa={acaoEfetiva} onSelecionar={selecionarAcao} />
            </div>
            <LegendaCores existeNeutro={existeNeutro} />
            <BarraRecorte
              recorte={recorteAtivo}
              onLimparCanal={() => selecionarAcao(null)}
              onLimparBusca={() => setBusca('')}
              onLimparCor={() => setCorFiltro(null)}
              onLimparTudo={() => { setAcaoAtiva(null); setBusca(''); setCorFiltro(null); }}
            />
            <BoardView
              cards={cardsComCor}
              cardsParaContador={cardsVisiveis}
              corFiltro={corFiltro}
              onCorFiltro={setCorFiltro}
              hojeISO={hojeISO}
              onOpen={setOpenId}
              busca={busca}
              onBusca={setBusca}
              totalSemBusca={cardsFiltrados.length}
              atalhoAtivo={!openId}
            />
            <RodapeTotais
              totais={totaisFiltrados}
              totalCards={cardsComCor.length}
              produtoAtivo={produtoAtivo === 'HM' ? 'Holding Masters' : 'Aurum'}
              filtroAtivo={rotuloFiltroAtivo}
              busca={busca}
              corAtiva={recorteAtivo.corLabel}
            />
          </>
        )
      )}

      {tab === 'faturamento' && (
        erroFat ? <ErroCarregamento msg={erroFat} onRetry={() => { setFat(null); setErroFat(null); }} /> : <Faturamento dados={fat} loading={!fat} />
      )}

      {tab === 'relatorios' && (
        board ? <Relatorios contas={contasDoRecorte} turma={turma} canVerDoc={canVerDoc} /> : <Loading label="Carregando…" minHeight={200} />
      )}

      {tab === 'ofertas' && (
        erroOfertas ? (
          <ErroCarregamento msg={erroOfertas} onRetry={() => { setOfertas([]); setErroOfertas(null); }} />
        ) : (
          <Ofertas ofertas={ofertas} loading={!ofertas.length && !erroOfertas} repo={repo} canEdit={canEdit} onSalvo={() => setOfertas([])} />
        )
      )}

      {aberta && (
        <FichaDrawer
          key={aberta.contato_hm_id}
          conta={aberta}
          repo={repo}
          canEdit={canEdit}
          canVerDoc={canVerDoc}
          regua={regua}
          hojeISO={hojeISO}
          onClose={() => setOpenId(null)}
          onAcordoSalvo={carregarBoardAgora}
        />
      )}
    </div>
  );
}

function ErroCarregamento({ msg, onRetry }: { msg: string; onRetry: () => void }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--red-border)] bg-[var(--red-subtle)] p-6 text-center">
      <Icon name="alert" size={22} className="mx-auto text-[var(--red)]" />
      <p className="mt-2 text-sm font-medium text-[var(--fg)]">{msg}</p>
      <button
        type="button"
        onClick={onRetry}
        className="mt-3 inline-flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--red-border)] px-3 py-1.5 text-xs font-semibold text-[var(--red)] hover:bg-[var(--red-subtle)]"
      >
        <Icon name="refresh" size={13} /> Tentar de novo
      </button>
    </div>
  );
}
