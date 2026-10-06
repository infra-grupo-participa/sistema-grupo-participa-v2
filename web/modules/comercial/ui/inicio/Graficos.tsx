'use client';

// Visuais dos widgets do painel em SVG puro, só com tokens do tema (nada de lib de gráfico, nada de hex).
// Âmbar fica fora: no Comercial ele é só seleção/ação. Cada gráfico tem aria-label com os valores.
import { Icon } from '@/shared/ui/icons';
import type { MetricaKey, VisualWidget } from '../../domain/types';
import { formatarValor, MENOS_E_MELHOR, variacao, type PontoSerie, type SerieWidget } from './metricas-painel';

/** Paleta categórica (pizza): tokens do tema, em ordem de contraste. */
const PALETA = ['var(--info)', 'var(--cyan)', 'var(--purple)', 'var(--green)', 'var(--yellow)', 'var(--fg-3)'];
const MAX_FATIAS = 5;
const TOP_N = 5;

const resumo = (pontos: PontoSerie[], s: SerieWidget) => pontos.map((p) => `${p.rotulo}: ${formatarValor(p.valor, s.formato)}`).join('; ');

/** Desenha a série no visual escolhido. */
export function VisualWidgetSvg({ visual, serie, metrica }: { visual: VisualWidget; serie: SerieWidget; metrica: MetricaKey }) {
  if (visual === 'numero') return <NumeroGrande serie={serie} metrica={metrica} />;
  if (!serie.pontos.length || serie.pontos.every((p) => p.valor === 0)) return <SemDados />;
  if (visual === 'linha') return <Linha serie={serie} />;
  if (visual === 'pizza') return <Rosca serie={serie} />;
  if (visual === 'lista') return <ListaTop serie={serie} />;
  return serie.pontos.length > 0 && /^\d{4}-\d{2}-\d{2}$/.test(serie.pontos[0].chave) ? <Colunas serie={serie} /> : <BarrasHorizontais serie={serie} />;
}

function SemDados() {
  return (
    <div className="grid place-items-center h-[140px] text-center">
      <div>
        <Icon name="chart" size={20} className="mx-auto text-[var(--fg-4)]" />
        <p className="mt-1.5 text-xs text-[var(--fg-3)]">Sem dado no período.</p>
      </div>
    </div>
  );
}

function NumeroGrande({ serie, metrica }: { serie: SerieWidget; metrica: MetricaKey }) {
  const v = variacao(serie);
  const ruim = v != null && v !== 0 && (v > 0) === MENOS_E_MELHOR.has(metrica);
  return (
    <div className="py-1">
      <div className="text-3xl font-bold tabular leading-tight text-[var(--fg)] truncate">{formatarValor(serie.valor, serie.formato)}</div>
      <div className="mt-1 text-xs text-[var(--fg-3)]">
        {serie.fotografia ? (
          'Agora'
        ) : v == null ? (
          serie.anterior != null ? `Anterior: ${formatarValor(serie.anterior, serie.formato)}` : 'Sem base para comparar'
        ) : (
          <span className="inline-flex items-center gap-1">
            <span className={`inline-flex items-center gap-0.5 font-semibold tabular ${v === 0 ? 'text-[var(--fg-2)]' : ruim ? 'text-[var(--red)]' : 'text-[var(--green)]'}`}>
              {v !== 0 && <Icon name={v > 0 ? 'arrow-up' : 'arrow-down'} size={12} />}
              {v > 0 ? '+' : ''}{v}%
            </span>
            <span>vs período anterior ({formatarValor(serie.anterior, serie.formato)})</span>
          </span>
        )}
      </div>
    </div>
  );
}

/** Barras horizontais: rótulo legível sempre (vendedor, produto, motivo…). */
function BarrasHorizontais({ serie }: { serie: SerieWidget }) {
  const pontos = serie.pontos.slice(0, 8);
  const max = Math.max(...pontos.map((p) => p.valor), 1);
  return (
    <ul className="space-y-2" aria-label={resumo(pontos, serie)}>
      {pontos.map((p) => (
        <li key={p.chave} className="min-w-0">
          <div className="flex items-baseline justify-between gap-2 text-xs">
            <span className="truncate text-[var(--fg-2)]">{p.rotulo}</span>
            <span className="shrink-0 tabular font-semibold text-[var(--fg)]">{formatarValor(p.valor, serie.formato)}</span>
          </div>
          <svg className="mt-1 block w-full" height="6" viewBox="0 0 100 6" preserveAspectRatio="none" aria-hidden>
            <rect x="0" y="0" width="100" height="6" rx="3" fill="var(--surface-3)" />
            <rect x="0" y="0" width={Math.max((p.valor / max) * 100, p.valor ? 1.5 : 0)} height="6" rx="3" fill="var(--info)" />
          </svg>
        </li>
      ))}
    </ul>
  );
}

/** Colunas por dia (série temporal curta). */
function Colunas({ serie }: { serie: SerieWidget }) {
  const pontos = serie.pontos;
  const max = Math.max(...pontos.map((p) => p.valor), 1);
  const W = 300, Hc = 110, gap = pontos.length > 15 ? 1.5 : 4;
  const larg = (W - gap * (pontos.length - 1)) / pontos.length;
  return (
    <figure className="m-0">
      <svg viewBox={`0 0 ${W} ${Hc}`} className="block w-full h-[120px]" preserveAspectRatio="none" role="img" aria-label={resumo(pontos, serie)}>
        <line x1="0" y1={Hc - 0.5} x2={W} y2={Hc - 0.5} stroke="var(--border)" strokeWidth="1" vectorEffect="non-scaling-stroke" />
        {pontos.map((p, i) => {
          const h = (p.valor / max) * (Hc - 6);
          return (
            <rect key={p.chave} x={i * (larg + gap)} y={Hc - h} width={larg} height={Math.max(h, 0)} rx="1.5" fill="var(--info)">
              <title>{`${p.rotulo}: ${formatarValor(p.valor, serie.formato)}`}</title>
            </rect>
          );
        })}
      </svg>
      <EixoDias pontos={pontos} max={max} formato={serie.formato} />
    </figure>
  );
}

/** Linha por dia, com área suave. */
function Linha({ serie }: { serie: SerieWidget }) {
  const pontos = serie.pontos;
  const max = Math.max(...pontos.map((p) => p.valor), 1);
  const W = 300, Hc = 110;
  const x = (i: number) => (pontos.length === 1 ? W / 2 : (i / (pontos.length - 1)) * W);
  const y = (v: number) => Hc - 4 - (v / max) * (Hc - 10);
  const caminho = pontos.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.valor).toFixed(1)}`).join(' ');
  const area = `${caminho} L${x(pontos.length - 1).toFixed(1)},${Hc} L${x(0).toFixed(1)},${Hc} Z`;
  return (
    <figure className="m-0">
      <svg viewBox={`0 0 ${W} ${Hc}`} className="block w-full h-[120px]" preserveAspectRatio="none" role="img" aria-label={resumo(pontos, serie)}>
        <line x1="0" y1={Hc - 0.5} x2={W} y2={Hc - 0.5} stroke="var(--border)" strokeWidth="1" vectorEffect="non-scaling-stroke" />
        <path d={area} fill="var(--info)" opacity="0.12" />
        <path d={caminho} fill="none" stroke="var(--info)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
        {pontos.map((p, i) => (
          <rect key={p.chave} x={x(i) - W / pontos.length / 2} y="0" width={W / pontos.length} height={Hc} fill="transparent">
            <title>{`${p.rotulo}: ${formatarValor(p.valor, serie.formato)}`}</title>
          </rect>
        ))}
      </svg>
      <EixoDias pontos={pontos} max={max} formato={serie.formato} />
    </figure>
  );
}

function EixoDias({ pontos, max, formato }: { pontos: PontoSerie[]; max: number; formato: SerieWidget['formato'] }) {
  return (
    <figcaption className="mt-1 flex items-center justify-between gap-2 text-[11px] tabular text-[var(--fg-3)]">
      <span>{pontos[0]?.rotulo}</span>
      <span>máx. {formatarValor(max, formato)}</span>
      <span>{pontos.at(-1)?.rotulo}</span>
    </figcaption>
  );
}

/** Rosca com legenda; passou de 5 fatias, o resto vira "Outros". */
function Rosca({ serie }: { serie: SerieWidget }) {
  const ordenados = [...serie.pontos].filter((p) => p.valor > 0).sort((a, b) => b.valor - a.valor);
  const fatias: PontoSerie[] = ordenados.length > MAX_FATIAS
    ? [...ordenados.slice(0, MAX_FATIAS), { chave: 'outros', rotulo: 'Outros', valor: ordenados.slice(MAX_FATIAS).reduce((s, p) => s + p.valor, 0) }]
    : ordenados;
  const total = fatias.reduce((s, p) => s + p.valor, 0) || 1;
  const R = 15.9155; // circunferência = 100
  // Início de cada fatia (soma das anteriores), em % da volta.
  const pcts = fatias.map((p) => (p.valor / total) * 100);
  const inicios = pcts.map((_, i) => pcts.slice(0, i).reduce((s, v) => s + v, 0));
  return (
    <div className="flex items-center gap-4 min-w-0">
      <svg viewBox="0 0 42 42" className="w-[112px] h-[112px] shrink-0 -rotate-90" role="img" aria-label={resumo(fatias, serie)}>
        <circle cx="21" cy="21" r={R} fill="none" stroke="var(--surface-3)" strokeWidth="6" />
        {fatias.map((p, i) => (
          <circle key={p.chave} cx="21" cy="21" r={R} fill="none" stroke={PALETA[i % PALETA.length]} strokeWidth="6"
            strokeDasharray={`${pcts[i]} ${100 - pcts[i]}`} strokeDashoffset={-inicios[i]}>
            <title>{`${p.rotulo}: ${formatarValor(p.valor, serie.formato)} (${Math.round(pcts[i])}%)`}</title>
          </circle>
        ))}
      </svg>
      <ul className="min-w-0 flex-1 space-y-1">
        {fatias.map((p, i) => (
          <li key={p.chave} className="flex items-center gap-2 text-xs min-w-0">
            <svg width="8" height="8" viewBox="0 0 8 8" className="shrink-0" aria-hidden><circle cx="4" cy="4" r="4" fill={PALETA[i % PALETA.length]} /></svg>
            <span className="truncate text-[var(--fg-2)]">{p.rotulo}</span>
            <span className="ml-auto shrink-0 tabular text-[var(--fg)]">{formatarValor(p.valor, serie.formato)}</span>
            <span className="w-9 shrink-0 text-right tabular text-[var(--fg-3)]">{Math.round((p.valor / total) * 100)}%</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Top-N em lista numerada. */
function ListaTop({ serie }: { serie: SerieWidget }) {
  const pontos = serie.pontos.slice(0, TOP_N);
  return (
    <ol className="divide-y divide-[var(--border-faint)]" aria-label={resumo(pontos, serie)}>
      {pontos.map((p, i) => (
        <li key={p.chave} className="flex items-center gap-3 py-1.5 text-sm min-w-0">
          <span className="w-4 shrink-0 text-right text-xs font-semibold tabular text-[var(--fg-3)]">{i + 1}</span>
          <span className="truncate text-[var(--fg-2)]">{p.rotulo}</span>
          <span className="ml-auto shrink-0 tabular font-semibold text-[var(--fg)]">{formatarValor(p.valor, serie.formato)}</span>
        </li>
      ))}
      {serie.pontos.length > TOP_N && (
        <li className="pt-1.5 text-[11px] text-[var(--fg-3)]">+{serie.pontos.length - TOP_N} fora do top {TOP_N}</li>
      )}
    </ol>
  );
}
