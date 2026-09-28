'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { Loading } from '@/shared/ui/components';
import type { ContaReceber, Oferta, ReguaPasso, TurmaFin } from '../domain/types';
// Mesma função pura de application/carregar-board.ts — reusada aqui para
// recalcular sobre o recorte filtrado pela timeline de ações (sem query nova).
import { calcularTotais as recalcularTotais } from '../domain/totais';
import { casaBusca } from '../domain/busca';
import { SupabaseFinanceiroRepository } from '../infrastructure/supabase-financeiro.repository';
import { carregarBoard, type BoardCarregado, type CardComEfeito } from '../application/carregar-board';
import { listarOfertas } from '../application/gerenciar-ofertas';
import { agruparPorAcao, chaveDaAcao, SEM_ACAO, TimelineAcoes } from './TimelineAcoes';
import { ResultadoAcoes } from './ResultadoAcoes';
import { FunisEAnalise } from './hotmart/FunisEAnalise';
import { ProgramaSemCard } from './ProgramaSemCard';
import { AssinaturaSemCard } from './AssinaturaSemCard';
import { OfertasSemCatalogo } from './OfertasSemCatalogo';
import { ProdutoTabs, type ProdutoChave } from './ProdutoTabs';
import { BoardView } from './BoardView';
import { BarraRecorte } from './BarraRecorte';
import type { RecorteAtivo } from '../domain/recorte';
import { RodapeTotais } from './RodapeTotais';
import { ForaDoBoard } from './hotmart/ForaDoBoard';
import { ROTULO_COR, type CorStatus } from '../domain/cor-status';
import { FichaDrawer } from './FichaDrawer';
import { Relatorios } from './Relatorios';
import { Ofertas } from './Ofertas';
import { FaturamentoDiario } from './FaturamentoDiario';
import { contarDiamantes, ServicoDiamante, useServicoDiamante } from './ServicoDiamante';
import type { BoardHotmart } from '../domain/hotmart';
import { indexarBoardHotmart } from '../domain/board-hotmart';
import { indexarAssinaturaHM, type AssinaturaHMBoard, type AssinaturaHMSemCard } from '../domain/assinatura-hm';
import type { PagouSemCard } from '../domain/programa-sem-card';
import { criarCacheListasSemCard, listasVisiveis } from '../application/carregar-listas-sem-card';
import { carregarContasReceber, type ContasReceberCarregado } from '../application/carregar-contas-receber';
import { ContasAReceber, type PremissasEstado } from './receber/ContasAReceber';
import { CABECALHO_RECEBER, ESTADOS_RECEBER, FERIADOS_RECEBER, PREMISSAS_RECEBER } from './receber/textos';
import type { CenarioReceber } from '../domain/contas-receber';
import { hashDaSubAbaReceber, subAbaReceberDoHash, type SubAbaReceber } from './receber/hash';

type Tab = 'board' | 'faturamento' | 'receber' | 'funis' | 'relatorios' | 'ofertas';

const repo = new SupabaseFinanceiroRepository();

export function FinanceiroClient({ canEdit, canVerDoc }: { canEdit: boolean; canVerDoc: boolean }) {
  const [tab, setTab] = useState<Tab>('board');
  const [relatorioInicial, setRelatorioInicial] = useState<'prorata' | null>(null);
  const [board, setBoard] = useState<BoardCarregado | null>(null);
  const [erroBoard, setErroBoard] = useState<string | null>(null);
  // Guardada aqui (e não descartada após montar o board) para alimentar
  // proximaAcao() na ficha — sem query nova por abertura de drawer (F3 do plano).
  const [regua, setRegua] = useState<ReguaPasso[]>([]);
  const [turmas, setTurmas] = useState<TurmaFin[]>([]);
  const [ofertas, setOfertas] = useState<Oferta[]>([]);
  const [erroOfertas, setErroOfertas] = useState<string | null>(null);
  // Contas a Receber: 1 RPC (fn_fin_receber_semanal) na 1ª vez que a aba abre; guardado aqui, voltar à aba não consulta
  // de novo (o componente da aba desmonta a cada troca — por isso o dado mora no pai). Falha não fica guardada.
  // F2: o mesmo vale POR CENÁRIO — 1 RPC na 1ª vez que cada cenário é pedido; voltar a um cenário já visto não consulta.
  // Gravou algo que muda a previsão (informado, premissa, feriado): o cache inteiro é invalidado (`geracaoReceber`),
  // a grade atual fica na tela enquanto só o cenário ativo é rebuscado; resposta de geração velha é descartada.
  const [receberPorCenario, setReceberPorCenario] = useState<Partial<Record<CenarioReceber, ContasReceberCarregado>>>({});
  const [cenarioReceber, setCenarioReceber] = useState<CenarioReceber>('base');
  const [erroReceber, setErroReceber] = useState<string | null>(null);
  const [tentativaReceber, setTentativaReceber] = useState(0);
  const pedidosReceber = useRef(new Set<CenarioReceber>());
  const geracaoReceber = useRef(0);
  // Sub-aba Premissas: 1 chamada de premissas + 1 de feriados na 1ª vez que a sub-aba abre (guardado aqui).
  const [premissasReceber, setPremissasReceber] = useState<PremissasEstado>(
    { premissas: null, feriados: null, erroPremissas: null, erroFeriados: null });
  const pedidoPremissas = useRef(false);
  // Sub-aba de Previsão de caixa (#receber?ver=) — mesmo padrão de hash do #board?produto=. "semana" é o padrão
  // (hash limpo #receber, sem `?`, o mesmo link do item do menu).
  const [receberSub, setReceberSub] = useState<SubAbaReceber>('semana');
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
  // Serviço Diamante: aba do board ao lado de HM/Aurum (27/09/2026). Carrega junto com o board (1 RPC, ~180 linhas).
  const [verDiamante, setVerDiamante] = useState(false);
  const diamante = useServicoDiamante(repo, tab === 'board');
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
  // Filtro "Diverge da Hotmart" — mesma camada/disciplina de busca e cor:
  // mora aqui para o rodapé somar o que o mosaico mostra; fora do hash.
  const [divergeFiltro, setDivergeFiltro] = useState(false);
  // Boleto/Pix gerado e não pago (27/09, João: "boleto aberto tem que ter uma visualização diferente").
  const [boletoFiltro, setBoletoFiltro] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);
  // Camada Hotmart do board (fn_fin_board_hotmart): carregada UMA vez junto
  // com o board, nunca por card. Falha não bloqueia o board — só a camada
  // mostra aviso. `null` = ainda carregando ou falhou (ver hotmartErro).
  const [hotmartPorCard, setHotmartPorCard] = useState<Map<string, BoardHotmart> | null>(null);
  const [hotmartErro, setHotmartErro] = useState(false);
  // Mensalidade do HM antigo por pessoa_chave (fn_fin_board_assinatura_hm, z52): UMA chamada por abertura do board,
  // junto da camada Hotmart, nunca por card. `null` = carregando ou falhou — o bloco Assinatura cai no dado antigo.
  const [assinaturaPorPessoa, setAssinaturaPorPessoa] = useState<Map<string, AssinaturaHMBoard> | null>(null);
  // Listas "sem card" (Programa HM/Aurum e mensalidade do HM antigo): cada uma carrega na 1ª vez que o produto dela
  // fica visível e fica guardada aqui — voltar à aba não consulta de novo, e Aurum nunca visitado nunca consulta
  // (programa_sem_card('AURUM') = 713 ms medidos, 28/09). O recarregar do board invalida o cache.
  // `null` = carregando; falha vira lista vazia (o bloco some, como antes).
  const [programaSemCard, setProgramaSemCard] = useState<Record<'HM' | 'AURUM', PagouSemCard[] | null>>({ HM: null, AURUM: null });
  const [assinaturaSemCard, setAssinaturaSemCard] = useState<AssinaturaHMSemCard[] | null>(null);
  const [cacheSemCard] = useState(() => criarCacheListasSemCard(repo, (lista, dados) => {
    if (lista === 'assinatura_HM') setAssinaturaSemCard(dados as AssinaturaHMSemCard[]);
    else setProgramaSemCard((p) => ({ ...p, [lista === 'programa_HM' ? 'HM' : 'AURUM']: dados as PagouSemCard[] }));
  }));

  const selecionarProduto = (produto: ProdutoChave) => {
    setVerDiamante(false);
    setProdutoAtivo(produto);
    setAcaoAtiva(null);
    setBusca('');
    setCorFiltro(null);
    setDivergeFiltro(false);
  };

  const selecionarAcao = (acao: string | null) => {
    setAcaoAtiva(acao);
    setBusca('');
    setCorFiltro(null);
    setDivergeFiltro(false);
  };

  const hojeISO = new Date().toISOString().slice(0, 10);

  /** Busca board+régua (sem tocar estado) — usado pelo mount e pelo retry/callback. */
  const buscarBoard = () => repo.loadRegua().then((rg) => carregarBoard(repo, rg, hojeISO, turma, null).then((b) => ({ b, rg })));

  /** Camada Hotmart — disparada em paralelo ao board; erro fica só nela. */
  const buscarHotmart = () => repo.loadBoardHotmart().then(indexarBoardHotmart);
  const buscarAssinatura = () => repo.loadBoardAssinaturaHM().then(indexarAssinaturaHM);

  // Recarrega o board a partir de um evento do usuário (retry do erro,
  // onAcordoSalvo do drawer) — componente já montado, sem guard de unmount.
  const carregarBoardAgora = () => {
    buscarHotmart()
      .then((m) => { setHotmartPorCard(m); setHotmartErro(false); })
      .catch(() => setHotmartErro(true));
    buscarAssinatura().then(setAssinaturaPorPessoa).catch(() => {});
    // Invalida as listas sem card: recarrega agora só as visíveis; as outras, na próxima visita.
    cacheSemCard.invalidar();
    cacheSemCard.garantir(listasVisiveis(tab, produtoAtivo, verDiamante));
    return buscarBoard()
      .then(({ b, rg }) => { setBoard(b); setRegua(rg); setErroBoard(null); })
      .catch(() => setErroBoard('Não foi possível carregar o board financeiro. Verifique sua conexão e tente novamente.'));
  };

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
    buscarHotmart()
      .then((m) => { if (vivo) { setHotmartPorCard(m); setHotmartErro(false); } })
      .catch(() => { if (vivo) setHotmartErro(true); });
    buscarAssinatura()
      .then((m) => { if (vivo) setAssinaturaPorPessoa(m); })
      .catch(() => { /* sem a camada nova o bloco Assinatura mostra o que já mostrava */ });
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
      else if (base === 'receber') { setTab('receber'); setReceberSub(subAbaReceberDoHash(query)); }
      else if (base === 'funis') setTab('funis');
      else if (base === 'relatorios') { setTab('relatorios'); setRelatorioInicial(null); }
      else if (base === 'ofertas') setTab('ofertas');
      // A Calculadora de Pro Rata saiu do menu (limpeza, 28/09) e mora em Relatórios; o link antigo abre lá.
      else if (base === 'prorata') { setTab('relatorios'); setRelatorioInicial('prorata'); }
      // #diamante era a tela própria do Serviço Diamante; virou aba do board (27/09).
      else if (base === 'diamante') { setTab('board'); setVerDiamante(true); }
      // #hotmart era a aba "Hotmart (oficial)", unificada no Faturamento Diário em 27/09 — link antigo cai nela.
      else if (base === 'hotmart') setTab('faturamento');
      else setTab('board');

      if (base === 'board' && query) {
        const params = new URLSearchParams(query);
        const produto = params.get('produto');
        if (produto === 'HM' || produto === 'AURUM') { setProdutoAtivo(produto); setVerDiamante(false); }
        if (produto === 'DIAMANTE') setVerDiamante(true);
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

  // Listas sem card do produto visível: pede só o que ainda não foi pedido (o cache ignora o resto).
  useEffect(() => {
    cacheSemCard.garantir(listasVisiveis(tab, produtoAtivo, verDiamante));
  }, [cacheSemCard, tab, produtoAtivo, verDiamante]);
  // Desmontou: respostas em voo são descartadas (e, no StrictMode, a remontagem pede de novo).
  useEffect(() => () => cacheSemCard.invalidar(), [cacheSemCard]);

  useEffect(() => {
    if (tab !== 'ofertas' || ofertas.length) return;
    listarOfertas(repo)
      .then((o) => { setOfertas(o); setErroOfertas(null); })
      .catch(() => setErroOfertas('Não foi possível carregar as ofertas.'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab]);

  useEffect(() => {
    const cen = cenarioReceber;
    if (tab !== 'receber' || receberPorCenario[cen] || pedidosReceber.current.has(cen)) return;
    const ger = geracaoReceber.current;
    pedidosReceber.current.add(cen);
    carregarContasReceber(repo, cen)
      .then((r) => {
        if (ger !== geracaoReceber.current) return;
        setReceberPorCenario((m) => ({ ...m, [cen]: r }));
        setErroReceber(null);
      })
      .catch(() => {
        if (ger !== geracaoReceber.current) return;
        pedidosReceber.current.delete(cen);
        setErroReceber(ESTADOS_RECEBER.erroCarregamento);
      });
  }, [tab, cenarioReceber, receberPorCenario, tentativaReceber]);

  // Algo que muda a previsão foi gravado (informado, premissa, feriado). Invalida TODOS os cenários guardados e rebusca
  // só o ativo, SEM apagar a grade atual (a sub-aba continua montada); falha vira o erro da aba, com "tentar de novo".
  const recarregarReceber = () => {
    geracaoReceber.current += 1;
    const ger = geracaoReceber.current;
    const cen = cenarioReceber;
    pedidosReceber.current = new Set([cen]);
    setReceberPorCenario((m) => (m[cen] ? { [cen]: m[cen] } : {}));
    carregarContasReceber(repo, cen)
      .then((r) => {
        if (ger !== geracaoReceber.current) return;
        setReceberPorCenario({ [cen]: r });
        setErroReceber(null);
      })
      .catch(() => {
        if (ger !== geracaoReceber.current) return;
        pedidosReceber.current.delete(cen);
        setErroReceber(ESTADOS_RECEBER.erroCarregamento);
      });
  };

  // Premissas e feriados: setState só nos retornos (nunca síncrono no corpo do efeito).
  const buscarPremissas = (quais: { premissas: boolean; feriados: boolean }) => {
    if (quais.premissas) {
      repo.loadPremissasReceber().then(
        (p) => setPremissasReceber((s) => ({ ...s, premissas: p, erroPremissas: null })),
        () => setPremissasReceber((s) => ({ ...s, erroPremissas: PREMISSAS_RECEBER.erroCarregamento })),
      );
    }
    if (quais.feriados) {
      repo.loadFeriados().then(
        (f) => setPremissasReceber((s) => ({ ...s, feriados: f, erroFeriados: null })),
        () => setPremissasReceber((s) => ({ ...s, erroFeriados: FERIADOS_RECEBER.erroCarregamento })),
      );
    }
  };
  useEffect(() => {
    if (tab !== 'receber' || receberSub !== 'premissas' || pedidoPremissas.current) return;
    pedidoPremissas.current = true;
    buscarPremissas({ premissas: true, feriados: true });
  }, [tab, receberSub]);
  const tentarPremissasDeNovo = () => {
    const quais = { premissas: premissasReceber.erroPremissas != null, feriados: premissasReceber.erroFeriados != null };
    setPremissasReceber((s) => ({
      ...s, erroPremissas: null, erroFeriados: null,
      premissas: quais.premissas ? null : s.premissas, feriados: quais.feriados ? null : s.feriados,
    }));
    buscarPremissas(quais);
  };

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
    params.set('produto', verDiamante ? 'DIAMANTE' : produtoAtivo);
    if (acaoEfetiva && !verDiamante) params.set('canal', acaoEfetiva);
    const novoHash = `#board?${params.toString()}`;
    if (window.location.hash !== novoHash) {
      window.history.replaceState(null, '', novoHash);
    }
  }, [tab, board, produtoAtivo, acaoEfetiva, verDiamante]);

  // Mesma disciplina do hash do board, mas para a sub-aba de Previsão de caixa — sem gate de carregamento: a
  // sub-aba é estado só de navegação (não depende de `receber` ter chegado), então não há janela em que reescrever
  // o hash apagaria um deep link que o próprio efeito ainda não leu.
  useEffect(() => {
    if (tab !== 'receber') return;
    const novoHash = hashDaSubAbaReceber(receberSub);
    if (window.location.hash !== novoHash) {
      window.history.replaceState(null, '', novoHash);
    }
  }, [tab, receberSub]);

  // Rótulo legível do filtro ativo (nome da ação/canal) — o rodapé usa para
  // deixar explícito que os totais são do recorte, não da carteira (problema 6).
  const rotuloFiltroAtivo = useMemo(() => {
    if (!acaoEfetiva) return null;
    return acoes.find((a) => a.chave === acaoEfetiva)?.nome ?? null;
  }, [acoes, acaoEfetiva]);

  const cardsFiltrados: CardComEfeito[] = useMemo(() => {
    if (!acaoEfetiva) return cardsDoProduto;
    if (acaoEfetiva === SEM_ACAO) return cardsDoProduto.filter((c) => c.acaoNome == null);
    return cardsDoProduto.filter((c) => chaveDaAcao(c.acaoNome) === acaoEfetiva);
  }, [cardsDoProduto, acaoEfetiva]);

  // Camada mais rasa do funil de filtros: produto → canal → BUSCA. Sai daqui
  // (e não do BoardView) para alimentar o mesmo array ao mosaico E ao rodapé.
  const cardsBuscados: CardComEfeito[] = useMemo(
    () => (busca.trim() ? cardsFiltrados.filter((c) => casaBusca(c.conta, busca)) : cardsFiltrados),
    [cardsFiltrados, busca],
  );

  // Quantos cards do recorte (depois da busca, antes do filtro) divergem da
  // Hotmart — número do chip, estável ao ligar/desligar o próprio filtro.
  const qtdDiverge = useMemo(
    () => (hotmartPorCard ? cardsBuscados.filter((c) => hotmartPorCard.get(c.conta.contato_hm_id)?.diverge === true).length : 0),
    [cardsBuscados, hotmartPorCard],
  );

  // Diverge entra entre busca e cor. Sem dado Hotmart (carregando/erro) o
  // filtro não se aplica — nunca esvazia o board por falta da camada.
  const divergeAtivo = divergeFiltro && !!hotmartPorCard;
  const qtdBoleto = useMemo(
    () => (hotmartPorCard ? cardsBuscados.filter((c) => (hotmartPorCard.get(c.conta.contato_hm_id)?.boleto_aberto_n ?? 0) > 0).length : 0),
    [cardsBuscados, hotmartPorCard],
  );
  const boletoAtivo = boletoFiltro && !!hotmartPorCard;
  const cardsVisiveis: CardComEfeito[] = useMemo(
    () => cardsBuscados.filter((c) => {
      const h = hotmartPorCard?.get(c.conta.contato_hm_id);
      if (divergeAtivo && h?.diverge !== true) return false;
      if (boletoAtivo && !((h?.boleto_aberto_n ?? 0) > 0)) return false;
      return true;
    }),
    [cardsBuscados, divergeAtivo, boletoAtivo, hotmartPorCard],
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

  // A legenda de cores saiu (limpeza de 28/09): o nome de cada cor está no próprio contador do BoardView,
  // que inclui o "neutro" (alarme de status desconhecido) sempre que houver card assim no recorte.

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
      diverge: divergeAtivo,
    }),
    [produtoAtivo, rotuloFiltroAtivo, busca, corFiltro, divergeAtivo],
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
            <>Faturamento <span className="text-[var(--accent)]">da Hotmart</span></>
          ) : tab === 'relatorios' ? (
            <>Relatórios <span className="text-[var(--accent)]">Financeiro</span></>
          ) : tab === 'receber' ? (
            <>{CABECALHO_RECEBER.titulo}</>
          ) : tab === 'funis' ? (
            <>Funis <span className="text-[var(--accent)]">e Análise</span></>
          ) : (
            <>Ofertas de <span className="text-[var(--accent)]">Cobrança</span></>
          )}
        </h1>
      </div>
      {/* Sem subtítulo explicativo (João, 27/09: "tira essas descrições… não ajudam em nada"). Só a turma escolhida. */}
      <div className="mb-4">
        {tab === 'board' && turmaAtual && (
          <p className="text-sm text-[var(--fg-3)]">turma {turmaAtual.turma} ({turmaAtual.alunos} alunos)</p>
        )}
      </div>

      {tab === 'board' && (
        erroBoard ? (
          <ErroCarregamento msg={erroBoard} onRetry={carregarBoardAgora} />
        ) : !board ? (
          <Loading label="Carregando board financeiro…" minHeight={320} />
        ) : (
          <>
            <ProdutoTabs contagens={contagensProduto} ativo={produtoAtivo} onSelecionar={selecionarProduto}
              diamante={{ ativo: verDiamante, contagem: contarDiamantes(diamante.dados), onSelecionar: () => setVerDiamante(true) }} />
            {verDiamante ? <ServicoDiamante dados={diamante.dados} erro={diamante.erro} repo={repo} /> : <>
            {(produtoAtivo === 'HM' || produtoAtivo === 'AURUM') && <OfertasSemCatalogo repo={repo} familia={produtoAtivo} />}
            {(produtoAtivo === 'HM' || produtoAtivo === 'AURUM') && <ProgramaSemCard key={produtoAtivo} dados={programaSemCard[produtoAtivo]} familia={produtoAtivo} />}
            {produtoAtivo === 'HM' && <AssinaturaSemCard dados={assinaturaSemCard} />}
            <ResultadoAcoes cards={cardsDoProduto} ativa={acaoEfetiva} onSelecionar={selecionarAcao} />
            <div className="mb-3">
              <TimelineAcoes acoes={acoes} ativa={acaoEfetiva} onSelecionar={selecionarAcao} />
            </div>
            <BarraRecorte
              recorte={recorteAtivo}
              onLimparCanal={() => selecionarAcao(null)}
              onLimparBusca={() => setBusca('')}
              onLimparCor={() => setCorFiltro(null)}
              onLimparDiverge={() => setDivergeFiltro(false)}
              onLimparTudo={() => { setAcaoAtiva(null); setBusca(''); setCorFiltro(null); setDivergeFiltro(false); setBoletoFiltro(false); }}
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
              hotmartPorCard={hotmartPorCard}
              assinaturaPorPessoa={assinaturaPorPessoa}
              divergeFiltro={divergeAtivo}
              qtdDiverge={qtdDiverge}
              onDivergeFiltro={setDivergeFiltro}
              boletoFiltro={boletoAtivo}
              qtdBoleto={qtdBoleto}
              onBoletoFiltro={setBoletoFiltro}
            />
            <RodapeTotais
              totais={totaisFiltrados}
              totalCards={cardsComCor.length}
              produtoAtivo={produtoAtivo === 'HM' ? 'Holding Masters' : 'Aurum'}
              filtroAtivo={rotuloFiltroAtivo}
              busca={busca}
              corAtiva={recorteAtivo.corLabel}
              diverge={divergeAtivo}
              contatoIds={contasVisiveis.map((c) => c.contato_hm_id)}
              hotmartPorCard={hotmartPorCard}
              hotmartErro={hotmartErro}
            />
            {/* Quem pagou na Hotmart e não tem card — e a adimplência de todo mundo que pagou (27/09, João:
                "pode exibir elas, mesmo que não tenha oferta"). Fica abaixo do mosaico: não muda card nem total. */}
            <div className="mt-6">
              <ForaDoBoard key={produtoAtivo} repo={repo} familia={produtoAtivo} />
            </div>
            </>}
          </>
        )
      )}

      {tab === 'faturamento' && <FaturamentoDiario repo={repo} />}

      {tab === 'relatorios' && (
        board ? <Relatorios key={relatorioInicial ?? 'padrao'} tipoInicial={relatorioInicial ?? undefined} contas={contasDoRecorte} produtoLabel={recorteAtivo.produtoLabel} acaoLabel={rotuloFiltroAtivo} turma={turma} canVerDoc={canVerDoc} repo={repo} hotmartPorCard={hotmartPorCard} /> : <Loading label="Carregando…" minHeight={200} />
      )}

      {tab === 'receber' && (
        erroReceber ? (
          <ErroCarregamento msg={erroReceber} onRetry={() => { setErroReceber(null); setTentativaReceber((t) => t + 1); }} />
        ) : Object.keys(receberPorCenario).length > 0 ? (
          // Cenário ainda não carregado: a grade mostra "carregando o cenário" (dados = null), o resto da aba segue.
          <ContasAReceber dados={receberPorCenario[cenarioReceber] ?? null} repo={repo} canEdit={canEdit} canVerDoc={canVerDoc}
            onInformadosAlterados={recarregarReceber} sub={receberSub} onSubChange={setReceberSub}
            cenario={cenarioReceber} onCenario={setCenarioReceber}
            premissas={premissasReceber} onTentarPremissas={tentarPremissasDeNovo}
            onPremissaGravada={() => { buscarPremissas({ premissas: true, feriados: false }); recarregarReceber(); }}
            onFeriadoGravado={() => { buscarPremissas({ premissas: false, feriados: true }); recarregarReceber(); }} />
        ) : <Loading label="Carregando a previsão de caixa…" minHeight={200} />
      )}

      {tab === 'funis' && <FunisEAnalise repo={repo} />}


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
          hotmartPorCard={hotmartPorCard}
          hotmartErro={hotmartErro}
          assinaturaPorPessoa={assinaturaPorPessoa}
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
