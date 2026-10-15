'use client';

// Aba 1, Visão geral: "estamos no caminho?". Só cards, cada card abre o ModalCard com as sub-abas fixas.
// Faixa 1 placar e investimento (primeira dobra) · Faixa 2 métricas de tráfego e funil de leads · Faixa 3 funis + CPL
// por etapa. O gráfico por fase saiu da visão geral em 13/10 (pedido do Victor): fica no detalhe do card de tráfego. Razão = soma sobre soma no mesmo recorte; sem dado = "Sem dado", nunca zero.
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { DataTable, KpiCard, Modal, ProgressBar, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { diaDe } from '../domain/recorte';
import { alertasNomenclatura } from '../domain/alertas-nomenclatura';
import { iscaDoNomeConjunto, tipoConteudoC1, type TipoConteudoC1 } from '../domain/ritmo';
import {
  agregar, cpc, cplPorEtapa, cpm, ctr, custoPorVisualizacao,
  dividir, ehCaptacao, ehEntresafraCampanha, ehPago, enviosMqlMaisRecentes, farolCpl, filtrarDias, filtrarLinhas, gastoDe, linhasCaptacao, somar, taxa as construirTaxa,
  taxaVideo75, type Taxa as TipoTaxa,
} from '../domain/metricas';
import { FUNIS, ROTULO_FUNIL, type DesempenhoDia, type Funil, type LinhaPerfil, type Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { ModalCard, type CardDef, type SubAbaModal } from './ModalCard';
import { Chip, Farol, formatar, IndicadorMeta, MODAL_TELA_CHEIA, moeda, Numero, Taxa } from './pecas';
import { GraficoLinha } from './graficos';
import { ProjecaoCaptacao } from './ProjecaoCaptacao';
import { EvolucaoMetaIndicador } from './EvolucaoMeta';
import { TabelaLeads } from './perfil/TabelaLeads';
import { ResumoLeads } from './ResumoLeads';
import { cplCaptacao, connectRate as connectRateNumero, conversaoPagina as conversaoPaginaNumero, gastoCampanha, investimentoTrafego, leadsDoTrafego, leadsPessoas, mql as mqlNumero, taxaMql, investimentoDeCaptacao, ingressoGrupoGeral } from '../domain/numeros';

const TODAS: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo', 'perfil'];
const TRAFEGO: SubAbaModal[] = ['funil', 'canal', 'fase', 'dia', 'criativo'];
const capDias = (dias: DesempenhoDia[], d: DadosTela) => dias.filter((x) => {
  const campanha = d.idx.campanhaDoAnuncio(x.anuncioId);
  return ehCaptacao(campanha?.funil) && !ehEntresafraCampanha(campanha);
});
const NOTA_ENTRESAFRA = 'Entresafra fora de todos os gastos (decisão do Victor)';
const capLinhas = (linhas: LinhaPerfil[], d: DadosTela) => linhasCaptacao(linhas, d.idx);
const valorTaxa = (t: TipoTaxa): Valor => t.valor;
// Funil macro: cinco colunas com linhas iguais a partir de 1280 px; abaixo, duas (três a partir de 1024) com a altura
// de cada linha, e o Ingresso no grupo (card com a lista por grupo) ocupa a linha inteira.
// Card com lista embaixo do número (Ingresso no grupo): a moldura do KpiCard vai para fora, para a lista ficar dentro
// dela em qualquer largura; a moldura do KpiCard de dentro some. A partir de 1280 px a moldura de fora ocupa a célula.
const MOLDURA_COM_LISTA = ' overflow-hidden border border-[var(--border)] bg-[var(--surface-2)]'
  + ' [&>*:first-child]:!rounded-none [&>*:first-child]:!border-0 [&>*:first-child]:!shadow-none';
const GRADE_MACRO = 'grid grid-cols-2 gap-3 lg:grid-cols-3 xl:grid-cols-5';
function Cartao({ onAbrir, titulo, children, cheio = false, className = '' }: { onAbrir?: () => void; titulo: string; children: ReactNode; cheio?: boolean | 'xl'; className?: string }) {
  // `cheio`: o card ocupa a altura toda da célula (grade com linhas iguais no funil macro). 'xl': card com lista embaixo
  // do número; só a moldura de fora ocupa a célula (a partir de 1280 px), o KpiCard e a lista ficam com a altura natural.
  const altura = cheio === 'xl' ? ' xl:h-full' + MOLDURA_COM_LISTA : cheio ? ' h-full [&>*]:h-full' : '';
  if (!onAbrir) return <div className={`min-w-0${altura} ${className}`}>{children}</div>;
  return (
    <div role="button" tabIndex={0} aria-label={`Abrir detalhe: ${titulo}`} onClick={onAbrir}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onAbrir(); } }}
      className={`atm-historico-card atm-historico-interativo min-w-0 cursor-pointer${altura} rounded-[var(--r-lg)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] ${className}`}>
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
  if (!Number.isFinite(ms) || ms <= 0) return '';
  return `faltam ${Math.ceil(ms / 86_400_000)} dias para a live`;
}

/** Tabela aberta por um card que não tem as sub-abas do ModalCard (os números vêm prontos do servidor). */
interface TabelaAberta { id: 'mql' | 'mql-percentual'; titulo: string; nota: string; linhas: LinhaPerfil[] }

function MetaComProgresso({ valor, meta, formato, menorMelhor = false }: { valor: Valor; meta: Valor; formato: 'brl' | 'pct'; menorMelhor?: boolean }) {
  if (meta === null) return <p className="text-[11px] text-[var(--fg-3)]">Sem meta cadastrada</p>;
  const atingido = valor === null ? null : menorMelhor
    ? valor <= meta ? 1 : valor === 0 ? 1 : Math.min(1, meta / valor)
    : meta === 0 ? null : Math.min(1, valor / meta);
  return <div className="space-y-1" title={`${menorMelhor ? 'Meta máxima' : 'Meta'}: ${formatar(meta, formato)}${valor === null ? '' : `; ${Math.round((atingido ?? 0) * 100)}% atingida`}`}>
    <div className="flex flex-wrap items-baseline justify-between gap-x-2 text-[10px] text-[var(--fg-3)]">
      <span>Meta {menorMelhor ? 'máx.' : ''} {formatar(meta, formato)}</span>
      <span>{atingido === null ? 'Sem dado para comparar' : `${Math.round(atingido * 100)}% da meta`}</span>
    </div>
    <ProgressBar value={(atingido ?? 0) * 100} ariaLabel={`Progresso em relação à meta ${formatar(meta, formato)}`} />
  </div>;
}

/** Cards de MQL mostram a base completa e destacam embaixo a parcela C2/C3. */
function CardMql({ geral, trafego, onAbrir }: { geral: ReturnType<typeof mqlNumero>; trafego: ReturnType<typeof mqlNumero>; onAbrir: () => void }) {
  return (
    <Cartao cheio titulo="MQLs" onAbrir={onAbrir}>
      <KpiCard label="MQLs" bar="none"
        valueClassName="text-2xl sm:text-3xl"
        value={<Numero valor={geral.num} formato="int" falta="sem cadastro no recorte" />}
        hint={<span>Do tráfego C2/C3: <strong className="tabular text-[var(--fg)]"><Numero valor={trafego.num} formato="int" falta="sem cadastro no recorte" /></strong></span>}
        title="Regra B: profissão do envio mais recente com profissão, uma pessoa por lead. Fonte: dados_black_perfil." />
    </Cartao>
  );
}

function CardPercentualMql({ geral, trafego, meta, onAbrir }: { geral: ReturnType<typeof taxaMql>; trafego: ReturnType<typeof taxaMql>; meta: Valor; onAbrir: () => void }) {
  return (
    <Cartao cheio titulo="% de MQL" onAbrir={onAbrir} className="min-h-[168px]">
      <KpiCard label="% de MQL" bar="none" value={<Taxa taxa={geral} className="text-2xl font-bold tracking-tight text-[var(--fg)] no-underline" />}
        valueClassName="text-2xl sm:text-3xl"
        className="!overflow-visible"
        hint={<div className="space-y-2 leading-snug">
          <div><div className="flex flex-wrap items-center gap-x-1"><span>Geral · </span><IndicadorMeta valor={geral.valor} meta={meta} formato="pct" compacto /></div><MetaComProgresso valor={geral.valor} meta={meta} formato="pct" /></div>
          <div><div className="flex flex-wrap items-center gap-x-1"><span>Tráfego C2/C3: <strong className="tabular text-[var(--fg)]"><Taxa taxa={trafego} /></strong> · </span><IndicadorMeta valor={trafego.valor} meta={meta} formato="pct" compacto /></div><MetaComProgresso valor={trafego.valor} meta={meta} formato="pct" /></div>
        </div>}
        title={`% de MQL. Geral: ${formatar(geral.num, 'int')} MQL ÷ ${formatar(geral.den, 'int')} leads. Tráfego: ${formatar(trafego.num, 'int')} MQL ÷ ${formatar(trafego.den, 'int')} leads pagos C2/C3. Meta geral e de tráfego: 60%. Regra B; fonte dados_black_perfil.`} />
    </Cartao>
  );
}

/** Ingresso usa a pessoa única do perfil, inclusive não MQL e sem campanha. */
function CardIngresso({ geral, trafego, grupo, meta, onAbrir }: { geral: ReturnType<typeof ingressoGrupoGeral>; trafego: ReturnType<typeof ingressoGrupoGeral>; grupo: DadosTela['grupo']['data']; meta: Valor; onAbrir: () => void }) {
  const linhasGrupo = ([
    ['advogado', 'Advogados', 'Denominador: leads advogado + estudante de Direito (leads_do_segmento).'],
    ['contador', 'Contadores', 'Denominador: leads contadores (leads_do_segmento).'],
    ['outros', 'Outros', 'Denominador: leads do segmento Outros (leads_do_segmento).'],
  ] as const).map(([segmento, nome, dica]) => {
    const matches = grupo?.grupos.filter((g) => g.segmento === segmento) ?? [];
    const item = matches.length === 1 ? matches[0] : null;
    return { nome, dica, taxa: item ? construirTaxa(item.leadsNoGrupo ?? null, item.leadsDoSegmento ?? null,
      matches.length > 1 ? 'Há mais de um grupo neste segmento; não se soma para evitar duplicidade.' : null) : null };
  });
  const multiGrupo = grupo?.leadsEmMaisDeUmGrupo;
  return (
    <Cartao cheio titulo="Ingresso no grupo" onAbrir={onAbrir}>
      <KpiCard label="Ingresso no grupo · todos os leads" bar="none"
        valueClassName="text-2xl sm:text-3xl"
        value={<Taxa taxa={geral} className="text-2xl font-bold tracking-tight text-[var(--fg)] no-underline" />}
        hint={<div className="space-y-2">
          <p className="whitespace-nowrap">Geral: <strong className="tabular text-[var(--fg)]"><Taxa taxa={geral} /></strong></p>
          <MetaComProgresso valor={geral.valor} meta={meta} formato="pct" />
          <p className="whitespace-nowrap">Do tráfego: <strong className="tabular text-[var(--fg)]"><Taxa taxa={trafego} /></strong></p>
          <MetaComProgresso valor={trafego.valor} meta={meta} formato="pct" />
          <ul className="border-t border-[var(--border-faint)] pt-1 text-[11px] text-[var(--fg-2)]">
            {linhasGrupo.map(({ nome, dica, taxa: t }) => <li key={nome} title={dica} className="whitespace-nowrap text-[10px]">
              <span>{nome}: </span><span className="font-semibold tabular">{t ? <><Taxa taxa={t} /> · {formatar(t.num, 'int')} / {formatar(t.den, 'int')}</> : 'Sem dado'}</span>
            </li>)}
            <li className="text-[var(--fg-3)]">
          {multiGrupo === null || multiGrupo === undefined ? 'Sem dado de sobreposição entre grupos.' : `${formatar(multiGrupo, 'int')} pessoas em mais de um grupo`}
            </li>
          </ul>
        </div>}
        title="Ingresso geral: números únicos que entraram no grupo ÷ leads únicos (dados_black_grupo.ingresso_geral, sem cruzar telefones). O tráfego e os recortes por pessoa continuam cruzados. Segmentos: dados_black_grupo.grupos[].leads_no_grupo ÷ leads_do_segmento. A união e as pessoas em mais de um grupo vêm dos campos leads_em_algum_grupo e leads_em_mais_de_um_grupo." />
    </Cartao>
  );
}

export function AbaVisaoGeral({ d }: { d: DadosTela }) {
  const [aberto, setAberto] = useState<CardDef | null>(null);
  const [detalheCaptacao, setDetalheCaptacao] = useState(false);
  const [etapaAberta, setEtapaAberta] = useState<string | null>(null);
  const [tabela, setTabela] = useState<TabelaAberta | null>(null);
  const [modalIngresso, setModalIngresso] = useState(false);
  const [abaVisao, setAbaVisao] = useState<'placar' | 'alertas'>('placar');
  const [tipoC1, setTipoC1] = useState<'todos' | TipoConteudoC1>('todos');
  const [iscaAberta, setIscaAberta] = useState<string | null>(null);
  // Sem fonte de cadastros, número de lead é "Sem dado" (nunca o zero de uma lista vazia).
  const semLeads = d.perfilSemDado;
  const { config, idx, recorte } = d;
  const filtro = { funil: recorte.funil, canal: recorte.canal };
  const abrir = (c: CardDef) => () => setAberto(c);

  // ─── Faixa 1: placar (do início até agora) ──────────────────────────────────────────────────────────────
  const leadsAteAgora: Valor = semLeads ? null : leadsPessoas(d.linhasTodas.filter((l) => l.pagina !== 'consultoria_respondi'), 'pessoas únicas desde o início').valor;
  const leadsTrafegoAteAgora = semLeads ? null : leadsDoTrafego(d.linhasTodas.filter((l) => l.pagina !== 'consultoria_respondi'), idx).valor;
  const leadsDeCampanha = leadsDoTrafego(d.linhas, idx, filtro);
  const investimentoCaptacao = investimentoDeCaptacao(d.trafegoPeriodo, d.periodo, filtro);
  const placar = cplCaptacao(investimentoCaptacao.total, leadsDeCampanha);

  const cardLeads: CardDef = { id: 'leads', rotulo: 'Leads (pessoas únicas)', formato: 'int', medir: (_, l) => leadsPessoas(l.filter((x) => x.pagina !== 'consultoria_respondi')).valor, aplica: TODAS,
    dica: 'No detalhe, o recorte é o período escolhido no topo. Uma pessoa com duas portas conta uma vez.' };
  const cardCpl: CardDef = { id: 'cpl', rotulo: 'CPL geral', formato: 'brl', medir: (_, l) => cplCaptacao(investimentoDeCaptacao(d.trafegoPeriodo, d.periodo, filtro).total, leadsDoTrafego(l, idx, filtro)).valor, aplica: TRAFEGO, menorMelhor: true,
    dica: `Investimento em captação C2/C3 ÷ leads pagos dessas etapas, no mesmo período. Remarketing fica fora. ${NOTA_ENTRESAFRA}.` };
  const cardGasto: CardDef = { id: 'gasto', rotulo: 'Gasto de tráfego', formato: 'brl', medir: (x) => (x.length ? gastoDe(x) : null), aplica: TRAFEGO,
    dica: `No detalhe, o recorte é o período escolhido no topo. ${NOTA_ENTRESAFRA}.` };

  // ─── Faixa 2: investimento (período) ────────────────────────────────────────────────────────────────────
  const gastoPeriodo: Valor = investimentoTrafego(d.trafegoPeriodo, filtro).valor;
  const porCanal = (c: 'meta' | 'google'): Valor => {
    return investimentoTrafego(d.trafegoPeriodo, { funil: recorte.funil, canal: c }).valor;
  };
  const disparoAplica = recorte.funil === 'todos' && recorte.canal === 'todos';
  const custoDisparo = d.mensageria ? somar(d.mensageria.canais.map((c) => c.custo)) : null;
  const total = gastoPeriodo === null ? null : disparoAplica && custoDisparo?.valor != null ? gastoPeriodo + custoDisparo.valor : gastoPeriodo;
  const investimento = investimentoCaptacao;
  const notaTotal = `${!disparoAplica ? 'Disparo não se divide por funil nem canal: fora da soma.'
    : custoDisparo?.valor == null ? 'Custo de disparo sem dado: fora da soma.' : 'Tráfego + disparo.'} ${NOTA_ENTRESAFRA}.`;

  // ─── Faixa 3: funil macro (só captação) ─────────────────────────────────────────────────────────────────
  const dCap = capDias(d.dias, d); const lCap = capLinhas(d.linhas, d); const lTrafegoPago = lCap.filter(ehPago);
  const leadsTrafegoNoFunil = semLeads ? null : leadsDoTrafego(lCap, idx).valor;
  const lGeral = d.linhas.filter((l) => l.pagina !== 'consultoria_respondi');
  const resultadoMqlGeral = mqlNumero(lGeral, 'pessoas únicas de todas as portas no período selecionado');
  const resultadoMqlTrafego = mqlNumero(lTrafegoPago, 'pessoas únicas pagas atribuídas a C2/C3 no período');
  const percentualMqlGeral = taxaMql(lGeral, 'pessoas únicas de todas as portas no período selecionado');
  const percentualMqlTrafego = taxaMql(lTrafegoPago, 'pessoas únicas pagas atribuídas a C2/C3 no período');
  const ingressoGeral = ingressoGrupoGeral(lGeral, d.grupo.data);
  const ingressoTrafego = ingressoGrupoGeral(lTrafegoPago);
  const aCap = agregar(dCap);
  const medirCap = (f: (a: ReturnType<typeof agregar>) => Valor) => (x: DesempenhoDia[]) => { const c = capDias(x, d); return c.length ? f(agregar(c)) : null; };
  // Ordem pedida pelo Victor (12/10): Impressões, CPM, Cliques, CTR, CPC, Visualizações, Connect, Inscrições, Conversão. O card Grupo em 48h saiu em 13/10: fica a taxa de Ingresso no grupo.
  const cards3: { c: CardDef; valor: ReactNode; hint?: ReactNode }[] = [
    { c: { id: 'investimento-captacao', rotulo: 'Investimento em captação', formato: 'brl', medir: () => investimento.total, aplica: TRAFEGO,
      dica: `Campanhas C2/C3, sem remarketing. ${NOTA_ENTRESAFRA}.` },
      valor: <Numero valor={investimento.total} formato="brl" falta="sem dado por cobertura incompleta" />,
      hint: `Meta Ads ${moeda(investimento.meta)} · Google Ads ${moeda(investimento.google)}` },
    { c: cardCpl, valor: <Numero valor={placar.valor} formato="brl" falta="sem leads pagos no recorte" />,
      hint: `${formatar(placar.den, 'int')} pessoas pagas` },
    { c: { id: 'cpm', rotulo: 'CPM', formato: 'brl', medir: medirCap(cpm), aplica: TRAFEGO, menorMelhor: true,
      dica: `Soma do gasto por anúncio em dados_black_trafego.dias_anuncio ÷ impressões desses anúncios × 1.000: ${moeda(aCap.gasto)} ÷ ${formatar(aCap.impressoes, 'int')}. O card de captação usa dias_campanha, agregado por campanha. A Meta coleta cada nível em chamadas independentes, então os totais podem diferir.` }, valor: <Numero valor={dCap.length ? cpm(aCap) : null} formato="brl" /> },
    { c: { id: 'ctr', rotulo: 'CTR', formato: 'pct', medir: (x) => valorTaxa(ctr(agregar(capDias(x, d)))), aplica: TRAFEGO, dica: 'Cliques no link ÷ impressões.' }, valor: <Taxa taxa={ctr(aCap)} /> },
    { c: { id: 'cpc', rotulo: 'CPC', formato: 'brl', medir: medirCap(cpc), aplica: TRAFEGO, menorMelhor: true, dica: 'Custo por clique: gasto ÷ cliques no link, só nas linhas com clique medido.' }, valor: <Numero valor={dCap.length ? cpc(aCap) : null} formato="brl" /> },
    { c: { id: 'connect', rotulo: 'Connect rate', formato: 'pct', medir: (x) => connectRateNumero(x, idx).valor, aplica: TRAFEGO,
      dica: 'dados_black_trafego.dias_anuncio: soma de views da página ÷ soma de cliques no link em C2/C3, somente nas linhas com os dois campos. O percentual mostra numerador e denominador ao passar o cursor.' }, valor: <Taxa taxa={connectRateNumero(d.dias, idx)} /> },
    { c: cardLeads, valor: <Numero valor={semLeads ? null : leadsPessoas(lGeral).valor} formato="int" falta={d.avisoPerfil ?? undefined} />, hint: <span>Do tráfego C2/C3: <strong className="tabular text-[var(--fg)]"><Numero valor={leadsTrafegoNoFunil} formato="int" falta={d.avisoPerfil ?? undefined} /></strong></span> },
    { c: { id: 'conv', rotulo: 'Conversão da página', formato: 'pct', medir: (x, l) => conversaoPaginaNumero(x, l, idx).valor, aplica: TRAFEGO, dica: 'Inscrições pagas ÷ views da página, dos mesmos anúncios.' }, valor: <Taxa taxa={conversaoPaginaNumero(d.dias, d.linhas, idx)} /> },
  ];

  // Indicador de meta (bom/ruim + % da meta) dos cards com fórmula. Metas: Victor, 13/10/2026 (config.metas).
  const m = config.metas;
  const progressoMeta: Record<string, ReactNode> = {
    cpl: <div className="space-y-1"><IndicadorMeta valor={placar.valor} ideal={config.reguaCpl?.meta ?? null} meta={config.cplAlvoMedio} menorMelhor formato="brl" compacto /><MetaComProgresso valor={placar.valor} meta={config.cplAlvoMedio} formato="brl" menorMelhor /></div>,
    cpm: <MetaComProgresso valor={dCap.length ? cpm(aCap) : null} meta={m.cpm} formato="brl" menorMelhor />,
    ctr: <MetaComProgresso valor={ctr(aCap).valor} meta={m.ctr} formato="pct" />,
    cpc: <MetaComProgresso valor={dCap.length ? cpc(aCap) : null} meta={m.cpc} formato="brl" menorMelhor />,
    connect: <MetaComProgresso valor={connectRateNumero(d.dias, idx).valor} meta={m.connectRate} formato="pct" />,
    conv: <MetaComProgresso valor={conversaoPaginaNumero(d.dias, d.linhas, idx).valor} meta={m.conversaoPagina} formato="pct" />,
  };

  // Tabelas dos cards MQLs e Ingresso: os envios do período e do nó (cada envio é uma linha; o card conta pessoas).
  const linhasMql = enviosMqlMaisRecentes(lGeral);
  const linhasGrupo = lGeral.filter((l) => l.entrouGrupoEm !== null && diaDe(l.entrouGrupoEm) >= d.periodo.de && diaDe(l.entrouGrupoEm) <= d.periodo.ate);
  const abrirMql = () => setTabela({ id: 'mql', titulo: 'MQLs', linhas: linhasMql,
    nota: 'MQL pela Regra B: profissão do envio mais recente com profissão, uma pessoa por lead, de todas as portas no período selecionado.' });
  const abrirPctMql = () => setTabela({ id: 'mql-percentual', titulo: '% de MQL', linhas: linhasMql,
    nota: 'Pessoas usadas no cálculo da taxa: MQL pela Regra B dividido por pessoas únicas do recorte. A meta de 60% vale para a base geral e para C2/C3.' });
  const abrirGrupo = () => setModalIngresso(true);

  // ─── Faixa 4: funis lado a lado ─────────────────────────────────────────────────────────────────────────
  const diasCanal = filtrarDias(d.diasPeriodoSemFiltro, idx, { funil: 'todos', canal: recorte.canal });
  const linhasCanal = filtrarLinhas(d.linhasPeriodoSemFiltro, { funil: 'todos', canal: recorte.canal });
  const etapas = cplPorEtapa(d.dias, d.linhas, idx, d.trafegoPeriodo.gastoCampanhas);
  const horaColeta = (iso: string | null) => iso
    ? new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
    : 'hora da coleta sem dado';
  const detalhesCobertura = [
    ...investimento.zerosMeta.map((c) => `${c.nome}: sem entrega, coleta ok às ${horaColeta(c.coletaEm)}`),
    ...investimento.zerosGoogle.map((c) => `${c.nome}: sem entrega, coleta ok às ${horaColeta(c.coletaEm)}`),
    ...investimento.semDadoMeta.map((c) => `${c.nome}: Sem dado (${c.motivo}${c.coletaEm ? `, coleta às ${horaColeta(c.coletaEm)}` : ''})`),
    ...investimento.semDadoGoogle.map((c) => `${c.nome}: Sem dado (${c.motivo}${c.coletaEm ? `, coleta às ${horaColeta(c.coletaEm)}` : ''})`),
  ].join(' · ');
  const abrirEtapa = (funil: Funil) => d.irPara({ aba: 'criativos', funil, criativos: {} });

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap gap-2" role="tablist" aria-label="Visão geral da Black">
        {([{ id: 'placar', nome: 'Visão geral' }, { id: 'alertas', nome: 'Alertas importantes' }] as const).map((tab) => (
          <button key={tab.id} type="button" role="tab" aria-selected={abaVisao === tab.id} onClick={() => setAbaVisao(tab.id)}
            className={`min-h-10 rounded-[var(--r-md)] px-3 text-sm ${abaVisao === tab.id ? 'bg-[var(--accent)] font-semibold text-black' : 'border border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'}`}>
            {tab.nome}
          </button>
        ))}
      </div>
      {abaVisao === 'placar' ? <div className="space-y-5">
      <section aria-labelledby="vg-placar">
        <div className="mb-2 flex items-center justify-between gap-3">
          <h2 id="vg-placar" className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Placar</h2>
          {config.liveEm && tempoAte(config.liveEm, d.agora) && <span className="text-xs text-[var(--fg-3)]">{tempoAte(config.liveEm, d.agora)}</span>}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          {/* O limite total reutiliza ORCAMENTO.total enquanto não há orçamento próprio de disparos. */}
          <KpiCard label="Investimento total" value={<Numero valor={total} formato="brl" falta="sem dado" />} valueClassName="text-2xl sm:text-3xl" title={`${notaTotal} O limite de ${moeda(config.orcamentoTotal)} reutiliza provisoriamente o orçamento total do projeto, pois não há limite separado para disparos.`} bar="none"
            hint={<div className="space-y-2"><p className="text-xs text-[var(--fg-2)]">{total === null ? `Sem dado de ${moeda(config.orcamentoTotal)} · sem percentual` : `${moeda(total)} de ${moeda(config.orcamentoTotal)} · ${formatar(dividir(total, config.orcamentoTotal), 'pct')}`}</p>{config.orcamentoTotal !== null && <ProgressBar value={total === null ? 0 : (total / config.orcamentoTotal) * 100} tone="yellow" ariaLabel="Investimento total em relação ao orçamento" />}</div>} />
          <Cartao titulo={cardGasto.rotulo} onAbrir={abrir(cardGasto)}>
            <KpiCard label="Investimento em tráfego" value={<Numero valor={gastoPeriodo} formato="brl" falta="sem dado" />} valueClassName="text-2xl sm:text-3xl" title={`${NOTA_ENTRESAFRA}`} bar="none"
              hint={<div className="space-y-2"><p className="text-xs text-[var(--fg-2)]">Meta Ads {moeda(porCanal('meta'))} · Google Ads {moeda(porCanal('google'))}</p><p className="text-xs text-[var(--fg-2)]">{gastoPeriodo === null ? `Sem dado de ${moeda(config.orcamentoTotal)} · sem percentual` : `${moeda(gastoPeriodo)} de ${moeda(config.orcamentoTotal)} · ${formatar(dividir(gastoPeriodo, config.orcamentoTotal), 'pct')}`}</p>{config.orcamentoTotal !== null && <ProgressBar value={gastoPeriodo === null ? 0 : (gastoPeriodo / config.orcamentoTotal) * 100} tone="yellow" ariaLabel="Investimento em tráfego em relação ao orçamento" />}</div>} />
          </Cartao>
          <Cartao titulo="Disparo" onAbrir={() => d.irPara({ aba: 'mensageria' })}>
            <KpiCard label="Investimento com disparo" bar="none" value={<Numero valor={custoDisparo?.valor ?? null} formato="brl" falta="Sem dado" />} valueClassName="text-2xl sm:text-3xl"
              title={notaTotal} hint={<div className="space-y-2"><p className="text-xs text-[var(--fg-2)]">limite sem cadastro</p><ProgressBar value={0} ariaLabel="Limite para investimento com disparo sem cadastro" /></div>} />
          </Cartao>
        </div>
        <div className="mt-3 grid grid-cols-1 gap-3">
          <Cartao titulo={cardLeads.rotulo} onAbrir={abrir(cardLeads)}>
            <KpiCard label="Leads contra a meta" bar="none" title={`${config.fontes.plano} Pessoas únicas de todas as portas desde o início, sem aplicar o filtro de período. Meta: ${config.metaLeads === null ? 'sem cadastro' : formatar(config.metaLeads, 'int')}.`} valueClassName="text-2xl sm:text-3xl"
              value={<span className="flex flex-wrap items-baseline gap-x-2"><Numero valor={leadsAteAgora} formato="int" falta={d.avisoPerfil ?? undefined} />{config.metaLeads !== null && leadsAteAgora !== null && <span className="text-base font-medium text-[var(--fg-2)]">de {formatar(config.metaLeads, 'int')} · {formatar(dividir(leadsAteAgora, config.metaLeads), 'pct')}</span>}</span>}
              hint={<div className="space-y-2">{config.metaLeads !== null && leadsAteAgora !== null && <ProgressBar value={(leadsAteAgora / config.metaLeads) * 100} ariaLabel={`${formatar(leadsAteAgora, 'int')} de ${formatar(config.metaLeads, 'int')} leads`} valueNow={leadsAteAgora} valueMin={0} valueMax={config.metaLeads} />}<p className="text-xs text-[var(--fg-2)]">Do tráfego C2/C3: <strong className="tabular text-[var(--fg)]">{formatar(leadsTrafegoAteAgora, 'int')}</strong></p></div>} />
          </Cartao>
        </div>
        <ProjecaoCaptacao d={d} />
      </section>

      <section aria-labelledby="vg-funil">
        <h2 id="vg-funil" className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil macro</h2>
        <p className="mb-2 text-xs text-[var(--fg-3)]">Leads, MQL e ingresso incluem todas as portas; métricas de tráfego e conversão da página ficam em C2/C3.</p>
        {recorte.funil === 'c1' ? (
          <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">O C1 é distribuição: não tem página, inscrição nem connect rate. Veja os funis lado a lado abaixo.</p>
        ) : (
          <>
            <ol className={GRADE_MACRO}>
              {cards3.flatMap(({ c, valor, hint }) => [
                <li key={c.id} className="min-w-0"><Cartao cheio titulo={c.rotulo} onAbrir={c.id === 'investimento-captacao' ? () => setDetalheCaptacao(true) : abrir(c)}><KpiCard label={c.rotulo} title={`${c.dica ?? ''} ${typeof hint === 'string' ? hint : ''}${c.id === 'investimento-captacao' && detalhesCobertura ? ` ${detalhesCobertura}` : ''}`} bar="none" valueClassName={c.id === 'investimento-captacao' ? 'whitespace-nowrap text-[clamp(1.125rem,2.2vw,1.875rem)]' : 'text-2xl sm:text-3xl'} value={valor}
                  hint={c.id === 'investimento-captacao' ? <div className="space-y-1"><span className="block">Meta Ads {moeda(investimento.meta)} · Google Ads {moeda(investimento.google)}</span><MetaComProgresso valor={investimento.total} meta={config.previstoPorFase.captacao} formato="brl" /></div> : c.id === 'leads' ? hint : progressoMeta[c.id] ?? undefined} /></Cartao></li>,
                // MQLs logo depois da conversão da página; o Ingresso no grupo vem em seguida (pedido de 13/10).
                ...(c.id === 'conv' ? [
                  <li key="mql" className="min-w-0"><CardMql geral={resultadoMqlGeral} trafego={resultadoMqlTrafego} onAbrir={abrirMql} /></li>,
                  <li key="mql-percentual" className="min-w-0"><CardPercentualMql geral={percentualMqlGeral} trafego={percentualMqlTrafego} meta={config.metas.mql} onAbrir={abrirPctMql} /></li>,
                  <li key="ingresso" className="col-span-2 min-w-0 lg:col-span-1"><CardIngresso geral={ingressoGeral} trafego={ingressoTrafego} grupo={d.grupo.data} meta={config.metas.ingressoGrupo} onAbrir={abrirGrupo} /></li>,
                ] : []),
              ])}
            </ol>
            <div className={'mt-3 ' + GRADE_MACRO}>
              <Cartao cheio titulo="Presença na live"><KpiCard label="Presença na live" value={<Numero valor={d.marcos?.presencaLive ?? null} formato="int" falta="presença da live ainda sem fonte" />} bar="none" /></Cartao>
              <Cartao cheio titulo="Vendas"><KpiCard label="Vendas" value={<Numero valor={d.marcos?.vendas ?? null} formato="int" falta="vendas ainda sem fonte" />} bar="none" /></Cartao>
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
            const selecionado = recorte.funil === f || (recorte.funil === 'c2' && (f === 'consultoria' || f === 'iscas'));
            const apagado = recorte.funil !== 'todos' && !selecionado;
            return (
              <SectionCard key={f} title={ROTULO_FUNIL[f]} className={apagado ? 'opacity-40' : ''}
                right={<button type="button" className="text-xs text-[var(--accent)] underline-offset-2 hover:underline max-md:-my-3 max-md:-mr-3 max-md:min-h-11 max-md:px-3" onClick={() => d.irPara({ funil: selecionado && recorte.funil !== 'todos' ? 'todos' : f })}>{selecionado && recorte.funil !== 'todos' ? 'Limpar filtro' : 'Filtrar'}</button>}>
                {f === 'c1' ? <ColunaC1Segmentada d={d} dias={df} selecionado={tipoC1} onSelecionar={setTipoC1} />
                  : f === 'iscas' ? <ColunaIscasSegmentada d={d} dias={df} linhas={lf} selecionado={iscaAberta} onSelecionar={setIscaAberta} />
                    : <ColunaCaptacao d={d} dias={df} linhas={lf} funil={f} />}
              </SectionCard>
            );
          })}
        </div>

      <SectionCard className="mt-3" title="CPL por etapa" subtitle="C2: campanhas pagas por iscas e aplicação da consultoria; o lead passa pela Central. C3 vai direto ao grupo. Expanda uma etapa para ver campanhas, conjuntos e métricas.">
          <div className="space-y-2">
            <EtapaFechada titulo="C1 · Distribuição" gasto={investimentoTrafego(d.trafegoPeriodo, { funil: 'c1', canal: recorte.canal }).valor} leads={null} cpl={null}
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

      {modalIngresso && <ModalIngresso d={d} onClose={() => setModalIngresso(false)} linhas={linhasGrupo} />}

      <ModalCard d={d} card={aberto} onClose={() => setAberto(null)} />
      {detalheCaptacao && (
        <Modal open onClose={() => setDetalheCaptacao(false)} title="Investimento em captação" width={`max-w-xl ${MODAL_TELA_CHEIA}`}>
          <div className="space-y-3 text-sm text-[var(--fg-2)]">
            <p className="text-2xl font-bold tabular text-[var(--fg)]"><Numero valor={investimento.total} formato="brl" falta="sem dado por cobertura incompleta" /></p>
            <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3"><dt className="text-xs text-[var(--fg-3)]">Meta Ads</dt><dd className="mt-1 font-semibold tabular text-[var(--fg)]"><Numero valor={investimento.meta} formato="brl" /></dd></div>
              <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3"><dt className="text-xs text-[var(--fg-3)]">Google Ads</dt><dd className="mt-1 font-semibold tabular text-[var(--fg)]"><Numero valor={investimento.google} formato="brl" /></dd></div>
            </dl>
            {detalhesCobertura && <p className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">{detalhesCobertura}.</p>}
            <p className="border-t border-[var(--border)] pt-3 text-xs text-[var(--fg-3)]">Total das campanhas de captação C2/C3, sem remarketing. {NOTA_ENTRESAFRA}.</p>
            {config.previstoPorFase.captacao !== null && <EvolucaoMetaIndicador d={d} cardId="investimento-captacao" rotulo="Investimento em captação" formato="brl" />}
          </div>
        </Modal>
      )}
      {tabela && (
        <Modal open onClose={() => setTabela(null)} title={tabela.titulo} width={`max-w-5xl ${MODAL_TELA_CHEIA}`}>
          <p className="mb-2 text-xs text-[var(--fg-3)]">{tabela.nota}</p>
          {tabela.id === 'mql-percentual' && config.metas.mql !== null && <div className="mb-3"><EvolucaoMetaIndicador d={d} cardId="mql-percentual" rotulo="% de MQL" formato="pct" /></div>}
          <div className="mb-3"><ResumoLeads linhas={d.linhas.filter((l) => l.pagina !== 'consultoria_respondi')} idx={d.idx} grupo={d.grupo.data} compacto semDado={d.perfilSemDado} /></div>
          <TabelaLeads d={d} linhas={tabela.linhas} />
        </Modal>
      )}
      </div> : <PainelAlertas d={d} />}
    </div>
  );
}

function Linha({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <div className="flex items-baseline justify-between gap-3 py-1 text-sm"><span className="text-[var(--fg-3)]">{rotulo}</span><span className="text-right text-[var(--fg)]">{children}</span></div>;
}

const ROTULOS_C1: readonly TipoConteudoC1[] = ['Teaser', 'Manifesto', 'Reels', 'Sem tipo no nome'];
const ROTULOS_ISCA = ['Checkup', 'Fluxograma', 'Futurômetro'] as const;

function ColunaC1Segmentada({ d, dias, selecionado, onSelecionar }: {
  d: DadosTela; dias: DesempenhoDia[]; selecionado: 'todos' | TipoConteudoC1; onSelecionar: (x: 'todos' | TipoConteudoC1) => void;
}) {
  const ads = d.trafego.anuncios.filter((a) => d.idx.campanhaDoAnuncio(a.id)?.funil === 'c1');
  const idsComDado = new Set(dias.map((x) => x.anuncioId));
  const categoria = new Map(ads.map((a) => [a.id, tipoConteudoC1(a.nome)]));
  const contagens = new Map<TipoConteudoC1, number>(ROTULOS_C1.map((x) => [x, new Set(ads.filter((a) => idsComDado.has(a.id) && categoria.get(a.id) === x).map((a) => a.nome)).size]));
  const categorias = selecionado === 'todos' ? null : new Set(ads.filter((a) => idsComDado.has(a.id) && categoria.get(a.id) === selecionado).map((a) => a.id));
  const recorte = categorias ? dias.filter((x) => categorias.has(x.anuncioId)) : dias;
  const a = agregar(recorte);
  return <div className="space-y-3">
    <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar C1 pelo tipo do anúncio">
      <Chip ativo={selecionado === 'todos'} onClick={() => onSelecionar('todos')}>Todos</Chip>
      {ROTULOS_C1.map((nome) => <Chip key={nome} ativo={selecionado === nome} onClick={() => onSelecionar(selecionado === nome ? 'todos' : nome)}>{nome} ({contagens.get(nome) ?? 0})</Chip>)}
    </div>
    <p className="text-[10px] text-[var(--fg-3)]">Tipo identificado pelo nome do anúncio. “Sem tipo no nome” mantém os anúncios sem TEASER, MANIFESTO ou REELS.</p>
    {recorte.length === 0 ? <p className="py-2 text-xs text-[var(--fg-3)]">Sem dado para este tipo no recorte.</p> : <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-3">
      <Par rotulo="Anúncios"><Numero valor={new Set(recorte.map((x) => d.idx.anuncio.get(x.anuncioId)?.nome).filter(Boolean)).size} formato="int" animado={false} /></Par>
      <Par rotulo="Investimento"><Numero valor={gastoDe(recorte)} formato="brl" animado={false} /></Par>
      <Par rotulo="Impressões"><Numero valor={a.impressoes} formato="int" animado={false} /></Par>
      <Par rotulo="ThruPlay"><Numero valor={a.thruplay.valor} formato="int" animado={false} /></Par>
      <Par rotulo="Vídeo 75%"><Taxa taxa={taxaVideo75(a)} /></Par>
      <Par rotulo="CPM"><Numero valor={cpm(a)} formato="brl" animado={false} /></Par>
    </div>}
  </div>;
}

function ColunaIscasSegmentada({ d, dias, linhas, selecionado, onSelecionar }: {
  d: DadosTela; dias: DesempenhoDia[]; linhas: LinhaPerfil[]; selecionado: string | null; onSelecionar: (x: string | null) => void;
}) {
  const campanhasIsca = new Set(d.trafegoPeriodo.campanhas.filter((c) => c.funil === 'iscas' && !ehEntresafraCampanha(c)).map((c) => c.id));
  const conjuntos = d.trafegoPeriodo.conjuntos.filter((cj) => campanhasIsca.has(cj.campanhaId));
  const iscaConjunto = new Map(conjuntos.map((cj) => [cj.id, iscaDoNomeConjunto(cj.nome)]));
  const iscaDoAnuncio = new Map(d.trafegoPeriodo.anuncios.map((a) => [a.id, iscaConjunto.get(a.conjuntoId) ?? null]));
  const categoria = (x: DesempenhoDia) => iscaDoAnuncio.get(x.anuncioId) ?? null;
  const escolhida = selecionado ? dias.filter((x) => categoria(x) === selecionado) : dias;
  const linhasIsla = selecionado ? linhas.filter((x) => x.isca === selecionado) : linhas;
  const investimento = escolhida.length ? gastoDe(escolhida) : null;
  const pagos = leadsDoTrafego(linhasIsla, d.idx);
  const cpl = cplCaptacao(investimento, pagos);
  const conjuntoIds = new Set(conjuntos.filter((cj) => !selecionado || iscaConjunto.get(cj.id) === selecionado).map((cj) => cj.id));
  const anunciosNomes = new Set(d.trafegoPeriodo.anuncios.filter((a) => conjuntoIds.has(a.conjuntoId) && escolhida.some((x) => x.anuncioId === a.id)).map((a) => a.nome));
  const anunciosConflitantes = new Set(d.trafegoPeriodo.anuncios.filter((a) => {
    const isca = iscaConjunto.get(a.conjuntoId);
    const nomeNormalizado = a.nome.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLocaleUpperCase('pt-BR');
    const iscaNormalizada = isca?.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLocaleUpperCase('pt-BR');
    return isca !== null && isca !== undefined && isca === selecionado && !nomeNormalizado.includes(iscaNormalizada ?? '');
  }).map((a) => a.nome));
  return <div className="space-y-3">
    <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar Iscas por isca">
      <Chip ativo={selecionado === null} onClick={() => onSelecionar(null)}>Todas</Chip>
      {ROTULOS_ISCA.map((nome) => <Chip key={nome} ativo={selecionado === nome} onClick={() => onSelecionar(selecionado === nome ? null : nome)}>{nome}</Chip>)}
    </div>
    <p className="text-[10px] text-[var(--fg-3)]">Tráfego agrupado pelo último bloco do nome do conjunto; leads pelo campo isca de dados_black_perfil.</p>
    {escolhida.length === 0 && linhasIsla.length === 0 ? <p className="py-2 text-xs text-[var(--fg-3)]">Sem dado para esta isca no recorte.</p> : <>
      <div className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-3">
        <Par rotulo="Anúncios"><Numero valor={anunciosNomes.size} formato="int" animado={false} /></Par>
        <Par rotulo="Investimento"><Numero valor={investimento} formato="brl" animado={false} /></Par>
        <Par rotulo="Leads pagos"><Numero valor={pagos.valor} formato="int" animado={false} /></Par>
        <Par rotulo="CPL"><Numero valor={cpl.valor} formato="brl" animado={false} /></Par>
        <Par rotulo="Conversão da página"><Taxa taxa={conversaoPaginaNumero(escolhida, linhasIsla, d.idx)} /></Par>
      </div>
      {anunciosConflitantes.size > 0 && <p className="rounded-[var(--r-sm)] bg-[var(--surface-3)] p-2 text-[10px] text-[var(--fg-2)]">Anúncio com outra isca no nome: {anunciosConflitantes.size}. O gasto segue a isca do conjunto.</p>}
    </>}
  </div>;
}

function CampanhasEtapa({ d, funil }: { d: DadosTela; funil: Funil }) {
  const campanhas = d.trafegoPeriodo.campanhas.filter((c) => !ehEntresafraCampanha(c) && (funil === 'iscas'
    ? c.funil === 'c3' && c.fase === 'captacao' && (c.subtipo === 'ISCA' || d.trafegoPeriodo.conjuntos.some((j) => j.campanhaId === c.id && j.isca !== null))
    : c.funil === funil && c.fase === 'captacao'));
  if (campanhas.length === 0) return <p className="py-2 text-xs text-[var(--fg-3)]">Sem campanha de captação com dado neste recorte.</p>;
  return (
    <ul className="divide-y divide-[var(--border-faint)]">
      {campanhas.map((campanha) => {
        const dias = d.dias.filter((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id === campanha.id);
        const leads = d.linhas.filter((l) => l.campanhaId === campanha.id && ehPago(l));
        const custo = gastoCampanha(d.trafegoPeriodo, campanha.id).valor;
        const pagos = leadsDoTrafego(leads, d.idx);
        const resultado = cplCaptacao(custo, pagos).valor;
        const resultadoMql = mqlNumero(leads, 'pessoas únicas pagas desta campanha');
        const mql = resultadoMql.valor;
        const agregado = agregar(dias);
        return (
          <li key={campanha.id} className="py-2">
            <p className="break-words text-sm font-medium text-[var(--fg)]">{campanha.nome}</p>
            <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
              <Par rotulo="Investimento"><Numero valor={custo} formato="brl" animado={false} /></Par>
              <Par rotulo="Leads pagos"><Numero valor={pagos.valor} formato="int" animado={false} /></Par>
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
    const gasto = gastoCampanha(d.trafegoPeriodo, campanha.id).valor;
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
      // O contrato atual não tem investimento por conjunto; mostrar Sem dado evita ratear um total de campanha.
      const custo: Valor = null;
      const pagos = leadsDoTrafego(leads, d.idx);
      const mqlSet = mqlNumero(leads, 'pessoas únicas pagas deste conjunto');
      const mql = mqlSet.valor;
      const cplSet = cplCaptacao(custo, pagos).valor;
      return <li key={cj.id} className="py-2">
        <p className="break-words text-xs font-medium text-[var(--fg-2)]">{cj.nome}</p>
        <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
          <Par rotulo="Investimento"><Numero valor={custo} formato="brl" animado={false} /></Par>
          <Par rotulo="Impressões"><Numero valor={dias.length ? a.impressoes : null} formato="int" animado={false} /></Par>
          <Par rotulo="Cliques"><Numero valor={a.cliques.valor} formato="int" animado={false} /></Par>
          <Par rotulo="CTR"><Taxa taxa={ctr(a)} /></Par>
          {!distribuicao && <>
            <Par rotulo="Leads pagos"><Numero valor={pagos.valor} formato="int" animado={false} /></Par>
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

function ColunaCaptacao({ d, dias, linhas, funil }: { d: DadosTela; dias: DesempenhoDia[]; linhas: LinhaPerfil[]; funil: Funil }) {
  const leads = leadsDoTrafego(linhas, d.idx);
  const investimento = investimentoDeCaptacao(d.trafegoPeriodo, d.periodo, { funil, canal: 'todos' });
  const c = cplCaptacao(investimento.total, leads);
  const campanhas = [...new Set(dias.map((x) => d.idx.campanhaDoAnuncio(x.anuncioId)?.id).filter((x): x is string => Boolean(x)))];
  const total = campanhas.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'campanha' && t.id === campanhas[0]) : undefined;
  const falta = campanhas.length > 1 ? 'alcance não soma entre campanhas' : funil === 'consultoria' && campanhas.length === 0 ? 'sem campanha com veiculação' : 'alcance do período';
  return (
    <div className="divide-y divide-[var(--border-faint)]">
      <Linha rotulo="Gasto"><Numero valor={investimento.total} formato="brl" animado={false} /></Linha>
      {funil === 'consultoria' && <>
        <Linha rotulo="Alcance"><Numero valor={total?.alcance ?? null} formato="int" falta={falta} animado={false} /></Linha>
        <Linha rotulo="Frequência"><Numero valor={total?.frequencia ?? null} formato="dec" falta={falta.replace('alcance', 'frequência')} animado={false} /></Linha>
        {total?.de && total.ate && <Linha rotulo="Período da campanha">de {dataBr(total.de)} a {dataBr(total.ate)}</Linha>}
      </>}
      <Linha rotulo="Cadastros"><Numero valor={linhas.length} formato="int" animado={false} /></Linha>
      <Linha rotulo="Leads pagos"><Numero valor={leads.valor} formato="int" animado={false} /></Linha>
      <Linha rotulo="CPL"><span className="inline-flex items-center gap-1.5"><Numero valor={c.valor} formato="brl" animado={false} /><Farol farol={farolCpl(c.valor, d.config.reguaCpl)} /></span></Linha>
      <Linha rotulo="Conversão da página"><Taxa taxa={conversaoPaginaNumero(dias, linhas, d.idx)} /></Linha>
    </div>
  );
}

const dataBr = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const ROTULO_REGRA: Record<string, string> = {
  R1: 'O último campo não é a etiqueta do dashboard.', R2: 'Quantidade de campos fora do padrão.',
  R3: 'Gestor fora de CF, RS ou EF.', R4: 'Projeto diferente de BF26.',
  R5: 'Objetivo fora da lista permitida.', R6: 'Etapa não cadastrada no banco.',
  R7: 'Mais de um subtipo reconhecido no nome.', R8: 'O primeiro bloco do conjunto não é PQ, PF, MIX ou ADV.',
  R9: 'Anúncio C1 sem TEASER, MANIFESTO ou REELS no nome.', R10: 'Anúncio de isca sem o nome da isca.',
  R11: 'A isca do anúncio difere da isca do conjunto.', R12: 'Conjunto de campanha C2 ISCA sem nome de isca.',
  U1: 'utm_campaign marcada fora do padrão pelo banco.', U2: 'Cadastro sem UTM, conforme a sinalização do banco.',
};

function PainelAlertas({ d }: { d: DadosTela }) {
  const alertas = useMemo(() => alertasNomenclatura(d.trafego, d.linhasTodas), [d.trafego, d.linhasTodas]);
  const tipos = ['Campanha', 'Conjunto', 'Anúncio', 'UTM'] as const;
  const total = alertas.reduce((soma, item) => soma + item.regras.length * item.ocorrencias, 0);
  return <div className="space-y-3">
    <SectionCard title="Alertas importantes" subtitle="Inconsistências calculadas a partir dos nomes exatos da fonte e das sinalizações de UTM do banco.">
      <p className="mb-3 text-sm text-[var(--fg-2)]">{total} ocorrências em {alertas.length} itens. As regras aparecem junto de cada nome para orientar a correção.</p>
      {alertas.length === 0 ? <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-5 text-center text-sm text-[var(--fg-3)]">Nenhuma inconsistência encontrada nos dados carregados.</p> : <div className="space-y-4">
        {tipos.map((tipo) => {
          const itens = alertas.filter((a) => a.tipo === tipo);
          if (itens.length === 0) return null;
          return <section key={tipo} aria-label={`Alertas de ${tipo.toLocaleLowerCase('pt-BR')}`}>
            <h3 className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{tipo} · {itens.length}</h3>
            <ul className="divide-y divide-[var(--border-faint)]">
              {itens.map((item) => <li key={item.chave} className="grid min-w-0 gap-1 py-2 md:grid-cols-[minmax(0,1fr)_minmax(15rem,0.8fr)_auto] md:items-start md:gap-3">
                <code className="break-words text-xs text-[var(--fg)]">{item.nome}</code>
                <span className="text-xs text-[var(--fg-2)]">{item.regras.map((r) => `${r}: ${ROTULO_REGRA[r]}`).join(' · ')}</span>
                <span className="text-xs tabular text-[var(--fg-3)]">{item.ocorrencias > 1 ? `${formatar(item.ocorrencias, 'int')} ocorrências` : item.regras.join(', ')}</span>
              </li>)}
            </ul>
          </section>;
        })}
      </div>}
      <p className="mt-3 border-t border-[var(--border-faint)] pt-2 text-[11px] text-[var(--fg-3)]">R1–R12: padrão de nomenclatura de campanhas, conjuntos e anúncios. U1–U2: flags a_corrigir da RPC dados_black_perfil.</p>
    </SectionCard>
  </div>;
}

type AbaIngresso = 'pessoas' | 'leads' | 'evolucao';
interface PontoIngresso { dia: string; pct: Valor; pctDia: Valor; membros: Valor; leads: Valor }
function listaDias(de: string, ate: string): string[] {
  if (!de || !ate || de > ate) return [];
  const dias: string[] = [];
  for (let dia = de; dia <= ate; dia = deslocarDia(dia, 1)) dias.push(dia);
  return dias;
}
const inteiroOuNulo = (n: Valor) => n === null ? 'Sem dado' : formatar(n, 'int');

function ModalIngresso({ d, onClose, linhas }: { d: DadosTela; onClose: () => void; linhas: LinhaPerfil[] }) {
  const [aba, setAba] = useState<AbaIngresso>('pessoas');
  const [serie, setSerie] = useState<PontoIngresso[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const carregando = aba === 'evolucao' && serie === null && erro === null;
  const { fonte, config, periodo, chave } = d;
  useEffect(() => {
    if (aba !== 'evolucao' || serie !== null) return;
    const dias = listaDias(config.inicio, periodo.ate);
    let vivo = true;
    const consultar = async (): Promise<PontoIngresso[]> => {
      const respostas = new Map<string, Awaited<ReturnType<typeof fonte.grupo>>>();
      for (let i = 0; i < dias.length; i += 4) {
        const lote = dias.slice(i, i + 4);
        const lidas = await Promise.all(lote.map(async (dia) => [dia, await fonte.grupo(chave, { de: config.inicio, ate: dia }, null)] as const));
        lidas.forEach(([dia, resposta]) => respostas.set(dia, resposta));
      }
      let membrosAntes: number | null = 0; let leadsAntes: number | null = 0;
      return dias.map((dia) => {
        const r = respostas.get(dia);
        if (!r || r.erro) throw new Error(r?.erro ?? 'Falha na leitura da série.');
        const g = r.data.ingressoGeral;
        const membros = g?.numerosUnicosNoGrupo ?? null; const leads = g?.leadsUnicos ?? null;
        const pct = g?.pct === null || g?.pct === undefined ? null : g.pct / 100;
        const diaMembros = membros === null || membrosAntes === null ? null : Math.max(0, membros - membrosAntes);
        const diaLeads = leads === null || leadsAntes === null ? null : Math.max(0, leads - leadsAntes);
        membrosAntes = membros; leadsAntes = leads;
        return { dia, pct, pctDia: construirTaxa(diaMembros, diaLeads).valor, membros: diaMembros, leads: diaLeads };
      });
    };
    void consultar().then((pontos) => { if (vivo) setSerie(pontos); }, (e: unknown) => { if (vivo) setErro(e instanceof Error ? e.message : 'Falha na leitura da série.'); });
    return () => { vivo = false; };
  }, [aba, config.inicio, chave, fonte, periodo.ate, serie]);

  const grupos = d.grupo.data?.grupos ?? [];
  return <Modal open onClose={onClose} title="Ingresso no grupo" width={`max-w-4xl ${MODAL_TELA_CHEIA}`}>
    <div className="space-y-3">
      <p className="text-xs text-[var(--fg-3)]">Métrica geral: números únicos que entraram no grupo ÷ leads únicos. A lista individual de participantes não é publicada por uma RPC.</p>
      <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="Detalhes do ingresso no grupo">
        {([{ id: 'pessoas', label: 'Pessoas' }, { id: 'leads', label: 'Leads' }, { id: 'evolucao', label: 'Evolução do percentual' }] as const).map((item) => <button key={item.id} type="button" role="tab" aria-selected={aba === item.id} onClick={() => { if (item.id === 'evolucao') setErro(null); setAba(item.id); }} className={`min-h-10 rounded-[var(--r-md)] px-3 text-xs ${aba === item.id ? 'bg-[var(--accent)] font-semibold text-black' : 'border border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'}`}>{item.label}</button>)}
      </div>
      {aba === 'pessoas' && <div className="space-y-3">
        <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-3 text-sm text-[var(--fg-2)]">A fonte publicada informa totais por grupo, sem nomes ou telefones dos membros.</p>
        <DataTable minWidth={720}>
          <Thead><Th>Grupo</Th><Th>Números únicos</Th><Th>Webhook</Th><Th>Só foto</Th><Th>Leads no grupo</Th><Th>Leads do segmento</Th></Thead>
          <tbody>{grupos.map((g) => <Tr key={g.campanha}><Td className="text-xs">{g.campanha}</Td><Td>{inteiroOuNulo(g.unicos)}</Td><Td>{inteiroOuNulo(g.unicosWebhook)}</Td><Td>{inteiroOuNulo(g.unicosSoFoto)}</Td><Td>{inteiroOuNulo(g.leadsNoGrupo ?? null)}</Td><Td>{inteiroOuNulo(g.leadsDoSegmento ?? null)}</Td></Tr>)}</tbody>
        </DataTable>
        <p className="text-xs text-[var(--fg-2)]">No grupo: {inteiroOuNulo(d.grupo.data?.ingressoGeral?.numerosUnicosNoGrupo ?? null)} · Leads únicos: {inteiroOuNulo(d.grupo.data?.ingressoGeral?.leadsUnicos ?? null)} · Leads cadastrados em algum grupo: {inteiroOuNulo(d.grupo.data?.leadsEmAlgumGrupo ?? null)} · Atualizado pela foto: {d.grupo.data?.atualizado.ultimaFoto ? new Date(d.grupo.data.atualizado.ultimaFoto).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'Sem dado'}.</p>
      </div>}
      {aba === 'leads' && (d.podeVerContato ? <TabelaLeads d={d} linhas={linhas} /> : <p className="py-8 text-center text-sm text-[var(--fg-3)]">A lista de leads com dados pessoais exige a capacidade contato.ver. Os indicadores continuam disponíveis.</p>)}
      {aba === 'evolucao' && <div className="space-y-3">
        {carregando && <p role="status" className="text-sm text-[var(--fg-3)]">Carregando a evolução, com até quatro leituras em paralelo…</p>}
        {erro && <p role="alert" className="text-sm text-[var(--yellow)]">{erro}</p>}
        {serie && <>
          <GraficoLinha rotuloSerie="Ingresso diário" formato="pct" meta={d.config.metas.ingressoGrupo} pontos={serie.map((x) => ({ chave: x.dia, rotulo: `${x.dia.slice(8, 10)}/${x.dia.slice(5, 7)}`, valor: x.pctDia }))} />
          <DataTable minWidth={560}>
            <Thead><Th>Dia</Th><Th>Ingresso no dia</Th><Th>Meta do dia</Th><Th>Acumulado real</Th><Th>Entradas únicas</Th><Th>Novos leads</Th></Thead>
            <tbody>{serie.map((x) => <Tr key={x.dia}><Td>{x.dia.slice(8, 10)}/{x.dia.slice(5, 7)}</Td><Td>{formatar(x.pctDia, 'pct')}</Td><Td>{formatar(d.config.metas.ingressoGrupo, 'pct')}</Td><Td>{formatar(x.pct, 'pct')}</Td><Td>{inteiroOuNulo(x.membros)}</Td><Td>{inteiroOuNulo(x.leads)}</Td></Tr>)}</tbody>
          </DataTable>
        </>}
        <p className="text-[11px] text-[var(--fg-3)]">Fonte: dados_black_grupo com p_ate em cada dia. Ingresso diário = novas entradas únicas ÷ novos leads; acumulado = membros únicos ÷ leads únicos.</p>
      </div>}
    </div>
  </Modal>;
}
