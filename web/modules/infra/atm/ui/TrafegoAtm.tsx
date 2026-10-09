'use client';

import { useState } from 'react';
import { EmptyState, SectionCard } from '@/shared/ui/components';
import type { DadosTrafegoAtm, DiaTrafegoAtm, Resultado } from '../infrastructure/atm-data';
import { dataPtBr } from '../domain/periodo';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const decimal = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

function contar(valor: number | null): string { return valor === null ? 'Sem dado' : inteiro.format(valor); }
function percentual(valor: number | null): string { return valor === null ? 'Sem dado' : `${decimal.format(valor)}%`; }
function dinheiro(centavos: number | null): string { return centavos === null ? 'Sem dado' : moeda.format(centavos / 100); }
function frequencia(valor: number | null): string { return valor === null ? 'Sem dado' : decimal.format(valor); }
function horario(valor: string | null): string {
  return valor ? new Date(valor).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'Sem dado';
}
function dia(valor: string | null): string { return valor ? dataPtBr(valor) : 'Sem dado'; }

function Campo({ label, value, calculado = false }: { label: string; value: string; calculado?: boolean }) {
  return <div className="min-w-0 rounded-[var(--r-md)] bg-[var(--surface-2)] p-3">
    <dt className="text-xs text-[var(--fg-3)]">{label}{calculado && <span className="text-[var(--accent)]"> · cálculo</span>}</dt>
    <dd className="mt-1 break-words text-sm font-semibold tabular text-[var(--fg)]">{value}</dd>
  </div>;
}

function CartaoMetrica({ label, value, calculado = false, hint, index = 0 }: { label: string; value: string; calculado?: boolean; hint?: string; index?: number }) {
  return <article tabIndex={0} title="Fonte: public.dados_atm_trafego · total do período." style={{ animationDelay: `${Math.min(index, 10) * 35}ms`, borderLeft: '4px solid var(--accent)' }} className="atm-historico-card atm-historico-interativo gp-rise min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 shadow-[var(--shadow-sm)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
    <h3 className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">{label}{calculado && <span className="normal-case text-[var(--accent)]"> · cálculo</span>}</h3>
    <p className="mt-2 break-words text-xl font-bold tabular text-[var(--fg)]">{value}</p>
    {hint && <p className="mt-1 break-words text-xs text-[var(--fg-3)]">{hint}</p>}
  </article>;
}

function rotuloMotivo(motivo: string | null): string | undefined {
  if (motivo === 'varias_campanhas') return 'Sem dado · várias campanhas no período.';
  if (motivo === 'periodo_parcial') return 'Sem dado · o período não cobre a campanha inteira.';
  if (motivo === 'sem_total') return 'Sem dado · a API não trouxe o total da campanha.';
  return motivo ? `Sem dado · motivo: ${motivo}` : undefined;
}

function GraficoGastoDiario({ rows }: { rows: DiaTrafegoAtm[] }) {
  if (!rows.length || !rows.some((row) => row.gastoCentavos !== null)) {
    return <EmptyState title="Série diária sem dado" hint="sem dado ainda" />;
  }
  const width = 720;
  const height = 190;
  const max = Math.max(1, ...rows.map((row) => row.gastoCentavos ?? 0));
  const passo = width / rows.length;
  const rotuloCada = Math.max(1, Math.ceil(rows.length / 8));
  return <div className="min-w-0">
    <p className="mb-2 text-xs text-[var(--fg-3)]">Gasto diário · valores na origem em centavos, exibidos em reais.</p>
    <svg viewBox={`0 0 ${width} ${height}`} className="h-auto w-full" role="img" aria-label={`Gasto diário de tráfego em ${rows.length} dias`}>
      <line x1="0" x2={width} y1="145" y2="145" stroke="var(--border-strong)" />
      {rows.map((row, index) => {
        const gasto = row.gastoCentavos;
        const barH = gasto === null ? 0 : Math.max(1, gasto / max * 112);
        const x = index * passo + Math.max(1, passo * 0.2);
        const barW = Math.max(1, passo * 0.6);
        return <g key={`${row.dia ?? 'sem-data'}-${index}`}>
          {gasto !== null && <rect className="atm-historico-barra" x={x} y={145 - barH} width={barW} height={barH} rx="2" fill="var(--accent)" style={{ animationDelay: `${Math.min(index, 10) * 25}ms` }}><title>{`${dia(row.dia)} · ${dinheiro(gasto)}`}</title></rect>}
          {index % rotuloCada === 0 && row.dia && <text x={x + barW / 2} y="166" textAnchor="middle" fontSize="9" fill="var(--fg-3)">{row.dia.slice(5)}</text>}
        </g>;
      })}
    </svg>
  </div>;
}

function LinhaDiaria({ row, index, calculados }: { row: DiaTrafegoAtm; index: number; calculados: Set<string> }) {
  return <details style={{ animationDelay: `${Math.min(index, 10) * 30}ms` }} className="atm-historico-card gp-rise min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] shadow-[var(--shadow-sm)]">
    <summary title="Fonte: public.dados_atm_trafego · série diária." className="cursor-pointer list-none p-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] sm:p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <strong className="text-sm text-[var(--fg)]">{dia(row.dia)}</strong>
        <span className="text-xs text-[var(--accent)]">Ver métricas do dia</span>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
        <span>Gasto: <strong>{dinheiro(row.gastoCentavos)}</strong></span>
        <span>Impressões: <strong>{contar(row.impressoes)}</strong></span>
        <span>Cliques no link: <strong>{contar(row.cliquesLink)}</strong></span>
        <span>Visualizações de página: <strong>{contar(row.landingPageViews)}</strong></span>
      </div>
    </summary>
    <dl className="grid grid-cols-2 gap-2 border-t border-[var(--border)] p-3 sm:grid-cols-3 lg:grid-cols-4 sm:p-4">
      <Campo label="Alcance" value={contar(row.alcance)} />
      <Campo label="Frequência" value={frequencia(row.frequencia)} />
      <Campo label="Impressões" value={contar(row.impressoes)} />
      <Campo label="Cliques no link" value={contar(row.cliquesLink)} />
      <Campo label="Cliques totais" value={contar(row.cliquesTotal)} />
      <Campo label="Cliques de saída" value={contar(row.cliquesSaida)} />
      <Campo label="Vídeo · plays" value={contar(row.videoPlays)} />
      <Campo label="Vídeo · 25%" value={contar(row.videoP25)} />
      <Campo label="Vídeo · 50%" value={contar(row.videoP50)} />
      <Campo label="Vídeo · 75%" value={contar(row.videoP75)} />
      <Campo label="Vídeo · 100%" value={contar(row.videoP100)} />
      <Campo label="Vídeo · ThruPlay" value={contar(row.videoThruplay)} />
      <Campo label="Visualizações de página" value={contar(row.landingPageViews)} />
      <Campo label="Engajamento" value={contar(row.engajamento)} />
      <Campo label="CPM" value={dinheiro(row.cpmCentavos)} calculado={calculados.has('cpm_centavos')} />
      <Campo label="CTR" value={percentual(row.ctrPct)} calculado={calculados.has('ctr_pct')} />
      <Campo label="CPC" value={dinheiro(row.cpcCentavos)} calculado={calculados.has('cpc_centavos')} />
    </dl>
    {calculados.size > 0 && <p className="px-3 pb-3 text-[11px] text-[var(--fg-3)] sm:px-4">Campos calculados: CPM, CTR e CPC.</p>}
  </details>;
}

const CORES_FUNIL = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--yellow)', 'var(--green)'];

type EtapaTrafego = { id: string; rotulo: string; valor: number | null };

// Funil visual da distribuição: a base é a impressão; a passagem de uma etapa para a outra é cálculo da tela.
function FunilTrafego({ etapas }: { etapas: EtapaTrafego[] }) {
  const [foco, setFoco] = useState<string | null>(null);
  const base = etapas[0]?.valor ?? null;
  return <ol className="space-y-1" aria-label="Funil de distribuição">
    {etapas.map((etapa, k) => {
      const anterior = k > 0 ? etapas[k - 1].valor : null;
      const passagem = etapa.valor !== null && anterior ? etapa.valor * 100 / anterior : null;
      const doTotal = etapa.valor !== null && base ? etapa.valor / base : null;
      const largura = doTotal === null ? 0 : Math.min(100, Math.max(2, doTotal * 100));
      const cor = CORES_FUNIL[k % CORES_FUNIL.length];
      return <li key={etapa.id} className="min-w-0">
        {k > 0 && <div className="flex items-center justify-center gap-1 py-1 text-xs text-[var(--fg-3)]">
          <span aria-hidden="true">↓</span>
          <span><strong className="tabular text-[var(--fg-2)]">{percentual(passagem)}</strong> da etapa anterior · cálculo</span>
        </div>}
        <div tabIndex={0} title={`${etapa.rotulo}: ${contar(etapa.valor)}${k > 0 ? ` · ${percentual(passagem)} sobre a etapa anterior (cálculo)` : ''} · Fonte: public.dados_atm_trafego`} onMouseEnter={() => setFoco(etapa.id)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(etapa.id)} onBlur={() => setFoco(null)} className={'atm-historico-interativo relative h-12 overflow-hidden rounded-[var(--r-md)] bg-[var(--surface-3)] ' + (foco === null || foco === etapa.id ? '' : 'opacity-35')}>
          <div aria-hidden="true" className="atm-historico-funil-bar absolute inset-y-0 left-1/2 -translate-x-1/2 rounded-[var(--r-md)] border" style={{ width: `${largura}%`, borderColor: cor, background: `color-mix(in srgb, ${cor} 28%, transparent)`, animationDelay: `${k * 90}ms` }} />
          <div className="relative flex h-full items-center justify-between gap-2 px-3">
            <span className="min-w-0 truncate text-sm font-medium text-[var(--fg)]">{etapa.rotulo}</span>
            <span className="shrink-0 text-right">
              <span className={'block text-base font-bold tabular leading-tight ' + (etapa.valor === null ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]')}>{contar(etapa.valor)}</span>
              {k > 0 && <span className="block text-[10px] text-[var(--fg-3)]">{percentual(doTotal === null ? null : doTotal * 100)} das impressões</span>}
            </span>
          </div>
        </div>
      </li>;
    })}
  </ol>;
}

export function TrafegoAtm({ result }: { result: Resultado<DadosTrafegoAtm> }) {
  const data = result.data;
  const reachReason = rotuloMotivo(data.total.alcanceMotivo);
  const reachUnavailable = data.total.alcanceMotivo !== null;
  const alcance = reachUnavailable ? null : data.total.alcance;
  const frequenciaTotal = reachUnavailable ? null : data.total.frequencia;
  const calculados = new Set(data.calculados);
  const periodo = data.periodoDe && data.periodoAte ? `${dia(data.periodoDe)} a ${dia(data.periodoAte)}` : 'Período sem dado';
  const campanhasSemDado = data.campanhas.length === 0;

  return <div className="atm-historico-panel-enter min-w-0 space-y-4">
    <div className="flex flex-wrap items-end justify-between gap-2">
      <p className="text-sm text-[var(--fg-2)]">Distribuição de conteúdo · {periodo}{data.moeda && data.moeda !== 'BRL' ? ` · ${data.moeda}` : ''}</p>
      <p className="text-xs text-[var(--fg-3)]" aria-live="polite">Meta coletado às {data.coletadoEm ? horario(data.coletadoEm) : 'sem dado'}</p>
    </div>
    {result.erro && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{result.erro}{!result.semDado ? ' · mostrando a última leitura válida' : ''}</p>}
    {result.semDado && <SectionCard><EmptyState title="Tráfego sem dado ainda" hint="A coleta e os campos da API aparecem quando estiverem disponíveis para o período." /></SectionCard>}
    {!result.semDado && <>
      <SectionCard title="Funil de distribuição" subtitle="Totais do período. Alcance e frequência não são somados entre dias ou campanhas.">
        {reachReason && <p role="status" className="mb-3 rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{reachReason}{data.total.alcanceDe || data.total.alcanceAte ? ` Cobertura informada: ${dia(data.total.alcanceDe)} a ${dia(data.total.alcanceAte)}.` : ''}</p>}
        <FunilTrafego etapas={[
          { id: 'impressoes', rotulo: 'Impressões', valor: data.total.impressoes },
          { id: 'plays', rotulo: 'Vídeo · plays', valor: data.total.videoPlays },
          { id: 'p25', rotulo: 'Vídeo · 25%', valor: data.total.videoP25 },
          { id: 'p50', rotulo: 'Vídeo · 50%', valor: data.total.videoP50 },
          { id: 'p75', rotulo: 'Vídeo · 75%', valor: data.total.videoP75 },
          { id: 'p100', rotulo: 'Vídeo · 100%', valor: data.total.videoP100 },
          { id: 'cliques', rotulo: 'Cliques no link', valor: data.total.cliquesLink },
          { id: 'lpv', rotulo: 'Visualizações de página', valor: data.total.landingPageViews },
        ]} />
        <div className="mt-5 grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <CartaoMetrica label="Gasto" value={dinheiro(data.total.gastoCentavos)} index={0} />
          <CartaoMetrica label="Impressões" value={contar(data.total.impressoes)} index={1} />
          <CartaoMetrica label="Alcance" value={contar(alcance)} hint={reachReason} index={2} />
          <CartaoMetrica label="Frequência" value={frequencia(frequenciaTotal)} hint={reachReason} index={3} />
          <CartaoMetrica label="Vídeo · plays" value={contar(data.total.videoPlays)} index={4} />
          <CartaoMetrica label="Vídeo · 25%" value={contar(data.total.videoP25)} index={5} />
          <CartaoMetrica label="Vídeo · 50%" value={contar(data.total.videoP50)} index={6} />
          <CartaoMetrica label="Vídeo · 75%" value={contar(data.total.videoP75)} index={7} />
          <CartaoMetrica label="Vídeo · 100%" value={contar(data.total.videoP100)} index={8} />
          <CartaoMetrica label="Vídeo · ThruPlay" value={contar(data.total.videoThruplay)} index={9} />
          <CartaoMetrica label="Cliques no link" value={contar(data.total.cliquesLink)} index={10} />
          <CartaoMetrica label="Visualizações de página" value={contar(data.total.landingPageViews)} index={11} />
        </div>
      </SectionCard>

      <SectionCard title="Custos e atividade" subtitle="Os campos marcados como cálculo são identificados pelo contrato da RPC.">
        <div className="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <CartaoMetrica label="CPM" value={dinheiro(data.total.cpmCentavos)} calculado={calculados.has('cpm_centavos')} />
          <CartaoMetrica label="CTR" value={percentual(data.total.ctrPct)} calculado={calculados.has('ctr_pct')} />
          <CartaoMetrica label="CPC" value={dinheiro(data.total.cpcCentavos)} calculado={calculados.has('cpc_centavos')} />
          <CartaoMetrica label="Cliques totais" value={contar(data.total.cliquesTotal)} />
          <CartaoMetrica label="Cliques de saída" value={contar(data.total.cliquesSaida)} />
          <CartaoMetrica label="Engajamento" value={contar(data.total.engajamento)} />
          <CartaoMetrica label="Dias com dados" value={contar(data.total.dias)} hint={data.total.primeiroDia || data.total.ultimoDia ? `${dia(data.total.primeiroDia)} a ${dia(data.total.ultimoDia)}` : undefined} />
        </div>
      </SectionCard>

      <SectionCard title="Evolução diária" subtitle="Série diária recebida pela RPC, sem somar alcance ou frequência para os totais.">
        <GraficoGastoDiario rows={data.dias} />
        <div className="mt-4 max-h-[70vh] space-y-2 overflow-y-auto">
          {data.dias.length ? data.dias.map((row, index) => <LinhaDiaria key={`${row.dia ?? 'sem-data'}-${index}`} row={row} index={index} calculados={calculados} />) : <EmptyState title="Série diária sem dado" hint="sem dado ainda" />}
        </div>
      </SectionCard>

      <SectionCard title="Campanhas vinculadas" subtitle="Nomes, status e objetivo conforme devolvidos pelo banco.">
        {campanhasSemDado ? <EmptyState title="Campanhas sem dado" hint="sem dado ainda" /> : <div className="grid min-w-0 gap-3 md:grid-cols-2">
          {data.campanhas.map((campanha, index) => <article key={campanha.id ?? `${campanha.nome ?? 'campanha'}-${index}`} tabIndex={0} title="Fonte: public.dados_atm_trafego · campanha vinculada." style={{ animationDelay: `${Math.min(index, 10) * 35}ms`, borderLeft: '4px solid var(--accent)' }} className="atm-historico-card atm-historico-interativo gp-rise min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 shadow-[var(--shadow-sm)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
            <h3 className="break-words text-sm font-semibold text-[var(--fg)]">{campanha.nome ?? 'Sem dado'}</h3>
            <dl className="mt-3 grid grid-cols-2 gap-2">
              <Campo label="Status" value={campanha.status ?? 'Sem dado'} />
              <Campo label="Objetivo" value={campanha.objetivo ?? 'Sem dado'} />
              <Campo label="Conta" value={campanha.conta ?? 'Sem dado'} />
              <Campo label="Gasto" value={dinheiro(campanha.gastoCentavos)} />
              <Campo label="Primeiro dia" value={dia(campanha.primeiroDia)} />
              <Campo label="Último dia" value={dia(campanha.ultimoDia)} />
            </dl>
          </article>)}
        </div>}
      </SectionCard>
    </>}
  </div>;
}
