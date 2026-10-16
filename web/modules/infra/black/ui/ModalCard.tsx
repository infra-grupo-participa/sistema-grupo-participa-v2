'use client';

// Modal do card da Visão geral (molde do modal canônico). Sub-abas FIXAS em todo card: Por funil · Por canal ·
// Por fase · Por dia · Por criativo · Perfil. A que não se aplica ao card diz isso, em vez de sumir (o lugar de
// cada coisa não muda de um card para outro). Cada linha recalcula a MESMA métrica do card no recorte da linha.
// Por fase = barras grossas por fase (graficos.tsx); Por dia = gráfico de linha com cursor; Por criativo = lista
// compacta (top 10, busca e rolagem), clique leva ao criativo. Evolução com meta fica dentro de Por dia.
import { useMemo, useState } from 'react';
import { Modal, SearchInput } from '@/shared/ui/components';
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { anunciosDoCriativo, idDoCriativo } from '../domain/criativos';
import { filtrarDias, filtrarLinhas } from '../domain/metricas';
import { diaDe } from '../domain/recorte';
import { FASES, FUNIS, ROTULO_CANAL, ROTULO_FASE, ROTULO_FUNIL, ROTULO_LINHA, ROTULO_SEM_CLASSIFICACAO, ROTULO_SEM_FASE, type Campanha, type DesempenhoDia, type Fase, type LinhaPerfil, type Valor } from '../domain/tipos';
import { funilDaLinha, linhaDaCampanha, linhaDoLead } from '../domain/linha-black';
import type { FormatoMetrica } from '../domain/jornada';
import type { DadosTela } from './contexto';
import { BarrasFase, GraficoLinha, type ItemFase } from './graficos';
import { Chip, formatar, MODAL_TELA_CHEIA, Numero } from './pecas';
import { PerfilLeads } from './perfil/PerfilLeads';
import { EvolucaoMetaIndicador, serieDiariaIndicador } from './EvolucaoMeta';

export type SubAbaModal = 'funil' | 'canal' | 'fase' | 'dia' | 'criativo' | 'perfil';
const SUBABAS: { k: SubAbaModal; l: string }[] = [
  { k: 'funil', l: 'Por funil' }, { k: 'canal', l: 'Por canal' }, { k: 'fase', l: 'Por fase' },
  { k: 'dia', l: 'Por dia' }, { k: 'criativo', l: 'Por criativo' }, { k: 'perfil', l: 'Perfil' },
];
const TOPO_CRIATIVOS = 10;
const NOTA_ENTRESAFRA = 'Entresafra fora de todos os gastos (decisão do Victor)';
const CARDS_DE_TRAFEGO = new Set(['gasto', 'cpl', 'imp', 'cpm', 'cliques', 'ctr', 'cpc', 'lpv', 'connect', 'conv']);

export interface CardDef {
  id: string;
  rotulo: string;
  formato: FormatoMetrica;
  /** A métrica do card, recalculável em qualquer recorte de dias e cadastros. */
  medir: (dias: DesempenhoDia[], linhas: LinhaPerfil[]) => Valor;
  /** Sub-abas que fazem sentido para este card. */
  aplica: SubAbaModal[];
  dica?: string;
  /** Custo (CPL, CPM, CPC): menor é melhor, a lista de criativos abre pelo menor. */
  menorMelhor?: boolean;
}

interface Linha { chave: string; rotulo: string; valor: Valor; anuncioId?: string }
const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
const metaDaSeriePara = (cardId: string, d: DadosTela): Valor => cardId === 'leads' ? d.config.metaLeads
  : cardId === 'cpl' ? (d.config.cplAlvoMedio ?? d.config.reguaCpl?.meta ?? null)
    : cardId === 'cpm' ? d.config.metas.cpm : cardId === 'ctr' ? d.config.metas.ctr
      : cardId === 'cpc' ? d.config.metas.cpc : cardId === 'connect' ? d.config.metas.connectRate
        : cardId === 'conv' ? d.config.metas.conversaoPagina
          : cardId === 'mql-percentual' ? d.config.metas.mql : null;

type Bloco = { dias: DesempenhoDia[]; leads: LinhaPerfil[] };
/**
 * Barras por fase (fase que o banco devolve por campanha). Campanha sem fase vira "Sem fase" e campanha que o banco não
 * classificou vira "Sem classificação": as duas aparecem quando existem, para a soma das barras fechar com o card.
 * Pré-captação fica fora (decisão do Victor): não entra em barra nenhuma.
 */
function itensFase(d: DadosTela, card: CardDef): ItemFase[] {
  const { idx } = d;
  const campanhaDoLead = (l: LinhaPerfil) => (l.campanhaId ? idx.campanha.get(l.campanhaId) : undefined);
  const faseDe = (c: Campanha | null | undefined): Fase | 'sem_fase' | 'sem_classificacao' | 'pre_captacao' | null => {
    if (!c) return null;
    const linha = linhaDaCampanha(c);
    if (linha === 'pre_captacao') return 'pre_captacao';
    if (linha === null) return 'sem_classificacao';
    return c.fase ?? 'sem_fase';
  };
  const dias = filtrarDias(d.dias, idx, { funil: 'todos', canal: 'todos' });
  const por = (chave: string): Bloco => ({
    dias: dias.filter((x) => faseDe(idx.campanhaDoAnuncio(x.anuncioId)) === chave),
    leads: d.linhas.filter((l) => faseDe(campanhaDoLead(l)) === chave),
  });
  const itens: ItemFase[] = FASES.map((f) => { const b = por(f); return { fase: f, rotulo: ROTULO_FASE[f], valor: card.medir(b.dias, b.leads) }; });
  for (const [fase, rotulo] of [['sem_fase', ROTULO_SEM_FASE], ['sem_classificacao', ROTULO_SEM_CLASSIFICACAO]] as const) {
    const b = por(fase);
    if (b.dias.length > 0 || b.leads.length > 0) itens.push({ fase, rotulo, valor: card.medir(b.dias, b.leads) });
  }
  return itens;
}

export function ModalCard({ d, card, onClose }: { d: DadosTela; card: CardDef | null; onClose: () => void }) {
  const [sub, setSub] = useState<SubAbaModal>('funil');
  if (!card) return null;
  const metaDaSerie = metaDaSeriePara(card.id, d);
  const pontosIndicador = metaDaSerie !== null ? serieDiariaIndicador(card.id, d) : null;
  const ativa = card.aplica.includes(sub) ? sub : card.aplica[0] ?? 'funil';
  const { idx } = d;
  const canalAtual = { canal: d.recorte.canal };
  const funilAtual = { funil: d.recorte.funil };

  // Variação de hoje contra ontem, no recorte de funil e canal.
  const hoje = d.periodo.ate; const ontem = deslocarDia(hoje, -1);
  const doDia = (dia: string) => pontosIndicador
    ? pontosIndicador.find((p) => p.dia === dia)?.realizado ?? null
    : card.medir(
    filtrarDias(d.diasTodos.filter((x) => x.dia === dia), idx, { ...funilAtual, ...canalAtual }),
    filtrarLinhas(d.linhasTodas.filter((l) => diaDe(l.criadoEm) === dia), { ...funilAtual, ...canalAtual }, idx),
  );
  const vHoje = doDia(hoje); const vOntem = doDia(ontem);
  const variacao = vHoje !== null && vOntem !== null && vOntem !== 0 ? (vHoje - vOntem) / vOntem : null;
  const lista = (): Linha[] => {
    if (ativa === 'funil') {
      const porFunil: Linha[] = FUNIS.map((f) => ({
        chave: f, rotulo: ROTULO_FUNIL[f],
        valor: card.medir(filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: f, ...canalAtual }), filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: f, ...canalAtual }, idx)),
      }));
      // Linhas que não são C1, C2 nem C3 também contam nos totais: aparecem à parte para a soma das linhas fechar com o card.
      const todosDias = filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: 'todos', ...canalAtual });
      const todosLeads = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', ...canalAtual }, idx);
      const noRemarketing = { dias: todosDias.filter((x) => idx.linhaDoAnuncio(x.anuncioId) === 'remarketing_pagina'), leads: todosLeads.filter((l) => linhaDoLead(l, idx) === 'remarketing_pagina') };
      const outros = {
        dias: todosDias.filter((x) => { const l = idx.linhaDoAnuncio(x.anuncioId); return l !== 'remarketing_pagina' && funilDaLinha(l) === null; }),
        leads: todosLeads.filter((l) => { const x = linhaDoLead(l, idx); return x !== 'remarketing_pagina' && funilDaLinha(x) === null && x !== undefined; }),
      };
      const extra: Linha[] = [
        { chave: 'remarketing_pagina', rotulo: ROTULO_LINHA.remarketing_pagina, valor: card.medir(noRemarketing.dias, noRemarketing.leads) },
        { chave: 'outras', rotulo: 'Fora de C1, C2 e C3 (lembrete, live, carrinho, sem classificação)', valor: card.medir(outros.dias, outros.leads) },
      ].filter((x) => x.chave === 'remarketing_pagina' || (x.valor !== null && x.valor !== 0));
      return [...porFunil, ...extra];
    }
    if (ativa === 'canal') return (['meta', 'google'] as const).map((c) => ({
      chave: c, rotulo: ROTULO_CANAL[c],
      valor: card.medir(filtrarDias(d.diasPeriodoSemFiltro, idx, { ...funilAtual, canal: c }), filtrarLinhas(d.linhasPeriodoSemFiltro, { ...funilAtual, canal: c }, idx)),
    }));
    return [];
  };

  return (
    <Modal open onClose={onClose} title={card.rotulo} width={`max-w-3xl ${MODAL_TELA_CHEIA}`}>
      <div className="space-y-3">
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
          <span className="text-2xl font-bold text-[var(--fg)]"><Numero valor={card.id === 'leads' && pontosIndicador ? pontosIndicador.at(-1)?.acumulado ?? null : card.medir(d.dias, d.linhas)} formato={card.formato} /></span>
          <span className="text-xs text-[var(--fg-3)]">
            Hoje ({dataCurta(hoje)}): {formatar(vHoje, card.formato)} · ontem: {formatar(vOntem, card.formato)}
            {variacao !== null ? ` · variação ${variacao >= 0 ? '+' : ''}${formatar(variacao, 'pct')}` : ''}
          </span>
        </div>
        {(card.dica || CARDS_DE_TRAFEGO.has(card.id)) && <p className="text-xs text-[var(--fg-3)]">{[card.dica, CARDS_DE_TRAFEGO.has(card.id) && !card.dica?.includes(NOTA_ENTRESAFRA) ? NOTA_ENTRESAFRA : null].filter(Boolean).join(' ')}</p>}

        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Detalhar por">
          {SUBABAS.map((s) => (
            <button key={s.k} type="button" aria-pressed={ativa === s.k} onClick={() => setSub(s.k)}
              className={'min-h-9 rounded-[var(--r-md)] px-3 text-xs ' + (ativa === s.k ? 'bg-[var(--accent)] font-semibold text-black' : 'bg-[var(--surface-3)] text-[var(--fg-2)] hover:text-[var(--fg)]')}>
              {s.l}
            </button>
          ))}
        </div>

        <div key={ativa} className="atm-historico-panel-enter">
          {!card.aplica.includes(sub) ? (
            <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Não se aplica a este card.</p>
          ) : ativa === 'perfil' ? (
            <PerfilLeads d={d} linhas={d.linhas} />
          ) : ativa === 'fase' ? (
            <div className="pt-2">
              <BarrasFase formato={card.formato} itens={itensFase(d, card)} />
            </div>
          ) : ativa === 'dia' ? (
            metaDaSerie !== null
              ? <EvolucaoMetaIndicador d={d} cardId={card.id} rotulo={card.rotulo} formato={card.formato as 'int' | 'brl' | 'pct'} pontos={pontosIndicador ?? undefined} />
              : <GraficoLinha rotuloSerie={card.rotulo} formato={card.formato} pontos={d.diasPeriodo.map((dia) => ({
                chave: dia, rotulo: dataCurta(dia),
                valor: card.medir(filtrarDias(d.dias.filter((x) => x.dia === dia), idx, { funil: 'todos', canal: 'todos' }), d.linhas.filter((l) => diaDe(l.criadoEm) === dia)),
              }))} />
          ) : ativa === 'criativo' ? (
            <PorCriativo d={d} card={card} onIr={(id) => { onClose(); d.irPara({ aba: 'criativos', criativos: { anuncio: id } }); d.abrirGaveta({ tipo: 'criativo', id }); }} />
          ) : (
            <ListaBarras linhas={lista()} formato={card.formato} />
          )}
        </div>
      </div>
    </Modal>
  );
}

function ListaBarras({ linhas, formato }: { linhas: Linha[]; formato: FormatoMetrica }) {
  const max = Math.max(0, ...linhas.map((l) => (l.valor !== null && l.valor > 0 ? l.valor : 0)));
  if (linhas.length === 0) return <p className="text-sm text-[var(--fg-3)]">Sem dado no recorte.</p>;
  return (
    <ul className="space-y-4 pt-1">
      {linhas.map((l, i) => (
        <li key={l.chave}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="min-w-0 break-words text-[var(--fg-2)]">{l.rotulo}</span>
            <span className="shrink-0 font-semibold text-[var(--fg)]"><Numero valor={l.valor} formato={formato} animado={false} /></span>
          </div>
          <div className="mt-1.5 h-2.5 overflow-hidden rounded-full bg-[var(--surface-4)]">
            <div className="atm-historico-barra h-full rounded-full bg-[var(--accent)]" style={{ width: max > 0 && l.valor !== null && l.valor > 0 ? `${(l.valor / max) * 100}%` : '0%', animationDelay: `${i * 60}ms` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

function PorCriativo({ d, card, onIr }: { d: DadosTela; card: CardDef; onIr: (id: string) => void }) {
  const [busca, setBusca] = useState('');
  const [todos, setTodos] = useState(false);
  const [menor, setMenor] = useState(Boolean(card.menorMelhor));
  const base = useMemo(() => {
    // Um item por criativo (anúncios de mesmo nome somados), não um por anúncio/conjunto.
    const ids = [...new Set(d.dias.map((x) => idDoCriativo(d.idx, x.anuncioId)))];
    return ids.map((id) => {
      const doCriativo = new Set(anunciosDoCriativo(d.idx, id));
      return {
        chave: id, anuncioId: id, rotulo: d.idx.anuncio.get(id)?.nome ?? 'Criativo sem nome',
        valor: card.medir(filtrarDias(d.dias.filter((x) => doCriativo.has(x.anuncioId)), d.idx, { funil: 'todos', canal: 'todos' }), d.linhas.filter((l) => l.anuncioId !== null && doCriativo.has(l.anuncioId))),
      };
    });
  }, [d, card]);
  const ordenada = useMemo(() => [...base].sort((a, b) => {
    if (a.valor === null) return b.valor === null ? 0 : 1;
    if (b.valor === null) return -1;
    return menor ? a.valor - b.valor : b.valor - a.valor;
  }), [base, menor]);
  const termo = busca.trim().toLocaleLowerCase('pt-BR');
  const filtrada = termo ? ordenada.filter((l) => l.rotulo.toLocaleLowerCase('pt-BR').includes(termo)) : ordenada;
  const visiveis = todos || termo ? filtrada : filtrada.slice(0, TOPO_CRIATIVOS);
  const max = Math.max(0, ...base.map((l) => (l.valor !== null && l.valor > 0 ? l.valor : 0)));

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <div className="min-w-0 flex-1"><SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} placeholder="Buscar criativo pelo nome" aria-label="Buscar criativo pelo nome" /></div>
        <Chip ativo={!menor} onClick={() => setMenor(false)}>Maior primeiro</Chip>
        <Chip ativo={menor} onClick={() => setMenor(true)}>Menor primeiro</Chip>
      </div>
      <p className="text-xs text-[var(--fg-3)]">
        {termo ? `${filtrada.length} de ${base.length} criativos.` : todos ? `Todos os ${base.length} criativos.` : `Top ${Math.min(TOPO_CRIATIVOS, base.length)} de ${base.length} criativos.`} Clique no nome para abrir o criativo.
      </p>
      <ol className="max-h-80 space-y-1 overflow-y-auto overscroll-contain pr-1">
        {visiveis.map((l, i) => (
          <li key={l.chave}>
            <button type="button" onClick={() => onIr(l.anuncioId)}
              className="group grid w-full grid-cols-[1.75rem_1fr_auto] items-center gap-x-2 rounded-[var(--r-md)] px-2 py-1.5 text-left hover:bg-[var(--surface-3)]">
              <span className="tabular text-xs text-[var(--fg-3)]">{i + 1}</span>
              <span className="min-w-0">
                <span className="block truncate text-sm text-[var(--fg-2)] group-hover:text-[var(--fg)]" title={l.rotulo}>{l.rotulo}</span>
                <span className="mt-1 block h-1.5 overflow-hidden rounded-full bg-[var(--surface-4)]">
                  <span className="atm-historico-barra block h-full rounded-full bg-[var(--accent)]" style={{ width: max > 0 && l.valor !== null && l.valor > 0 ? `${(l.valor / max) * 100}%` : '0%' }} />
                </span>
              </span>
              <span className="text-sm font-semibold text-[var(--fg)]"><Numero valor={l.valor} formato={card.formato} animado={false} /></span>
            </button>
          </li>
        ))}
        {visiveis.length === 0 && <li className="px-2 text-sm text-[var(--fg-3)]">{termo ? 'Nenhum criativo com esse nome.' : 'Sem dado no recorte.'}</li>}
      </ol>
      {!termo && base.length > TOPO_CRIATIVOS && (
        <button type="button" onClick={() => setTodos((t) => !t)} className="text-xs text-[var(--accent)] underline-offset-2 hover:underline max-md:min-h-11">
          {todos ? `Mostrar só o top ${TOPO_CRIATIVOS}` : `Mostrar todos os ${base.length}`}
        </button>
      )}
    </div>
  );
}
