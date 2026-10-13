'use client';

// Aba 1, Visão geral: "estamos no caminho?". Só cards, cada card abre o ModalCard com as sub-abas fixas.
// Faixa 1 placar e investimento (primeira dobra) · Faixa 2 funil macro (só C2 e C3) · Faixa 3 funis lado a lado + CPL
// por etapa. O gráfico por fase saiu da visão geral em 13/10 (pedido do Victor): fica no detalhe do card de tráfego. Razão = soma sobre soma no mesmo recorte; sem dado = "Sem dado", nunca zero.
import { useState, type ReactNode } from 'react';
import { KpiCard, Modal, ProgressBar, SectionCard } from '@/shared/ui/components';
import { cardMql, cardsGrupo, ROTULO_CRUZADO } from '../domain/grupo';
import { avaliarFaixa } from '../domain/meta';
import { diaDe } from '../domain/recorte';
import {
  agregar, connectRate, conversaoPagina, cpc, cplDo, cplPlacar, cplPorEtapa, cpm, ctr, custoPorVisualizacao,
  dividir, ehCaptacao, ehPago, farolCpl, filtrarDias, filtrarLinhas, gastoDe, ingressoGrupo, pessoasUnicas, somar,
  taxaVideo75, type Taxa as TipoTaxa,
} from '../domain/metricas';
import { FUNIS, ROTULO_FUNIL, type DesempenhoDia, type Funil, type LinhaPerfil, type Valor } from '../domain/tipos';
import { ehMqlPorProfissao, enviosMaisRecentesPorPessoa, enviosMqlMaisRecentes } from '../domain/metricas';
import type { DadosTela } from './contexto';
import { ModalCard, type CardDef, type SubAbaModal } from './ModalCard';
import { Farol, formatar, IndicadorMeta, MODAL_TELA_CHEIA, moeda, Numero, Taxa } from './pecas';
import { TabelaLeads } from './perfil/TabelaLeads';
import { investimentoCaptacao } from '../domain/custo-captacao';
import { INCLUIR_ENTRESAFRA_NO_CPL } from '../domain/decisoes';

const TODAS: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo', 'perfil'];
const TRAFEGO: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo'];
const capDias = (dias: DesempenhoDia[], d: DadosTela) => dias.filter((x) => ehCaptacao(d.idx.campanhaDoAnuncio(x.anuncioId)?.funil));
const capLinhas = (linhas: LinhaPerfil[]) => linhas.filter((l) => ehCaptacao(l.funil));
const valorTaxa = (t: TipoTaxa): Valor => t.valor;
// Funil macro: cinco colunas com linhas iguais a partir de 1280 px; abaixo, duas (três a partir de 1024) com a altura
// de cada linha, e o Ingresso no grupo (card com a lista por grupo) ocupa a linha inteira.
// Card com lista embaixo do número (Ingresso no grupo): a moldura do KpiCard vai para fora, para a lista ficar dentro
// dela em qualquer largura; a moldura do KpiCard de dentro some. A partir de 1280 px a moldura de fora ocupa a célula.
const MOLDURA_COM_LISTA = ' overflow-hidden border border-l-4 border-[var(--border)] border-l-[var(--accent)] bg-[var(--surface-2)]'
  + ' [&>*:first-child]:!rounded-none [&>*:first-child]:!border-0 [&>*:first-child]:!shadow-none';
const GRADE_MACRO = 'grid grid-cols-2 gap-3 lg:grid-cols-3 xl:auto-rows-fr xl:grid-cols-5';
function Cartao({ onAbrir, titulo, children, cheio = false }: { onAbrir?: () => void; titulo: string; children: ReactNode; cheio?: boolean | 'xl' }) {
  // `cheio`: o card ocupa a altura toda da célula (grade com linhas iguais no funil macro). 'xl': card com lista embaixo
  // do número; só a moldura de fora ocupa a célula (a partir de 1280 px), o KpiCard e a lista ficam com a altura natural.
  const altura = cheio === 'xl' ? ' xl:h-full' + MOLDURA_COM_LISTA : cheio ? ' h-full [&>*]:h-full' : '';
  if (!onAbrir) return <div className={'min-w-0' + altura}>{children}</div>;
  return (
    <div role="button" tabIndex={0} aria-label={`Abrir detalhe: ${titulo}`} onClick={onAbrir}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onAbrir(); } }}
      className={'atm-historico-card atm-historico-interativo min-w-0 cursor-pointer' + altura + '  rounded-[var(--r-lg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]'}>
      {children}
    </div>
  );
}

function EtapaFechada({ titulo, gasto, leads, cpl, aberta, onToggle, onAbrir, children }: {
  titulo: string; gasto: Valor; leads: Valor; cpl: { valor: Valor; gasto: Valor; leadsPagos: number } | null;
  aberta: boolean; onToggle: () => void; onAbrir: () => void; children: ReactNode;
}) {
  return (
    <section className="overflow-hidden rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]">
      <button type="button" aria-expanded={aberta} onClick={onToggle}
        className="atm-historico-interativo flex min-h-14 w-full flex-wrap items-center gap-x-4 gap-y-2 p-3 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
        <span className="min-w-32 flex-1 font-semibold text-[var(--fg)]">{titulo}</span>
        <span className="text-xs text-[var(--fg-2)]">Investimento <strong className="ml-1 tabular text-[var(--fg)]"><Numero valor={gasto} formato="brl" animado={false} /></strong></span>
        {leads !== null && <span className="text-xs text-[var(--fg-2)]">Leads pagos <strong className="ml-1 tabular text-[var(--fg)]">{formatar(leads, 'int')}</strong></span>}
        {cpl?.valor !== null && cpl && <span className="text-xs text-[var(--fg-2)]">CPL <strong className="ml-1 tabular text-[var(--fg)]">{moeda(cpl.valor)}</strong></span>}
        <span aria-hidden="true" className="ml-auto text-lg leading-none text-[var(--accent)]">{aberta ? '−' : '+'}</span>
      </button>
      {aberta && (
        <div className="border-t border-[var(--border)] p-3">
          {children}
          <button type="button" onClick={onAbrir}
            className="mt-3 min-h-10 rounded-[var(--r-md)] border border-[var(--border-accent)] px-3 text-sm font-semibold text-[var(--accent)] hover:bg-[var(--accent-subtle)]">
            Ver campanhas e conjuntos
          </button>
        </div>
      )}
    </section>
  );
}

function tempoAte(alvo: string, agora: Date): string {
  const ms = Date.parse(alvo) - agora.getTime();
  if (!Number.isFinite(ms)) return 'Sem dado';
  if (ms <= 0) return 'Já começou';
  const dias = Math.floor(ms / 86_400_000); const horas = Math.floor((ms % 86_400_000) / 3_600_000);
  return dias > 0 ? `${dias} d ${horas} h` : `${horas} h ${Math.floor((ms % 3_600_000) / 60_000)} min`;
}
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

/** Tabela aberta por um card que não tem as sub-abas do ModalCard (os números vêm prontos do servidor). */
interface TabelaAberta { titulo: string; nota: string; linhas: LinhaPerfil[] }

/** Card MQLs: total e % sobre os leads únicos (dados_black_grupo.leads). */
function CardMql({ d, onAbrir }: { d: DadosTela; onAbrir: () => void }) {
  const g = d.grupo.data;
  const falta = d.grupo.motivo ?? d.grupo.aviso ?? 'leads do grupo';
  const c = g ? cardMql(g) : null;
  return (
    <Cartao cheio titulo="MQLs" onAbrir={onAbrir}>
      <KpiCard label="MQLs" title="dados_black_grupo: leads.mql e leads.unicos (pessoas únicas do período e do nó, sem teste)."
        value={<span className="inline-flex flex-wrap items-baseline gap-x-2"><Numero valor={c?.total ?? null} formato="int" falta={falta} />{c && <IndicadorMeta valor={c.taxa.valor} meta={d.config.metas.mql} formato="pct" />}</span>}
        hint={c ? `${c.taxa.valor === null ? 'Sem dado' : formatar(c.taxa.valor, 'pct')} dos leads (${formatar(c.taxa.num, 'int')} ÷ ${formatar(c.taxa.den, 'int')}).` : falta} />
      {c && d.grupo.descricao && <p className="-mt-2 px-4 pb-3 text-xs text-[var(--fg-3)]">Recorte: {d.grupo.descricao}</p>}
    </Cartao>
  );
}

/** Card Ingresso no grupo: taxa geral MQL e uma linha por grupo (dados_black_grupo). */
function CardIngresso({ d, onAbrir }: { d: DadosTela; onAbrir: () => void }) {
  const g = d.grupo.data;
  const falta = d.grupo.motivo ?? d.grupo.aviso ?? 'grupo';
  const c = g ? cardsGrupo(g) : null;
  return (
    <Cartao cheio="xl" titulo="Ingresso no grupo" onAbrir={onAbrir}>
      <KpiCard label="Ingresso no grupo" title="Únicos nos grupos de Advogados e Contadores ÷ leads MQL (dados_black_grupo)."
        value={c ? <span className="inline-flex flex-wrap items-baseline gap-x-2"><Taxa taxa={c.geral} className="text-3xl font-bold tracking-tight text-[var(--fg)] no-underline" /><IndicadorMeta valor={c.geral.valor} meta={d.config.metas.ingressoGrupo} formato="pct" /></span> : <Numero valor={null} formato="pct" falta={falta} />}
        hint={c ? (c.cruzado ? ROTULO_CRUZADO : 'MQL no grupo ÷ leads MQL.') : falta} />
      {c?.geral.valor !== null && c?.geral.valor !== undefined && (
        <div className="-mt-2 px-4 pb-3"><ProgressBar value={c.geral.valor * 100} ariaLabel={`Ingresso no grupo ${formatar(c.geral.valor, 'pct')}`} /></div>
      )}
      {c && (
        <ul className="-mt-2 px-4 pb-3 text-xs">
          {c.linhas.map((x) => (
            <li key={x.segmento} className="flex items-baseline justify-between gap-2 py-0.5">
              <span className="text-[var(--fg-3)]">{x.rotulo}</span>
              <span className="text-right text-[var(--fg)]"><Taxa taxa={x.taxa} /> <span className="text-[var(--fg-3)]">{formatar(x.taxa.num, 'int')} ÷ {formatar(x.taxa.den, 'int')}</span></span>
            </li>
          ))}
          {d.grupo.descricao && <li className="pt-1 text-[var(--fg-3)]">Recorte: {d.grupo.descricao}</li>}
        </ul>
      )}
    </Cartao>
  );
}

export function AbaVisaoGeral({ d }: { d: DadosTela }) {
  const [aberto, setAberto] = useState<CardDef | null>(null);
  const [etapaAberta, setEtapaAberta] = useState<string | null>(null);
  const [tabela, setTabela] = useState<TabelaAberta | null>(null);
  // Sem fonte de cadastros, número de lead é "Sem dado" (nunca o zero de uma lista vazia).
  const semLeads = d.perfilSemDado;
  const { config, idx, recorte } = d;
  const filtro = { funil: recorte.funil, canal: recorte.canal };
  const abrir = (c: CardDef) => () => setAberto(c);

  // ─── Faixa 1: placar (do início até agora) ──────────────────────────────────────────────────────────────
  const diasAteHoje = filtrarDias(d.diasTodos, idx, filtro);
  const linhasAteAgora = filtrarLinhas(d.linhasTodas, filtro);
  const leadsAteAgora: Valor = semLeads ? null : pessoasUnicas(linhasAteAgora);
  const gastoAteHoje = gastoDe(diasAteHoje);
  const placar = cplPlacar(d.dias, d.linhas, idx, d.trafegoPeriodo.gastoCampanhas, INCLUIR_ENTRESAFRA_NO_CPL, filtro);

  const cardLeads: CardDef = { id: 'leads', rotulo: 'Leads (pessoas únicas)', formato: 'int', medir: (_, l) => pessoasUnicas(l), aplica: TODAS,
    dica: 'No detalhe, o recorte é o período escolhido no topo. Uma pessoa com duas portas conta uma vez.' };
  const cardCpl: CardDef = { id: 'cpl', rotulo: 'CPL geral', formato: 'brl', medir: (x, l) => cplPlacar(x, l, idx, d.trafegoPeriodo.gastoCampanhas, INCLUIR_ENTRESAFRA_NO_CPL, filtro).valor, aplica: TRAFEGO, menorMelhor: true,
    dica: 'Investimento em captação C2/C3 ÷ leads pagos dessas etapas, no mesmo período. Remarketing fica fora. Entresafra desligada até importação dos leads daquele período.' };
  const cardGasto: CardDef = { id: 'gasto', rotulo: 'Gasto de tráfego', formato: 'brl', medir: (x) => (x.length ? gastoDe(x) : null), aplica: TRAFEGO,
    dica: 'No detalhe, o recorte é o período escolhido no topo.' };

  // ─── Faixa 2: investimento (período) ────────────────────────────────────────────────────────────────────
  const gastoPeriodo = gastoDe(d.dias);
  const porCanal = (c: 'meta' | 'google') => gastoDe(filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: recorte.funil, canal: c }));
  const disparoAplica = recorte.funil === 'todos' && recorte.canal === 'todos';
  const custoDisparo = d.mensageria ? somar(d.mensageria.canais.map((c) => c.custo)) : null;
  const total = disparoAplica && custoDisparo?.valor != null ? gastoPeriodo + custoDisparo.valor : gastoPeriodo;
  const notaTotal = !disparoAplica ? 'Disparo não se divide por funil nem canal: fora da soma.'
    : custoDisparo?.valor == null ? 'Custo de disparo sem dado: fora da soma.' : 'Tráfego + disparo (disparo fictício).';
  const custoCanal = (k: 'api' | 'sms' | 'ligacao') => d.mensageria?.canais.find((c) => c.canal === k)?.custo ?? null;

  // ─── Faixa 3: funil macro (só captação) ─────────────────────────────────────────────────────────────────
  const dCap = capDias(d.dias, d); const lCap = capLinhas(d.linhas);
  const aCap = agregar(dCap);
  const medirCap = (f: (a: ReturnType<typeof agregar>) => Valor) => (x: DesempenhoDia[]) => { const c = capDias(x, d); return c.length ? f(agregar(c)) : null; };
  // Ordem pedida pelo Victor (12/10): Impressões, CPM, Cliques, CTR, CPC, Visualizações, Connect, Inscrições, Conversão. O card Grupo em 48h saiu em 13/10: fica a taxa de Ingresso no grupo.
  const cards3: { c: CardDef; valor: ReactNode; hint?: string }[] = [
    { c: { id: 'imp', rotulo: 'Impressões', formato: 'int', medir: medirCap((a) => a.impressoes), aplica: TRAFEGO }, valor: <Numero valor={dCap.length ? aCap.impressoes : null} formato="int" /> },
    { c: { id: 'cpm', rotulo: 'CPM', formato: 'brl', medir: medirCap(cpm), aplica: TRAFEGO, menorMelhor: true, dica: 'Custo por mil impressões: gasto ÷ impressões × 1000.' }, valor: <Numero valor={dCap.length ? cpm(aCap) : null} formato="brl" />, hint: dCap.length ? `Gasto diário por anúncio: ${moeda(aCap.gasto)} ÷ ${formatar(aCap.impressoes, 'int')} impressões × 1.000.` : 'Sem dado de gasto ou impressões no período.' },
    { c: { id: 'cliques', rotulo: 'Cliques no link', formato: 'int', medir: (x) => agregar(capDias(x, d)).cliques.valor, aplica: TRAFEGO }, valor: <Numero valor={aCap.cliques.valor} formato="int" /> },
    { c: { id: 'ctr', rotulo: 'CTR', formato: 'pct', medir: (x) => valorTaxa(ctr(agregar(capDias(x, d)))), aplica: TRAFEGO, dica: 'Cliques no link ÷ impressões.' }, valor: <Taxa taxa={ctr(aCap)} /> },
    { c: { id: 'cpc', rotulo: 'CPC', formato: 'brl', medir: medirCap(cpc), aplica: TRAFEGO, menorMelhor: true, dica: 'Custo por clique: gasto ÷ cliques no link, só nas linhas com clique medido.' }, valor: <Numero valor={dCap.length ? cpc(aCap) : null} formato="brl" />, hint: 'Custo por clique no link.' },
    { c: { id: 'lpv', rotulo: 'Visualizações da página', formato: 'int', medir: (x) => agregar(capDias(x, d)).lpv.valor, aplica: TRAFEGO }, valor: <Numero valor={aCap.lpv.valor} formato="int" />, hint: aCap.lpv.conhecidos < aCap.lpv.total ? 'Parcial: Google sem LPV.' : undefined },
    { c: { id: 'connect', rotulo: 'Connect rate', formato: 'pct', medir: (x) => valorTaxa(connectRate(x, idx)), aplica: TRAFEGO, dica: 'Σ views da página ÷ Σ cliques, só nas linhas com as duas métricas.' }, valor: <Taxa taxa={connectRate(d.dias, idx)} /> },
    { c: { id: 'insc', rotulo: 'Inscrições', formato: 'int', medir: (_, l) => capLinhas(l).length, aplica: TODAS, dica: 'Cadastros de C2 e C3 (todas as portas).' }, valor: <Numero valor={semLeads ? null : lCap.length} formato="int" falta={d.avisoPerfil ?? undefined} />, hint: `${formatar(lCap.filter((l) => l.origem === 'pago').length, 'int')} de tráfego pago` },
    { c: { id: 'conv', rotulo: 'Conversão da página', formato: 'pct', medir: (x, l) => valorTaxa(conversaoPagina(x, l, idx)), aplica: TRAFEGO, dica: 'Inscrições pagas ÷ views da página, dos mesmos anúncios.' }, valor: <Taxa taxa={conversaoPagina(d.dias, d.linhas, idx)} /> },
  ];

  // Indicador de meta (bom/ruim + % da meta) dos cards com fórmula. Metas: Victor, 13/10/2026 (config.metas).
  const m = config.metas;
  const estadoCpl = avaliarFaixa(placar.valor, config.reguaCpl?.meta ?? null, config.cplAlvoMedio).estado;
  const indicador: Record<string, ReactNode> = {
    cpm: <IndicadorMeta valor={dCap.length ? cpm(aCap) : null} meta={m.cpm} menorMelhor formato="brl" />,
    ctr: <IndicadorMeta valor={ctr(aCap).valor} meta={m.ctr} formato="pct" />,
    cpc: <IndicadorMeta valor={dCap.length ? cpc(aCap) : null} meta={m.cpc} menorMelhor formato="brl" />,
    connect: <IndicadorMeta valor={connectRate(d.dias, idx).valor} meta={m.connectRate} formato="pct" />,
    conv: <IndicadorMeta valor={conversaoPagina(d.dias, d.linhas, idx).valor} meta={m.conversaoPagina} formato="pct" />,
  };

  // Tabelas dos cards MQLs e Ingresso: os envios do período e do nó (cada envio é uma linha; o card conta pessoas).
  const linhasMql = enviosMqlMaisRecentes(d.linhas);
  const linhasGrupo = d.linhas.filter((l) => l.entrouGrupoEm !== null && diaDe(l.entrouGrupoEm) >= d.periodo.de && diaDe(l.entrouGrupoEm) <= d.periodo.ate);
  const abrirMql = () => setTabela({ titulo: 'MQLs', linhas: linhasMql,
    nota: 'Envios de advogado, contador ou estudante de Direito no período e no nó. O card conta pessoas únicas (a classe é a do envio mais recente com profissão).' });
  const abrirGrupo = () => setTabela({ titulo: 'Ingresso no grupo', linhas: linhasGrupo,
    nota: 'Envios do período e do nó cuja pessoa entrou no grupo dentro do período. O card conta telefones únicos por grupo.' });

  // ─── Faixa 4: funis lado a lado ─────────────────────────────────────────────────────────────────────────
  const diasCanal = filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: 'todos', canal: recorte.canal });
  const linhasCanal = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', canal: recorte.canal });
  const etapas = cplPorEtapa(d.dias, d.linhas, idx, d.trafegoPeriodo.gastoCampanhas);
  const investimento = investimentoCaptacao(d.trafegoPeriodo, d.periodo);
  const rotuloInvestimentoCanal = (nome: string, completo: Valor, medido: Valor, campanhasMedidas: number, campanhasTotal: number, semFonte: boolean) => {
    if (campanhasTotal === 0) return `${nome} sem campanha · ${moeda(0)}`;
    if (completo !== null) return `${nome} ${moeda(completo)}`;
    if (medido !== null) return `${nome} ${moeda(medido)} medidos (${campanhasMedidas}/${campanhasTotal} campanhas); parcial`;
    return `${nome} ${semFonte ? 'sem fonte' : 'sem dado'}`;
  };
  const detalheInvestimento = [
    rotuloInvestimentoCanal('Meta Ads', investimento.meta, investimento.metaMedido, investimento.campanhasMetaMedidas, investimento.campanhasMetaTotal, investimento.campanhasMeta.length === 0),
    rotuloInvestimentoCanal('Google Ads', investimento.google, investimento.googleMedido, investimento.campanhasGoogleMedidas, investimento.campanhasGoogleTotal, investimento.campanhasGoogle.length === 0),
  ].join(' · ');
  const notaZeroConfirmado = investimento.campanhasZeroConfirmado.length
    ? ` Sem entrega, coleta do Meta concluída até 13/10 às 20:15 BRT: ${investimento.campanhasZeroConfirmado.join('; ')} = R$ 0,00.`
    : '';
  const c1Dias = filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: 'c1', canal: recorte.canal });
  const abrirEtapa = (funil: Funil) => d.irPara({ aba: 'criativos', funil, criativos: {} });

  return (
    <div className="space-y-5">
      <section aria-labelledby="vg-placar">
        <h2 id="vg-placar" className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Placar</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <KpiCard label="Até a live" value={config.liveEm ? tempoAte(config.liveEm, d.agora) : 'Sem dado'}
            hint={config.liveEm ? `Live em ${dataHora(config.liveEm)}` : 'Data da live sem cadastro.'} bar={config.liveEm ? 'purple' : 'gray'} />
          <Cartao titulo={cardLeads.rotulo} onAbrir={abrir(cardLeads)}>
            <KpiCard label="Leads contra a meta" bar="accent" title={config.fontes.plano}
              value={<><Numero valor={leadsAteAgora} formato="int" falta={d.avisoPerfil ?? undefined} /> <span className="text-sm font-normal text-[var(--fg-3)]">de {config.metaLeads === null ? 'meta sem cadastro' : formatar(config.metaLeads, 'int')}</span></>}
              hint={`Pessoas únicas do início até agora. ${config.metaLeads === null ? 'Meta: Sem dado.' : `${formatar(dividir(leadsAteAgora, config.metaLeads), 'pct')} da meta.`}`} />
            {config.metaLeads !== null && leadsAteAgora !== null && (
              <div className="-mt-2 px-4 pb-3"><ProgressBar value={(leadsAteAgora / config.metaLeads) * 100} ariaLabel={`${formatar(leadsAteAgora, 'int')} de ${formatar(config.metaLeads, 'int')} leads`} valueNow={leadsAteAgora} valueMin={0} valueMax={config.metaLeads} /></div>
            )}
          </Cartao>
          <Cartao titulo={cardCpl.rotulo} onAbrir={abrir(cardCpl)}>
            <KpiCard label="CPL geral" bar={estadoCpl === 'sem' ? 'gray' : estadoCpl === 'bom' ? 'green' : estadoCpl === 'atencao' ? 'yellow' : 'red'}
              value={<span className="inline-flex items-center gap-2"><Numero valor={placar.valor} formato="brl" falta="sem leads pagos no recorte" /><IndicadorMeta valor={placar.valor} ideal={config.reguaCpl?.meta ?? null} meta={config.cplAlvoMedio} formato="brl" /></span>}
              hint={`Captação C2/C3 ÷ leads pagos C2/C3: ${moeda(placar.gasto)} ÷ ${formatar(placar.leadsPagos, 'int')}. Entresafra excluída. Alvo ${config.cplAlvoMedio === null ? 'sem cadastro' : moeda(config.cplAlvoMedio)}.`} />
          </Cartao>
          <Cartao titulo={cardGasto.rotulo} onAbrir={abrir(cardGasto)}>
            <KpiCard label="Verba contra o orçamento" bar="yellow"
              value={<><Numero valor={gastoAteHoje} formato="brl" /> <span className="text-sm font-normal text-[var(--fg-3)]">de {config.orcamentoTotal === null ? 'orçamento sem cadastro' : moeda(config.orcamentoTotal)}</span></>}
              hint={`Tráfego do início até hoje. ${config.orcamentoTotal === null ? 'Orçamento: Sem dado.' : `${formatar(dividir(gastoAteHoje, config.orcamentoTotal), 'pct')} do orçamento.`}`} />
            {config.orcamentoTotal !== null && (
              <div className="-mt-2 px-4 pb-3"><ProgressBar value={(gastoAteHoje / config.orcamentoTotal) * 100} tone="yellow" ariaLabel={`${moeda(gastoAteHoje)} de ${moeda(config.orcamentoTotal)}`} /></div>
            )}
          </Cartao>
        </div>
        {/* Investimento do período, na mesma faixa do placar: os sete cards ficam na primeira dobra (pedido de 13/10). */}
        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-3">
          <KpiCard label="Investimento total" value={<Numero valor={total} formato="brl" />} hint={notaTotal} bar="accent" />
          <Cartao titulo="Tráfego" onAbrir={abrir(cardGasto)}>
            <KpiCard label="Investimento em tráfego" value={<Numero valor={d.dias.length ? gastoPeriodo : null} formato="brl" />} hint={`Meta ${moeda(porCanal('meta'))} · Google ${moeda(porCanal('google'))}`} bar="accent" />
          </Cartao>
          <Cartao titulo="Disparo" onAbrir={() => d.irPara({ aba: 'mensageria' })}>
            <KpiCard label="Investimento com disparo" bar="purple"
              value={<Numero valor={custoDisparo?.valor ?? null} formato="brl" falta="custo de disparo" />}
              hint={`API ${moeda(custoCanal('api'))} · SMS ${moeda(custoCanal('sms'))} · Ligação ${moeda(custoCanal('ligacao'))}`} />
          </Cartao>
        </div>
      </section>

      <section aria-labelledby="vg-funil">
        <h2 id="vg-funil" className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil macro</h2>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Só C2 e C3. C1 fora (distribuição).</p>
        {recorte.funil === 'c1' ? (
          <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">O C1 é distribuição: não tem página, inscrição nem connect rate. Veja os funis lado a lado abaixo.</p>
        ) : (
          <>
            <ol className={GRADE_MACRO}>
              <li key="investimento-captacao" className="min-w-0">
                <Cartao cheio titulo="Investimento em captação">
                  <KpiCard label="Investimento em captação" bar="accent"
                    value={<Numero valor={investimento.total} formato="brl" falta="sem dado no período" />}
                    hint={`${detalheInvestimento}. Total ${investimento.total === null ? 'sem dado por fonte incompleta' : 'das campanhas C2/C3'}.${notaZeroConfirmado} Sem remarketing. Inclui Entresafra, excluída do CPL geral.`} />
                </Cartao>
              </li>
              {cards3.flatMap(({ c, valor, hint }) => [
                <li key={c.id} className="min-w-0"><Cartao cheio titulo={c.rotulo} onAbrir={abrir(c)}><KpiCard label={c.rotulo} value={indicador[c.id] ? <span className="inline-flex flex-wrap items-baseline gap-x-2">{valor}{indicador[c.id]}</span> : valor} hint={hint} /></Cartao></li>,
                // MQLs logo depois da conversão da página; o Ingresso no grupo vem em seguida (pedido de 13/10).
                ...(c.id === 'conv' ? [
                  <li key="mql" className="min-w-0"><CardMql d={d} onAbrir={abrirMql} /></li>,
                  <li key="ingresso" className="col-span-2 min-w-0 lg:col-span-3 xl:col-span-1"><CardIngresso d={d} onAbrir={abrirGrupo} /></li>,
                ] : []),
              ])}
            </ol>
            <div className={'mt-3 ' + GRADE_MACRO}>
              <Cartao cheio titulo="Presença na live"><KpiCard label="Presença na live" value={<Numero valor={d.marcos?.presencaLive ?? null} formato="int" falta="presença da live ainda sem fonte" />} bar="gray" /></Cartao>
              <Cartao cheio titulo="Vendas"><KpiCard label="Vendas" value={<Numero valor={d.marcos?.vendas ?? null} formato="int" falta="vendas ainda sem fonte" />} bar="gray" /></Cartao>
            </div>
          </>
        )}
      </section>

      <section aria-labelledby="vg-lado">
        <h2 id="vg-lado" className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funis lado a lado</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {FUNIS.map((f) => {
            const df = filtrarDias(diasCanal, idx, { funil: f, canal: 'todos' });
            const lf = filtrarLinhas(linhasCanal, { funil: f, canal: 'todos' });
            const apagado = recorte.funil !== 'todos' && recorte.funil !== f;
            return (
              <SectionCard key={f} title={ROTULO_FUNIL[f]} className={apagado ? 'opacity-40' : ''}
                right={<button type="button" className="text-xs text-[var(--accent)] underline-offset-2 hover:underline max-md:-my-3 max-md:-mr-3 max-md:min-h-11 max-md:px-3" onClick={() => d.irPara({ funil: f })}>Filtrar</button>}>
                {f === 'c1' ? <ColunaC1 d={d} dias={df} /> : <ColunaCaptacao d={d} dias={df} linhas={lf} funil={f} />}
              </SectionCard>
            );
          })}
        </div>

        <SectionCard className="mt-3" title="CPL por etapa" subtitle={`Abra uma etapa para ver o cálculo e os detalhes de campanha. ${config.reguaCpl ? `Farol: meta ${moeda(config.reguaCpl.meta)}, teto ${moeda(config.reguaCpl.teto)}.` : 'Farol: régua de CPL sem cadastro.'}`}>
          <div className="space-y-2">
            <EtapaFechada titulo="C1 · Distribuição" gasto={c1Dias.length ? gastoDe(c1Dias) : null} leads={null} cpl={null}
              aberta={etapaAberta === 'c1'} onToggle={() => setEtapaAberta((v) => v === 'c1' ? null : 'c1')}
              onAbrir={() => abrirEtapa('c1')}>
              <CampanhasC1 d={d} />
              <AlcanceFrequenciaCampanhas d={d} funil="c1" />
            </EtapaFechada>
            {(['consultoria', 'iscas', 'c3'] as const).map((funil) => {
              const chave = funil === 'consultoria' ? 'consultoria' : funil;
              const principal = etapas.find((e) => e.chave === chave)?.cpl ?? null;
              const rotulo = funil === 'consultoria' ? 'Consultoria' : funil === 'iscas' ? 'Iscas' : 'C3';
              const itens = etapas.filter((e) => e.funil === funil && e.nivel !== 'etapa');
              const gasto = principal?.gasto;
              return (
                <EtapaFechada key={funil} titulo={rotulo} gasto={gasto != null && (gasto > 0 || principal?.leadsPagos) ? gasto : null}
                  leads={principal?.leadsPagos ?? null} cpl={principal} aberta={etapaAberta === funil}
                  onToggle={() => setEtapaAberta((v) => v === funil ? null : funil)} onAbrir={() => abrirEtapa(funil)}>
                  {funil === 'consultoria' && <AlcanceFrequenciaCampanhas d={d} funil="consultoria" />}
                  <CampanhasEtapa d={d} funil={funil} />
                  {itens.map((e) => (
                    <div key={e.chave} className="flex flex-wrap items-center justify-between gap-2 border-t border-[var(--border-faint)] py-2 text-sm">
                      <span className="min-w-0 break-words font-medium text-[var(--fg-2)]">{e.rotulo}</span>
                      <span className="flex flex-wrap items-center gap-3 text-xs text-[var(--fg-2)]">
                        <span>Investimento <Numero valor={e.cpl.gasto !== null && e.cpl.gasto > 0 ? e.cpl.gasto : null} formato="brl" animado={false} /></span>
                        <span>Leads pagos <Numero valor={e.cpl.leadsPagos > 0 ? e.cpl.leadsPagos : null} formato="int" animado={false} /></span>
                        {e.cpl.valor !== null && <span className="font-semibold text-[var(--fg)]">CPL {moeda(e.cpl.valor)}</span>}
                      </span>
                    </div>
                  ))}
                  {principal?.valor !== null && principal && principal.gasto !== null && <p className="border-t border-[var(--border-faint)] py-2 text-xs text-[var(--fg-2)]">Cálculo do CPL: {moeda(principal.gasto)} ÷ {formatar(principal.leadsPagos, 'int')} leads pagos.</p>}
                </EtapaFechada>
              );
            })}
          </div>
        </SectionCard>
      </section>

      <SemEtapa d={d} />

      <ModalCard d={d} card={aberto} onClose={() => setAberto(null)} />
      {tabela && (
        <Modal open onClose={() => setTabela(null)} title={tabela.titulo} width={`max-w-5xl ${MODAL_TELA_CHEIA}`}>
          <p className="mb-2 text-xs text-[var(--fg-3)]">{tabela.nota}</p>
          <TabelaLeads d={d} linhas={tabela.linhas} />
        </Modal>
      )}
    </div>
  );
}

function Linha({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <div className="flex items-baseline justify-between gap-3 py-1 text-sm"><span className="text-[var(--fg-3)]">{rotulo}</span><span className="text-right text-[var(--fg)]">{children}</span></div>;
}

function CampanhasEtapa({ d, funil }: { d: DadosTela; funil: Funil }) {
  const campanhas = d.trafegoPeriodo.campanhas.filter((c) => (funil === 'iscas'
    ? c.funil === 'c3' && c.fase === 'captacao' && (c.subtipo === 'ISCA' || d.trafegoPeriodo.conjuntos.some((j) => j.campanhaId === c.id && j.isca !== null))
    : c.funil === funil && c.fase === 'captacao'));
  if (campanhas.length === 0) return <p className="py-2 text-xs text-[var(--fg-3)]">Sem campanha de captação com dado neste recorte.</p>;
  return (
    <ul className="divide-y divide-[var(--border-faint)]">
      {campanhas.map((campanha) => {
        const dias = d.dias.filter((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id === campanha.id);
        const leads = d.linhas.filter((l) => l.campanhaId === campanha.id && ehPago(l));
        const custo = d.trafegoPeriodo.gastoCampanhas === undefined
          ? dias.length ? gastoDe(dias) : null
          : d.trafegoPeriodo.gastoCampanhas.find((x) => x.campanhaId === campanha.id)?.gasto ?? null;
        const resultado = custo !== null && leads.length ? custo / leads.length : null;
        const conhecidos = enviosMaisRecentesPorPessoa(leads);
        const mql = conhecidos.length ? dividir(conhecidos.filter(ehMqlPorProfissao).length, conhecidos.length) : null;
        const agregado = agregar(dias);
        return (
          <li key={campanha.id} className="py-2">
            <p className="break-words text-sm font-medium text-[var(--fg)]">{campanha.nome}</p>
            <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
              <Par rotulo="Investimento"><Numero valor={custo} formato="brl" animado={false} /></Par>
              <Par rotulo="Leads pagos"><Numero valor={leads.length} formato="int" animado={false} /></Par>
              {resultado !== null && <Par rotulo="CPL"><Numero valor={resultado} formato="brl" animado={false} /></Par>}
              <Par rotulo="CTR"><Taxa taxa={ctr(agregado)} /></Par>
              <Par rotulo="Views da página"><Numero valor={agregado.lpv.valor} formato="int" animado={false} /></Par>
              {mql !== null && <Par rotulo="% MQL dos pagos"><Numero valor={mql} formato="pct" animado={false} /></Par>}
            </div>
            <DetalhesConjuntos d={d} campanhaId={campanha.id} distribuicao={false} />
          </li>
        );
      })}
    </ul>
  );
}

function CampanhasC1({ d }: { d: DadosTela }) {
  const campanhas = d.trafegoPeriodo.campanhas.filter((c) => c.funil === 'c1'
    && d.dias.some((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id === c.id));
  if (campanhas.length === 0) return <p className="py-2 text-xs text-[var(--fg-3)]">Sem campanha C1 com dado neste recorte.</p>;
  return <ul className="divide-y divide-[var(--border-faint)]">{campanhas.map((campanha) => {
    const dias = d.dias.filter((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id === campanha.id);
    const a = agregar(dias);
    const gasto = d.trafegoPeriodo.gastoCampanhas?.find((x) => x.campanhaId === campanha.id)?.gasto ?? (dias.length ? gastoDe(dias) : null);
    return <li key={campanha.id} className="py-2">
      <p className="break-words text-sm font-medium text-[var(--fg)]">{campanha.nome}</p>
      <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
        <Par rotulo="Investimento"><Numero valor={gasto} formato="brl" animado={false} /></Par>
        <Par rotulo="Impressões"><Numero valor={dias.length ? a.impressoes : null} formato="int" animado={false} /></Par>
        <Par rotulo="Cliques"><Numero valor={a.cliques.valor} formato="int" animado={false} /></Par>
        <Par rotulo="CPM"><Numero valor={dias.length ? cpm(a) : null} formato="brl" animado={false} /></Par>
        <Par rotulo="Custo por visualização"><Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} /></Par>
      </div>
      <DetalhesConjuntos d={d} campanhaId={campanha.id} distribuicao />
    </li>;
  })}</ul>;
}

function DetalhesConjuntos({ d, campanhaId, distribuicao }: { d: DadosTela; campanhaId: string; distribuicao: boolean }) {
  const conjuntos = d.trafegoPeriodo.conjuntos.filter((cj) => cj.campanhaId === campanhaId);
  const linhas = conjuntos.map((cj) => {
    const ids = new Set(d.trafegoPeriodo.anuncios.filter((a) => a.conjuntoId === cj.id).map((a) => a.id));
    const dias = d.dias.filter((dia) => ids.has(dia.anuncioId));
    const leads = d.linhas.filter((l) => l.conjuntoId === cj.id && ehPago(l));
    return { cj, dias, leads };
  }).filter((x) => x.dias.length > 0 || x.leads.length > 0);
  if (linhas.length === 0) return null;
  return <ul className="mt-2 divide-y divide-[var(--border-faint)] border-l-2 border-[var(--border)] pl-3">
    {linhas.map(({ cj, dias, leads }) => {
      const a = agregar(dias);
      const custo = dias.length ? gastoDe(dias) : null;
      const conhecidos = enviosMaisRecentesPorPessoa(leads);
      const mql = conhecidos.length ? dividir(conhecidos.filter(ehMqlPorProfissao).length, conhecidos.length) : null;
      const cplSet = custo !== null && leads.length > 0 ? custo / leads.length : null;
      return <li key={cj.id} className="py-2">
        <p className="break-words text-xs font-medium text-[var(--fg-2)]">{cj.nome}</p>
        <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
          <Par rotulo="Investimento"><Numero valor={custo} formato="brl" animado={false} /></Par>
          <Par rotulo="Impressões"><Numero valor={dias.length ? a.impressoes : null} formato="int" animado={false} /></Par>
          <Par rotulo="Cliques"><Numero valor={a.cliques.valor} formato="int" animado={false} /></Par>
          <Par rotulo="CTR"><Taxa taxa={ctr(a)} /></Par>
          {!distribuicao && <>
            <Par rotulo="Leads pagos"><Numero valor={leads.length} formato="int" animado={false} /></Par>
            {leads.length > 0 && cplSet !== null && <Par rotulo="CPL"><Numero valor={cplSet} formato="brl" animado={false} /></Par>}
            {mql !== null && <Par rotulo="% MQL dos pagos"><Numero valor={mql} formato="pct" animado={false} /></Par>}
            <Par rotulo="Views da página"><Numero valor={a.lpv.valor} formato="int" animado={false} /></Par>
          </>}
          {distribuicao && <>
            <Par rotulo="CPM"><Numero valor={dias.length ? cpm(a) : null} formato="brl" animado={false} /></Par>
            <Par rotulo="Custo por visualização"><Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} /></Par>
          </>}
        </div>
      </li>;
    })}
  </ul>;
}

function Par({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <span className="flex min-w-0 flex-col"><span className="truncate text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</span><span className="text-[var(--fg)]">{children}</span></span>;
}

function AlcanceFrequenciaCampanhas({ d, funil }: { d: DadosTela; funil: Funil }) {
  const campanhas = d.trafegoPeriodo.campanhas.filter((c) => c.funil === funil);
  return (
    <div className="mt-2 space-y-2 border-t border-[var(--border-faint)] pt-2">
      {campanhas.length === 0 ? (
        <p className="text-xs text-[var(--fg-3)]">Alcance e frequência: Sem dado, sem campanha com veiculação neste funil.</p>
      ) : campanhas.map((campanha) => {
        const t = d.totaisPeriodo.find((x) => x.nivel === 'campanha' && x.id === campanha.id);
        return (
          <div key={campanha.id} className="grid grid-cols-2 gap-x-3 text-xs">
            <p className="col-span-2 break-words font-medium text-[var(--fg-2)]">{campanha.nome}</p>
            <p className="text-[var(--fg-3)]">Alcance <strong className="text-[var(--fg)]"><Numero valor={t?.alcance ?? null} formato="int" falta="sem total da campanha" animado={false} /></strong></p>
            <p className="text-[var(--fg-3)]">Frequência <strong className="text-[var(--fg)]"><Numero valor={t?.frequencia ?? null} formato="dec" falta="sem total da campanha" animado={false} /></strong></p>
            <p className="col-span-2 text-[11px] text-[var(--fg-3)]">Período da campanha: {t?.de && t.ate ? `de ${dataBr(t.de)} a ${dataBr(t.ate)}` : 'Sem dado'}</p>
          </div>
        );
      })}
      {campanhas.length > 1 && <p className="text-[11px] text-[var(--fg-3)]">Não há total combinado: alcance e frequência não se somam entre campanhas.</p>}
    </div>
  );
}

function ColunaC1({ d, dias }: { d: DadosTela; dias: DesempenhoDia[] }) {
  const a = agregar(dias);
  // Alcance e frequência não somam entre campanhas: só com uma campanha C1 no recorte.
  const campanhas = [...new Set(dias.map((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id).filter((x): x is string => Boolean(x)))];
  const total = campanhas.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'campanha' && t.id === campanhas[0]) : undefined;
  const falta = campanhas.length > 1 ? 'alcance não soma entre campanhas' : 'alcance do período';
  return (
    <div className="divide-y divide-[var(--border-faint)]">
      <Linha rotulo="Gasto"><Numero valor={dias.length ? a.gasto : null} formato="brl" animado={false} /></Linha>
      <Linha rotulo="Impressões"><Numero valor={dias.length ? a.impressoes : null} formato="int" animado={false} /></Linha>
      <Linha rotulo="Alcance"><Numero valor={total?.alcance ?? null} formato="int" falta={falta} animado={false} /></Linha>
      <Linha rotulo="Frequência"><Numero valor={total?.frequencia ?? null} formato="dec" falta={falta} animado={false} /></Linha>
      {total?.de && total.ate && <Linha rotulo="Período da campanha">de {dataBr(total.de)} a {dataBr(total.ate)}</Linha>}
      <Linha rotulo="CPM"><Numero valor={dias.length ? cpm(a) : null} formato="brl" animado={false} /></Linha>
      <Linha rotulo="Vídeo 75%"><Taxa taxa={taxaVideo75(a)} /></Linha>
      <Linha rotulo="Custo por visualização"><Numero valor={custoPorVisualizacao(a)} formato="brl" falta="ThruPlay" animado={false} /></Linha>
      <p className="pt-1 text-[11px] text-[var(--fg-3)]">Distribuição: sem leads nem página.</p>
    </div>
  );
}

function ColunaCaptacao({ d, dias, linhas, funil }: { d: DadosTela; dias: DesempenhoDia[]; linhas: LinhaPerfil[]; funil: Funil }) {
  const c = cplDo(dias, linhas);
  const campanhas = [...new Set(dias.map((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id).filter((x): x is string => Boolean(x)))];
  const total = campanhas.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'campanha' && t.id === campanhas[0]) : undefined;
  const falta = campanhas.length > 1 ? 'alcance não soma entre campanhas' : funil === 'consultoria' && campanhas.length === 0 ? 'sem campanha com veiculação' : 'alcance do período';
  return (
    <div className="divide-y divide-[var(--border-faint)]">
      <Linha rotulo="Gasto"><Numero valor={dias.length ? c.gasto : null} formato="brl" animado={false} /></Linha>
      {funil === 'consultoria' && <>
        <Linha rotulo="Alcance"><Numero valor={total?.alcance ?? null} formato="int" falta={falta} animado={false} /></Linha>
        <Linha rotulo="Frequência"><Numero valor={total?.frequencia ?? null} formato="dec" falta={falta.replace('alcance', 'frequência')} animado={false} /></Linha>
        {total?.de && total.ate && <Linha rotulo="Período da campanha">de {dataBr(total.de)} a {dataBr(total.ate)}</Linha>}
      </>}
      <Linha rotulo="Cadastros"><Numero valor={linhas.length} formato="int" animado={false} /></Linha>
      <Linha rotulo="Leads pagos"><Numero valor={c.leadsPagos} formato="int" animado={false} /></Linha>
      <Linha rotulo="CPL"><span className="inline-flex items-center gap-1.5"><Numero valor={c.valor} formato="brl" animado={false} /><Farol farol={farolCpl(c.valor, d.config.reguaCpl)} /></span></Linha>
      <Linha rotulo="Conversão da página"><Taxa taxa={conversaoPagina(dias, linhas, d.idx)} /></Linha>
      <Linha rotulo="Grupo em 48h"><Taxa taxa={ingressoGrupo(linhas, 48, d.agora)} /></Linha>
    </div>
  );
}

const dataBr = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

/** Campanhas sem o código de etapa no nome: nome exato da fonte, gasto fora dos funis. A etapa nunca é deduzida. */
function SemEtapa({ d }: { d: DadosTela }) {
  const sem = d.trafego.campanhas.filter((c) => c.funil === null);
  if (sem.length === 0) return null;
  const gastoDaCampanha = (id: string): Valor => {
    const dias = d.diasPeriodoSemFiltro.filter((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id === id);
    return dias.length ? gastoDe(dias) : null;
  };
  return (
    <SectionCard title="Sem etapa" subtitle="Campanhas sem C1, C2 ou C3 no nome: ficam fora dos funis até o tráfego renomear. A etapa nunca é deduzida.">
      <ul className="divide-y divide-[var(--border-faint)] text-sm">
        {sem.map((c) => (
          <li key={c.id} className="flex flex-wrap items-baseline justify-between gap-2 py-1.5">
            <span className="min-w-0 break-words">{c.nome}{c.conflito ? <span className="ml-2 text-xs text-[var(--yellow)]">nome com dois subtipos</span> : null}</span>
            <span className="text-xs text-[var(--fg-3)]">Gasto no período <Numero valor={gastoDaCampanha(c.id)} formato="brl" falta="sem gasto por anúncio no período" animado={false} /></span>
          </li>
        ))}
      </ul>
    </SectionCard>
  );
}
