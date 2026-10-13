'use client';

// Aba 5, Histórico (molde HistoricoAtm do ATM). Régua de dias que "toca" o funil dia a dia (autoplay só sem
// movimento reduzido) e o gráfico do período: investimento por dia em barras, pessoas únicas acumuladas desde o
// início do projeto contra a meta acumulada (650 por dia desde o início da captação). O funil do dia é só da
// captação (C2 e C3), como na Visão geral; o investimento e o acumulado seguem o funil e o canal do seletor.
import { useEffect, useMemo, useState } from 'react';
import { KpiCard, SectionCard } from '@/shared/ui/components';
import { ehCaptacao, filtrarDias, filtrarLinhas, taxa } from '../domain/metricas';
import { serieHistorico, type DiaHistorico } from '../domain/historico';
import { diaDe } from '../domain/recorte';
import type { Valor } from '../domain/tipos';
import type { DadosTela } from './contexto';
import { formatar, inteiro, moeda, Numero, Taxa, usePrefereMenosMovimento } from './pecas';

const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
const PASSO_MS = 900;

export function AbaHistorico({ d }: { d: DadosTela }) {
  const reduzido = usePrefereMenosMovimento();
  const { serie, serieCap } = useMemo(() => {
    const fim = d.diasPeriodo[d.diasPeriodo.length - 1] ?? '';
    const f = { funil: d.recorte.funil, canal: d.recorte.canal };
    const dias = filtrarDias(d.diasTodos, d.idx, f);
    const linhas = filtrarLinhas(d.linhasTodas, f).filter((l) => diaDe(l.criadoEm) <= fim);
    const cfg = { inicioCaptacao: d.config.inicioCaptacao, metaLeadsDia: d.config.metaLeadsDia };
    return {
      serie: serieHistorico(dias, linhas, d.diasPeriodo, cfg),
      serieCap: serieHistorico(dias.filter((x) => ehCaptacao(d.idx.campanhaDoAnuncio(x.anuncioId)?.funil)), linhas.filter((l) => ehCaptacao(l.funil)), d.diasPeriodo, cfg),
    };
  }, [d.diasTodos, d.linhasTodas, d.idx, d.recorte.funil, d.recorte.canal, d.diasPeriodo, d.config.inicioCaptacao, d.config.metaLeadsDia]);

  const ultimo = serie.length - 1;
  const [escolhido, setEscolhido] = useState<number | null>(null);
  const [tocando, setTocando] = useState(false);
  const i = escolhido === null ? ultimo : Math.min(escolhido, ultimo);
  const rodando = tocando && !reduzido && ultimo > 0;

  useEffect(() => {
    if (!rodando) return;
    const t = window.setInterval(() => {
      setEscolhido((atual) => {
        const prox = (atual === null || atual >= ultimo ? -1 : atual) + 1;
        return prox;
      });
    }, PASSO_MS);
    return () => window.clearInterval(t);
  }, [rodando, ultimo]);

  if (serie.length === 0) return <p className="text-sm text-[var(--fg-3)]">Sem dia no período.</p>;
  const dia = serie[i];
  const cap = serieCap[i];
  const meta = dia.metaAcumulada;

  return (
    <div className="space-y-4">
      <SectionCard title="Dia a dia" subtitle="Arraste a régua ou toque play para o funil andar pelos dias do período.">
        <div className="flex flex-wrap items-center gap-3">
          <button type="button" onClick={() => { if (escolhido === null || escolhido >= ultimo) setEscolhido(0); setTocando((x) => !x); }}
            disabled={reduzido || ultimo === 0} aria-pressed={rodando}
            title={reduzido ? 'Animação desligada (o sistema pede menos movimento)' : undefined}
            className="inline-flex min-h-9 items-center rounded-[var(--r-md)] border border-[var(--border-accent)] px-3 text-xs text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:cursor-not-allowed disabled:opacity-50">
            {rodando ? 'Pausar' : 'Tocar'}
          </button>
          <label className="flex min-w-0 flex-1 items-center gap-2 text-xs text-[var(--fg-3)]">
            <span className="sr-only">Dia</span>
            <input type="range" min={0} max={ultimo} value={i} onChange={(e) => { setTocando(false); setEscolhido(Number(e.target.value)); }}
              aria-valuetext={dataCurta(dia.dia)} className="min-w-0 flex-1 accent-[var(--accent)] max-md:h-11" />
            <span className="w-12 shrink-0 text-right font-semibold tabular text-[var(--fg)]">{dataCurta(dia.dia)}</span>
          </label>
        </div>

        <div className="mt-3 grid grid-cols-2 gap-3 max-sm:grid-cols-1 lg:grid-cols-4">
          <KpiCard label="Investimento do dia" value={moeda(dia.gasto)} bar="yellow" hint="Funil e canal do seletor" />
          <KpiCard label="Cadastros do dia" value={inteiro(dia.cadastros)} bar="accent" hint={`${inteiro(dia.leadsPagos)} vieram de anúncio`} />
          <KpiCard label="Pessoas novas no dia" value={inteiro(dia.pessoasNovas)} bar="green" hint="Primeira vez na lista" />
          <KpiCard label="Acumulado x meta" value={inteiro(dia.pessoasAcumuladas)} bar={meta !== null && dia.pessoasAcumuladas >= meta ? 'green' : 'red'}
            hint={meta === null ? 'Antes do início da captação, sem meta' : `Meta acumulada ${inteiro(meta)}`} />
        </div>

        <FunilDia key={dia.dia} dia={cap} />
      </SectionCard>

      <SectionCard title="Acumulado contra a meta" subtitle="Barras: investimento por dia. Linha cheia: pessoas únicas acumuladas desde o início. Tracejada: meta acumulada.">
        <Grafico serie={serie} ativo={i} onEscolher={(k) => { setTocando(false); setEscolhido(k); }} />
      </SectionCard>
    </div>
  );
}

function FunilDia({ dia }: { dia: DiaHistorico }) {
  const etapas: { rotulo: string; valor: Valor; anterior: Valor }[] = [
    { rotulo: 'Impressões', valor: dia.impressoes, anterior: null },
    { rotulo: 'Cliques no link', valor: dia.cliques, anterior: dia.impressoes },
    { rotulo: 'Views da página', valor: dia.lpv, anterior: dia.cliques },
    { rotulo: 'Leads pagos', valor: dia.leadsPagos, anterior: dia.lpv },
  ];
  const max = Math.max(1, dia.impressoes);
  return (
    <section aria-label="Funil do dia (captação)" className="mt-4">
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Funil do dia · só C2 e C3</h3>
      <ol className="space-y-2">
        {etapas.map((e, k) => (
          <li key={e.rotulo}>
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
              <span className="text-[var(--fg-2)]">{e.rotulo}</span>
              <span className="flex items-baseline gap-2">
                {k > 0 && <span className="text-xs text-[var(--fg-3)]"><Taxa taxa={taxa(e.valor, e.anterior)} /></span>}
                <Numero valor={e.valor} formato="int" animado={false} />
              </span>
            </div>
            <div className="mt-0.5 h-2 overflow-hidden rounded-full bg-[var(--surface-4)]" aria-hidden="true">
              {e.valor !== null && <div className="atm-historico-funil-bar h-full rounded-full bg-[var(--accent)]"
                style={{ width: `${Math.max(e.valor > 0 ? 1.5 : 0, (e.valor / max) * 100)}%`, animationDelay: `${k * 90}ms` }} />}
            </div>
          </li>
        ))}
      </ol>
      <p className="mt-2 text-[11px] text-[var(--fg-3)]">Cada taxa é a etapa sobre a anterior, no mesmo dia.</p>
    </section>
  );
}

function Grafico({ serie, ativo, onEscolher }: { serie: DiaHistorico[]; ativo: number; onEscolher: (k: number) => void }) {
  const W = 720; const H = 220; const topo = 12; const base = H - 24; const n = serie.length;
  const larg = W / n;
  const maxG = Math.max(1, ...serie.map((s) => s.gasto));
  const maxP = Math.max(1, ...serie.map((s) => Math.max(s.pessoasAcumuladas, s.metaAcumulada ?? 0)));
  const yP = (v: number) => base - (v / maxP) * (base - topo);
  const x = (k: number) => (k + 0.5) * larg;
  const linhaPessoas = serie.map((s, k) => `${x(k)},${yP(s.pessoasAcumuladas)}`).join(' ');
  const linhaMeta = serie.map((s, k) => (s.metaAcumulada === null ? null : `${x(k)},${yP(s.metaAcumulada)}`)).filter(Boolean).join(' ');
  const passos = Math.max(1, Math.ceil(n / 8));
  return (
    <figure className="min-w-0">
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img"
        aria-label={`Período de ${dataCurta(serie[0].dia)} a ${dataCurta(serie[n - 1].dia)}. No último dia: ${inteiro(serie[n - 1].pessoasAcumuladas)} pessoas acumuladas, meta ${formatar(serie[n - 1].metaAcumulada, 'int')}.`}>
        {serie.map((s, k) => {
          const h = (s.gasto / maxG) * (base - topo) * 0.6;
          const dica = `${dataCurta(s.dia)}: ${moeda(s.gasto)} · ${inteiro(s.pessoasAcumuladas)} acumuladas · meta ${formatar(s.metaAcumulada, 'int')}`;
          return (
            <g key={s.dia} role="button" tabIndex={0} aria-label={dica} aria-pressed={k === ativo} className="atm-historico-interativo cursor-pointer"
              onClick={() => onEscolher(k)} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onEscolher(k); } }}>
              <rect x={k * larg} y={topo} width={larg} height={base - topo} fill="transparent" />
              <rect className="atm-historico-barra" x={k * larg + larg * 0.18} width={larg * 0.64} y={base - h} height={h} rx="2"
                fill={k === ativo ? 'var(--accent)' : 'var(--surface-4)'}><title>{dica}</title></rect>
            </g>
          );
        })}
        <line x1="0" x2={W} y1={base} y2={base} stroke="var(--border)" />
        {linhaMeta && <polyline points={linhaMeta} fill="none" stroke="var(--fg-3)" strokeWidth="1.5" strokeDasharray="5 4" vectorEffect="non-scaling-stroke" />}
        <polyline points={linhaPessoas} fill="none" stroke="var(--cyan)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" />
        <line x1={x(ativo)} x2={x(ativo)} y1={topo} y2={base} stroke="var(--accent)" strokeWidth="1" vectorEffect="non-scaling-stroke" opacity="0.6" />
        {serie.map((s, k) => (k % passos === 0 || k === n - 1) && (
          <text key={`t-${s.dia}`} x={x(k)} y={H - 6} textAnchor="middle" className="fill-[var(--fg-3)] text-[13px]">{dataCurta(s.dia)}</text>
        ))}
      </svg>
      <figcaption className="mt-1 flex flex-wrap gap-3 text-xs text-[var(--fg-3)]">
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-2 w-3 rounded-sm bg-[var(--surface-4)]" />Investimento (máx. {moeda(maxG)})</span>
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-0.5 w-3 bg-[var(--cyan)]" />Pessoas acumuladas</span>
        <span className="inline-flex items-center gap-1"><span aria-hidden="true" className="h-0 w-3 border-t border-dashed border-[var(--fg-3)]" />Meta acumulada</span>
      </figcaption>
    </figure>
  );
}
