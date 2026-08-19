'use client';

import { useEffect, useMemo, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { Loading } from '@/shared/ui/components';
import type { ContaReceber, Oferta, TurmaFin } from '../domain/types';
// Mesma função pura de application/carregar-board.ts — reusada aqui para
// recalcular sobre o recorte filtrado pela timeline de ações (sem query nova).
import { calcularTotais as recalcularTotais } from '../domain/totais';
import { SupabaseFinanceiroRepository } from '../infrastructure/supabase-financeiro.repository';
import { carregarBoard, type BoardCarregado, type CardComEfeito } from '../application/carregar-board';
import { carregarFaturamento, type FaturamentoCarregado } from '../application/carregar-faturamento';
import { listarOfertas } from '../application/gerenciar-ofertas';
import { agruparPorAcao, SEM_ACAO, TimelineAcoes } from './TimelineAcoes';
import { BoardView } from './BoardView';
import { RodapeTotais } from './RodapeTotais';
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
  const [acaoAtiva, setAcaoAtiva] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  const hojeISO = new Date().toISOString().slice(0, 10);

  /** Busca board+régua (sem tocar estado) — usado pelo mount e pelo retry/callback. */
  const buscarBoard = () => repo.loadRegua().then((rg) => carregarBoard(repo, rg, hojeISO, turma, null));

  // Recarrega o board a partir de um evento do usuário (retry do erro,
  // onAcordoSalvo do drawer) — componente já montado, sem guard de unmount.
  const carregarBoardAgora = () =>
    buscarBoard()
      .then((b) => { setBoard(b); setErroBoard(null); })
      .catch(() => setErroBoard('Não foi possível carregar o board financeiro. Verifique sua conexão e tente novamente.'));

  useEffect(() => {
    let vivo = true;
    (async () => {
      try {
        const b = await buscarBoard();
        if (vivo) { setBoard(b); setErroBoard(null); }
      } catch {
        if (vivo) setErroBoard('Não foi possível carregar o board financeiro. Verifique sua conexão e tente novamente.');
      }
    })();
    (async () => {
      const t = await repo.loadTurmas().catch(() => []);
      if (vivo) setTurmas(t);
    })();

    const applyHash = () => {
      const h = window.location.hash.replace('#', '');
      if (h === 'faturamento') setTab('faturamento');
      else if (h === 'relatorios') setTab('relatorios');
      else if (h === 'ofertas') setTab('ofertas');
      else setTab('board');
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

  const acoes = useMemo(() => (board ? agruparPorAcao(board.cards) : []), [board]);

  // Rótulo legível do filtro ativo (nome da ação/canal) — o rodapé usa para
  // deixar explícito que os totais são do recorte, não da carteira (problema 6).
  const rotuloFiltroAtivo = useMemo(() => {
    if (!acaoAtiva) return null;
    return acoes.find((a) => a.chave === acaoAtiva)?.nome ?? null;
  }, [acoes, acaoAtiva]);

  const cardsFiltrados: CardComEfeito[] = useMemo(() => {
    if (!board) return [];
    if (!acaoAtiva) return board.cards;
    if (acaoAtiva === SEM_ACAO) return board.cards.filter((c) => c.acaoNome == null);
    return board.cards.filter((c) => c.acaoNome === acaoAtiva);
  }, [board, acaoAtiva]);

  const contasFiltradas: ContaReceber[] = useMemo(() => cardsFiltrados.map((c) => c.conta), [cardsFiltrados]);

  const colunasFiltradas = useMemo(() => {
    if (!board) return null;
    if (!acaoAtiva) return board.colunas;
    const grupos = { ...board.colunas };
    for (const chave of Object.keys(grupos) as (keyof typeof grupos)[]) {
      grupos[chave] = grupos[chave].filter((c) =>
        acaoAtiva === SEM_ACAO ? c.acaoNome == null : c.acaoNome === acaoAtiva,
      );
    }
    return grupos;
  }, [board, acaoAtiva]);

  // calcularTotais roda sobre o array já filtrado pela ação — sem query nova.
  const totaisFiltrados = useMemo(() => {
    if (!board) return null;
    if (!acaoAtiva) return board.totais;
    // Reimporta o cálculo puro do domínio sobre o recorte visível.
    return recalcularTotais(contasFiltradas);
  }, [board, acaoAtiva, contasFiltradas]);

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
        ) : !board || !colunasFiltradas || !totaisFiltrados ? (
          <Loading label="Carregando board financeiro…" minHeight={320} />
        ) : (
          <>
            <div className="mb-3">
              <TimelineAcoes acoes={acoes} ativa={acaoAtiva} onSelecionar={setAcaoAtiva} />
            </div>
            <BoardView colunas={colunasFiltradas} onOpen={setOpenId} />
            <RodapeTotais totais={totaisFiltrados} totalCards={cardsFiltrados.length} filtroAtivo={rotuloFiltroAtivo} />
          </>
        )
      )}

      {tab === 'faturamento' && (
        erroFat ? <ErroCarregamento msg={erroFat} onRetry={() => { setFat(null); setErroFat(null); }} /> : <Faturamento dados={fat} loading={!fat} />
      )}

      {tab === 'relatorios' && (
        board ? <Relatorios contas={contasFiltradas} turma={turma} canVerDoc={canVerDoc} /> : <Loading label="Carregando…" minHeight={200} />
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
