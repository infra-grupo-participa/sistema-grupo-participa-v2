'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { DataTable, EmptyState, KpiCard, SectionCard, Tabs, Td, Th, Thead, Tr, idsAba } from '@/shared/ui/components';
import { carregarHistoricoEdicoes } from '../infrastructure/historico-data';
import {
  descreverFonte, ehProvisorio, etapasFunil, formatarHistorico, indicadoresEdicao, METRICAS_HISTORICO, metricaHistorico,
  periodoEdicao, picosAulas, ROTULO_CAMPO_FONTE, SECOES_HISTORICO, SEM_VALOR,
  type CampoFonteHistorico, type EdicaoHistorico, type MetricaHistorico,
} from '../domain/historico';

const ABA_COMPARATIVO = 'comparativo';
const ID_ABAS = 'atm-historico';
const CORES_FUNIL = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--yellow)', 'var(--green)'];

type PropsView = {
  edicoes: EdicaoHistorico[];
  carregando: boolean;
  erro: string | null;
  lidoEm: Date | null;
  onRecarregar: () => void;
};

/** Carrega o histórico da família (RPC `dados_historico_edicoes`) e segura o último dado bom em caso de falha. */
export function HistoricoAtm({ familia }: { familia: string }) {
  const [edicoes, setEdicoes] = useState<EdicaoHistorico[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [lidoEm, setLidoEm] = useState<Date | null>(null);
  const emCurso = useRef(false);

  const carregar = useCallback(async () => {
    if (emCurso.current) return;
    emCurso.current = true;
    try {
      const r = await carregarHistoricoEdicoes(familia);
      if (!r.erro) {
        setEdicoes(r.data);
        setLidoEm(new Date());
      }
      setErro(r.erro);
    } finally {
      emCurso.current = false;
      setCarregando(false);
    }
  }, [familia]);

  useEffect(() => { void carregar(); }, [carregar]);

  return <HistoricoAtmView edicoes={edicoes} carregando={carregando} erro={erro} lidoEm={lidoEm} onRecarregar={() => { setCarregando(true); void carregar(); }} />;
}

/** Parte visual, sem I/O: recebe as edições já ordenadas e em reais. */
export function HistoricoAtmView({ edicoes, carregando, erro, lidoEm, onRecarregar }: PropsView) {
  const [aba, setAba] = useState(ABA_COMPARATIVO);
  const abaAtiva = aba === ABA_COMPARATIVO || edicoes.some((e) => e.chave === aba) ? aba : ABA_COMPARATIVO;
  const desatualizado = erro !== null && edicoes.length > 0;
  const hora = lidoEm ? lidoEm.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' }) : null;
  const idx = edicoes.findIndex((e) => e.chave === abaAtiva);
  const ids = idsAba(ID_ABAS, abaAtiva);

  return <section aria-labelledby="atm-historico-titulo" className="min-w-0 space-y-4">
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h2 id="atm-historico-titulo" className="text-lg font-bold text-[var(--fg)]">Histórico das edições</h2>
        <p className="text-sm text-[var(--fg-2)]">Números fechados de cada Seminário ATM. Taxas, CAC, ROAS e CPL são calculados na tela a partir deles.</p>
      </div>
      <div className="flex items-center gap-3">
        <span className="text-xs text-[var(--fg-3)]" aria-live="polite">{carregando ? 'Lendo…' : hora ? `Lido às ${hora}` : 'aguardando leitura'}</span>
        <button type="button" onClick={onRecarregar} disabled={carregando} className="min-h-10 rounded-[var(--r-md)] border border-[var(--border)] px-4 text-sm text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">Recarregar</button>
      </div>
    </div>

    {erro && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{erro}{desatualizado && hora ? ` Mostrando a leitura de ${hora}.` : ''}</p>}

    {edicoes.length === 0
      ? <SectionCard><EmptyState title={carregando ? 'Carregando o histórico…' : 'Histórico sem edições'} hint={carregando ? undefined : 'sem dado ainda · as edições aparecem quando o banco devolver o histórico desta família.'} /></SectionCard>
      : <div className={'min-w-0 transition-opacity ' + (desatualizado ? 'opacity-60' : '')}>
        <Tabs idBase={ID_ABAS} label="Visões do histórico" active={abaAtiva} onChange={setAba} tabs={[{ k: ABA_COMPARATIVO, l: 'Comparativo geral' }, ...edicoes.map((e) => ({ k: e.chave, l: e.rotulo }))]} />
        <div role="tabpanel" id={ids.panel} aria-labelledby={ids.tab} tabIndex={0} className="min-w-0 focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
          {abaAtiva === ABA_COMPARATIVO || idx < 0
            ? <ComparativoGeral edicoes={edicoes} />
            : <EdicaoDetalhe edicao={edicoes[idx]} anterior={edicoes[idx - 1] ?? null} />}
        </div>
      </div>}
  </section>;
}

function ValorComFonte({ m, e, anterior, grande = false }: { m: MetricaHistorico; e: EdicaoHistorico; anterior: EdicaoHistorico | null; grande?: boolean }) {
  const v = m.valor(e, indicadoresEdicao(e, anterior));
  const prov = ehProvisorio(m, e, anterior);
  const texto = formatarHistorico(v, m.formato);
  return <span title={descreverFonte(m, e, anterior)} className={'relative inline-flex flex-col items-end tabular ' + (texto === SEM_VALOR ? 'text-[var(--fg-3)]' : '')}>
    <span className={grande ? 'font-bold' : ''}>{texto}{prov && <><span aria-hidden="true" className="ml-0.5 text-[var(--yellow)]">*</span><span className="sr-only"> (provisório)</span></>}</span>
    {v === null && m.vazio && <span className="text-[10px] font-normal text-[var(--fg-3)]">{m.vazio}</span>}
  </span>;
}

function ComparativoGeral({ edicoes }: { edicoes: EdicaoHistorico[] }) {
  return <div className="space-y-3">
    <DataTable minWidth={220 + edicoes.length * 140}>
      <caption className="sr-only">Comparativo geral: métricas nas linhas, uma coluna por edição</caption>
      <Thead>
        <Th className="sticky left-0 z-[2] bg-[var(--surface-3)]">Métrica</Th>
        {edicoes.map((e) => <th key={e.chave} scope="col" className="px-3 py-2.5 text-right text-[11px] font-semibold uppercase tracking-[0.06em] whitespace-nowrap">{e.rotulo}</th>)}
      </Thead>
      <tbody>
        {SECOES_HISTORICO.map((secao) => <SecaoComparativo key={secao} secao={secao} edicoes={edicoes} />)}
      </tbody>
    </DataTable>
    <p className="text-xs text-[var(--fg-3)]">Passe o mouse sobre o número para ver a fonte. <span className="text-[var(--yellow)]">*</span> provisório. {SEM_VALOR} = sem dado na fonte ou divisão por zero. Comparativo = pico da edição ÷ pico da mesma aula da edição anterior.</p>
    <FontesDetalhe edicoes={edicoes} />
  </div>;
}

function SecaoComparativo({ secao, edicoes }: { secao: string; edicoes: EdicaoHistorico[] }) {
  const metricas = METRICAS_HISTORICO.filter((m) => m.secao === secao);
  return <>
    <tr className="border-t border-[var(--border)]"><th scope="colgroup" colSpan={edicoes.length + 1} className="bg-[var(--surface-2)] px-3 pb-1 pt-4 text-left text-[11px] font-semibold uppercase tracking-wider text-[var(--accent)]"><span className="sticky left-3">{secao}</span></th></tr>
    {metricas.map((m) => {
      const fundo = m.destaque ? 'bg-[color-mix(in_srgb,var(--accent)_14%,var(--surface-2))]' : 'bg-[var(--surface-2)]';
      return <Tr key={m.id} className={m.destaque ? fundo + ' font-semibold' : ''}>
        <th scope="row" className={'sticky left-0 z-[1] px-3 py-2.5 text-left text-sm font-medium text-[var(--fg-2)] ' + fundo}>
          <span className={m.destaque ? 'text-[var(--fg)]' : ''}>{m.rotulo}</span>
          {m.destaque && <span className="ml-2 rounded-full border border-[var(--accent-border)] px-2 py-0.5 text-[10px] uppercase text-[var(--accent)]">principal</span>}
        </th>
        {edicoes.map((e, i) => <Td key={e.chave} className={'text-right ' + (m.destaque ? 'text-[var(--accent)]' : 'text-[var(--fg)]')}><ValorComFonte m={m} e={e} anterior={edicoes[i - 1] ?? null} grande={m.destaque} /></Td>)}
      </Tr>;
    })}
  </>;
}

function FontesDetalhe({ edicoes }: { edicoes: EdicaoHistorico[] }) {
  const campos = Object.keys(ROTULO_CAMPO_FONTE) as CampoFonteHistorico[];
  return <details className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-sm">
    <summary className="cursor-pointer font-medium text-[var(--fg)]">Fonte de cada número</summary>
    <div className="mt-3 grid gap-4 md:grid-cols-2">
      {edicoes.map((e) => <div key={e.chave} className="min-w-0">
        <h4 className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{e.rotulo}</h4>
        <dl className="space-y-1">{campos.map((c) => <div key={c} className="grid grid-cols-[minmax(0,10rem)_minmax(0,1fr)] gap-2">
          <dt className="text-[var(--fg-3)]">{ROTULO_CAMPO_FONTE[c]}</dt>
          <dd className="break-words text-[var(--fg-2)]">{e.fontes[c] ?? 'fonte não informada pelo banco'}{e.provisorio.includes(c) && <span className="ml-1 text-[var(--yellow)]">(provisório)</span>}</dd>
        </div>)}</dl>
      </div>)}
    </div>
  </details>;
}

function EdicaoDetalhe({ edicao: e, anterior }: { edicao: EdicaoHistorico; anterior: EdicaoHistorico | null }) {
  const i = indicadoresEdicao(e, anterior);
  const periodo = periodoEdicao(e);
  const card = (id: string, hint?: string) => {
    const m = metricaHistorico(id);
    const prov = ehProvisorio(m, e, anterior);
    const extra = [hint, prov ? 'provisório' : null].filter(Boolean).join(' · ');
    return <KpiCard key={id} label={m.rotulo} value={formatarHistorico(m.valor(e, i), m.formato)} title={descreverFonte(m, e, anterior)} hint={extra || undefined} bar={id === 'vendas' || id === 'receita_liquida' ? 'green' : 'accent'} />;
  };
  const principal = metricaHistorico('conversao_pre_checkout');
  const provPrincipal = ehProvisorio(principal, e, anterior);
  const camposProv = e.provisorio.map((c) => ROTULO_CAMPO_FONTE[c as CampoFonteHistorico] ?? c);

  return <div className="space-y-4">
    <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <h3 className="text-xl font-bold text-[var(--fg)]">{e.rotulo}</h3>
      {periodo && <span className="text-sm text-[var(--fg-2)]">{periodo}</span>}
      {camposProv.length > 0 && <span className="rounded-full border border-[var(--yellow)]/50 px-2 py-0.5 text-xs text-[var(--yellow)]">Provisório: {camposProv.join(', ')}</span>}
    </div>

    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div title={descreverFonte(principal, e, anterior)} className="gp-rise relative min-w-0 overflow-hidden rounded-[var(--r-lg)] border border-[var(--accent-border)] bg-[color-mix(in_srgb,var(--accent)_10%,var(--surface-2))] p-5 shadow-[var(--highlight-surface),var(--shadow-sm)] col-span-2 lg:row-span-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Conversão sobre o pré-checkout · principal</div>
        <div className={'mt-2 text-5xl font-bold tabular leading-none tracking-[-0.03em] ' + (i.conversaoPreCheckout === null ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]')}>{formatarHistorico(i.conversaoPreCheckout, 'percentual')}</div>
        <p className="mt-3 text-sm text-[var(--fg-2)]">{formatarHistorico(e.vendas, 'inteiro')} vendas de {formatarHistorico(e.preCheckout, 'inteiro')} pessoas no pré-checkout{provPrincipal ? ' · provisório' : ''}</p>
        <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
          <div><div className="text-xs text-[var(--fg-3)]">Sobre o grupo</div><div className="font-semibold tabular text-[var(--fg)]">{formatarHistorico(i.conversaoGrupo, 'percentual')}</div></div>
          <div><div className="text-xs text-[var(--fg-3)]">Sobre os leads</div><div className="font-semibold tabular text-[var(--fg)]">{formatarHistorico(i.conversaoLeads, 'percentual')}</div></div>
        </div>
      </div>
      {card('receita_liquida')}
      {card('roas')}
      {card('vendas')}
      {card('cac')}
    </div>

    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      {card('leads')}
      {card('grupo', `${formatarHistorico(i.taxaGrupo, 'percentual')} dos leads`)}
      {card('taxa_grupo')}
      {card('invest_total', `tráfego ${formatarHistorico(e.investTrafego, 'moeda')} · disparo ${formatarHistorico(e.investDisparo, 'moeda')}`)}
      {card('cpl')}
    </div>

    <div className="grid gap-4 lg:grid-cols-2">
      <SectionCard title="Pico ao vivo por aula" subtitle={anterior ? `Retenção sobre a aula anterior e comparativo com a mesma aula de ${anterior.rotulo}.` : 'Retenção sobre a aula anterior. Primeira edição: sem comparativo.'}>
        <GraficoPicos e={e} anterior={anterior} />
      </SectionCard>
      <SectionCard title="Funil da edição" subtitle="Leads até vendas, com a passagem de uma etapa para a outra.">
        <FunilEdicao e={e} />
      </SectionCard>
    </div>

    <FontesDetalhe edicoes={[e]} />
  </div>;
}

function GraficoPicos({ e, anterior }: { e: EdicaoHistorico; anterior: EdicaoHistorico | null }) {
  const picos = picosAulas(e, anterior);
  const max = Math.max(1, ...picos.map((p) => p.valor ?? 0));
  const largura = 360;
  const alturaUtil = 130;
  const base = 160;
  const passo = largura / 3;
  const resumo = picos.map((p) => `dia ${p.dia}: ${p.valor === null ? 'sem dado' : formatarHistorico(p.valor, 'inteiro')}`).join(', ');
  return <div className="min-w-0">
    <svg viewBox={`0 0 ${largura} 185`} className="h-auto w-full max-h-64" role="img" aria-label={`Pico ao vivo por aula, ${resumo}`}>
      <line x1="0" x2={largura} y1={base} y2={base} stroke="var(--border-strong)" />
      {picos.map((p, k) => {
        const x = k * passo + passo / 2;
        const w = passo * 0.52;
        if (p.valor === null) {
          return <g key={p.dia}>
            <rect x={x - w / 2} y={base - 50} width={w} height={50} rx="6" fill="none" stroke="var(--border-strong)" strokeDasharray="4 4" />
            <text x={x} y={base - 22} textAnchor="middle" fontSize="11" fill="var(--fg-3)">{p.dia === 3 ? 'sem dia 3' : 'sem dado'}</text>
            <text x={x} y={base + 18} textAnchor="middle" fontSize="12" fill="var(--fg-2)">Dia {p.dia}</text>
          </g>;
        }
        const h = Math.max(2, (p.valor / max) * alturaUtil);
        return <g key={p.dia}>
          <rect x={x - w / 2} y={base - h} width={w} height={h} rx="6" fill={k === 0 ? 'var(--accent)' : 'color-mix(in srgb, var(--accent) 62%, var(--surface-3))'}><title>{descreverFonte(metricaHistorico(p.campo), e, anterior)}</title></rect>
          <text x={x} y={base - h - 7} textAnchor="middle" fontSize="15" fontWeight="700" fill="var(--fg)">{formatarHistorico(p.valor, 'inteiro')}</text>
          <text x={x} y={base + 18} textAnchor="middle" fontSize="12" fill="var(--fg-2)">Dia {p.dia}</text>
        </g>;
      })}
    </svg>
    <dl className="mt-2 grid grid-cols-3 gap-2 text-xs">
      {picos.map((p) => <div key={p.dia} className="min-w-0 rounded-[var(--r-md)] bg-[var(--surface-3)] p-2">
        <dt className="font-semibold text-[var(--fg-2)]">Dia {p.dia}</dt>
        <dd className="mt-1 text-[var(--fg-3)]">Retenção <strong className="tabular text-[var(--fg)]" title={p.dia === 1 ? 'Primeira aula: sem aula anterior.' : descreverFonte(metricaHistorico(p.dia === 2 ? 'retencao_d2' : 'retencao_d3'), e, anterior)}>{p.dia === 1 ? SEM_VALOR : formatarHistorico(p.retencao, 'percentual')}</strong></dd>
        <dd className="text-[var(--fg-3)]">Contra a anterior <strong className="tabular text-[var(--fg)]" title={descreverFonte(metricaHistorico(`comparativo_d${p.dia}`), e, anterior)}>{formatarHistorico(p.comparativo, 'percentual')}</strong></dd>
        {p.valor === null && p.dia === 3 && <dd className="text-[var(--fg-3)]">sem dia 3</dd>}
      </div>)}
    </dl>
  </div>;
}

function FunilEdicao({ e }: { e: EdicaoHistorico }) {
  const etapas = etapasFunil(e);
  return <ol className="space-y-1" aria-label="Funil da edição">
    {etapas.map((etapa, k) => {
      const largura = etapa.doTotal === null ? 0 : Math.min(100, Math.max(2, etapa.doTotal * 100));
      const cor = CORES_FUNIL[k % CORES_FUNIL.length];
      const m = metricaHistorico(etapa.id);
      return <li key={etapa.id} className="min-w-0">
        {k > 0 && <div className="flex items-center justify-center gap-1 py-1 text-xs text-[var(--fg-3)]">
          <span aria-hidden="true">↓</span>
          <span><strong className="tabular text-[var(--fg-2)]">{formatarHistorico(etapa.passagem, 'percentual')}</strong> da etapa anterior</span>
        </div>}
        <div className="relative h-12 overflow-hidden rounded-[var(--r-md)] bg-[var(--surface-3)]" title={descreverFonte(m, e, null)}>
          <div aria-hidden="true" className="absolute inset-y-0 left-1/2 -translate-x-1/2 rounded-[var(--r-md)] border" style={{ width: `${largura}%`, borderColor: cor, background: `color-mix(in srgb, ${cor} 28%, transparent)` }} />
          <div className="relative flex h-full items-center justify-between gap-2 px-3">
            <span className="min-w-0 truncate text-sm font-medium text-[var(--fg)]">{etapa.rotulo}</span>
            <span className="shrink-0 text-right">
              <span className={'block text-base font-bold tabular leading-tight ' + (etapa.valor === null ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]')}>{formatarHistorico(etapa.valor, 'inteiro')}</span>
              {k > 0 && <span className="block text-[10px] text-[var(--fg-3)]">{formatarHistorico(etapa.doTotal, 'percentual')} dos leads</span>}
            </span>
          </div>
        </div>
      </li>;
    })}
  </ol>;
}
