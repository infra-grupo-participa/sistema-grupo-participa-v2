'use client';

// Peças visuais da performance da equipe: sparkline SVG, comparação (Δ), indicador com (i) e selo.
// Só tokens do tema; âmbar fica fora (é seleção/ação).
import { Badge } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import type { MetricaKey } from '../../domain/types';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { formatarValor } from '../inicio/metricas-painel';
import { rotuloDia, type Selo } from './performance';

/** Linha fina com área, para a tendência. aria-label traz os valores. */
export function Sparkline({ pontos, rotulo, altura = 32 }: { pontos: { dia: string; valor: number }[]; rotulo: string; altura?: number }) {
  const largura = 120;
  const max = Math.max(0, ...pontos.map((p) => p.valor));
  const n = pontos.length;
  const x = (i: number) => (n <= 1 ? largura / 2 : (i / (n - 1)) * (largura - 4) + 2);
  const y = (v: number) => (max ? altura - 3 - (v / max) * (altura - 6) : altura - 3);
  const linha = pontos.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.valor).toFixed(1)}`).join(' ');
  const area = n ? `${linha} L${x(n - 1).toFixed(1)},${altura} L${x(0).toFixed(1)},${altura} Z` : '';
  const desc = pontos.map((p) => `${rotuloDia(p.dia)}: ${fmtBRL(p.valor)}`).join('; ');
  return (
    <svg viewBox={`0 0 ${largura} ${altura}`} preserveAspectRatio="none" className="block w-full" style={{ height: altura }} role="img" aria-label={`${rotulo}. ${desc}`}>
      {max > 0 ? (
        <>
          <path d={area} fill="var(--info)" opacity={0.12} />
          <path d={linha} fill="none" stroke="var(--info)" strokeWidth={1.5} vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
        </>
      ) : (
        <line x1={2} x2={largura - 2} y1={altura - 3} y2={altura - 3} stroke="var(--border-strong)" strokeWidth={1} strokeDasharray="3 3" vectorEffect="non-scaling-stroke" />
      )}
    </svg>
  );
}

/**
 * Comparação curta: "+12% vs anterior". `menosEMelhor` inverte a cor. `pp` mostra pontos percentuais (taxas).
 * Cor só quando a diferença existe; texto sempre diz o sentido.
 */
export function Delta({ valor, rotulo, menosEMelhor = false, pp = false }: { valor: number | null; rotulo: string; menosEMelhor?: boolean; pp?: boolean }) {
  if (valor == null) return <span className="text-[11px] text-[var(--fg-4)]">sem base {rotulo}</span>;
  const bom = valor === 0 ? null : (valor > 0) !== menosEMelhor;
  const cor = bom == null ? 'text-[var(--fg-3)]' : bom ? 'text-[var(--green)]' : 'text-[var(--red)]';
  const sinal = valor > 0 ? '+' : valor < 0 ? '−' : '';
  return (
    <span className={`text-[11px] tabular ${cor}`}>
      {sinal}{Math.abs(valor)}{pp ? ' pp' : '%'} <span className="text-[var(--fg-3)]">{rotulo}</span>
    </span>
  );
}

/** Indicador compacto: rótulo + (i), valor e uma linha de comparação. */
export function Indicador({ rotulo, metrica, info, valor, sub, alerta = false }: {
  rotulo: string; metrica?: MetricaKey; info?: TextoIndicador; valor: React.ReactNode; sub?: React.ReactNode; alerta?: boolean;
}) {
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-0.5 text-[11px] text-[var(--fg-3)]">
        <span className="truncate">{rotulo}</span>
        <InfoIndicador metrica={metrica} texto={info} />
      </dt>
      <dd className={`text-sm font-semibold tabular ${alerta ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>
        {valor}
        {alerta && <span className="sr-only"> (fora da meta)</span>}
      </dd>
      {sub && <dd className="truncate">{sub}</dd>}
    </div>
  );
}

/** Selo de destaque ou alerta: cor só no ponto, o motivo no title. */
export function SeloBadge({ selo }: { selo: Selo }) {
  return (
    <span title={selo.motivo}>
      <Badge dot tone={selo.tipo === 'destaque' ? 'success' : selo.k === 'fila_parada' || selo.k === 'falha_processo' ? 'danger' : 'warning'}>
        {selo.rotulo}
        <span className="sr-only">: {selo.motivo}</span>
      </Badge>
    </span>
  );
}

/** Minutos legíveis (mesmo formato do painel). */
export const fmtMin = (v: number | null) => formatarValor(v, 'minutos');

/** Número com uma casa no máximo, pt-BR. */
export const fmtNum = (v: number | null, casas = 1) => (v == null ? '—' : v.toLocaleString('pt-BR', { maximumFractionDigits: casas }));

/** Percentual inteiro. */
export const fmtPct = (v: number | null) => (v == null ? '—' : `${Math.round(v)}%`);
