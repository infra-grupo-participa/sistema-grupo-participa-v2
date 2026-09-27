'use client';

// Gráfico de linha compacto do Faturamento (pedido do João, 27/09: "um representativo visual da nossa performance",
// sem ocupar muito espaço). SVG próprio — o projeto não tem biblioteca de gráfico e não vale uma dependência
// para duas linhas. O traço é SVG esticado (preserveAspectRatio none + vector-effect non-scaling-stroke);
// texto e ponto de destaque são HTML por cima, para não deformarem com a largura.
import { useMemo, useState } from 'react';
import { fmtBRL } from '@/shared/ui/format';

export interface PontoGrafico {
  rotulo: string;
  /** Rótulo curto do eixo X. */
  curto: string;
  bruto: number;
  liquido: number;
  vendas: number;
}

const ALTURA = 170;

/** "R$ 1,2 mi" / "R$ 350 mil" — só para o eixo; valores exatos ficam na dica e na tabela. */
function compacto(v: number): string {
  if (v >= 1_000_000) return `R$ ${(v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`;
  if (v >= 1_000) return `R$ ${Math.round(v / 1_000).toLocaleString('pt-BR')} mil`;
  return `R$ ${Math.round(v)}`;
}

export function GraficoLinha({ pontos, titulo }: { pontos: PontoGrafico[]; titulo: string }) {
  const [foco, setFoco] = useState<number | null>(null);
  const max = useMemo(() => Math.max(1, ...pontos.map((p) => p.bruto)), [pontos]);
  if (pontos.length < 2) return null;

  const x = (i: number) => (i / (pontos.length - 1)) * 100;
  const y = (v: number) => 100 - (v / max) * 100;
  const linha = (k: 'bruto' | 'liquido') => pontos.map((p, i) => `${x(i)},${y(p[k])}`).join(' ');
  const area = `0,100 ${linha('bruto')} 100,100`;
  // até 6 rótulos no eixo X, sempre com o primeiro e o último
  const passo = Math.max(1, Math.ceil((pontos.length - 1) / 5));
  const ultimo = pontos.length - 1;
  // rótulo do meio colado no último (fica por cima dele em tela estreita) sai; o último sempre fica
  const marcas = pontos.map((_, i) => i).filter((i) => i === ultimo || (i % passo === 0 && (ultimo - i) / ultimo > 0.2));
  const totalBruto = pontos.reduce((s, p) => s + p.bruto, 0);
  const totalLiquido = pontos.reduce((s, p) => s + p.liquido, 0);
  const p = foco != null ? pontos[foco] : null;

  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-4">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <div className="text-sm font-semibold text-[var(--fg)]">{titulo}</div>
        <div className="flex flex-wrap items-center gap-x-4 text-xs text-[var(--fg-3)]">
          <span className="flex items-center gap-1.5"><span className="h-0.5 w-4 rounded bg-[var(--accent)]" aria-hidden />Bruto <strong className="tabular text-[var(--fg)]">{fmtBRL(totalBruto)}</strong></span>
          <span className="flex items-center gap-1.5"><span className="h-0.5 w-4 rounded bg-[var(--green)]" aria-hidden />Líquido <strong className="tabular text-[var(--fg)]">{fmtBRL(totalLiquido)}</strong></span>
        </div>
      </div>
      <div className="flex gap-2">
        {/* eixo Y: topo, meio e zero */}
        <div className="flex w-16 shrink-0 flex-col justify-between text-right text-[10px] tabular text-[var(--fg-4)]" style={{ height: ALTURA }} aria-hidden>
          <span>{compacto(max)}</span><span>{compacto(max / 2)}</span><span>R$ 0</span>
        </div>
        <div className="relative min-w-0 flex-1">
          <div
            className="relative"
            style={{ height: ALTURA }}
            role="img"
            aria-label={`${titulo}: ${pontos.length} períodos, de ${pontos[0].rotulo} a ${pontos[pontos.length - 1].rotulo}. Bruto ${fmtBRL(totalBruto)}, líquido ${fmtBRL(totalLiquido)}. Maior bruto: ${fmtBRL(max)}. Os valores de cada período estão na tabela abaixo.`}
            onMouseLeave={() => setFoco(null)}
            onMouseMove={(e) => {
              const r = e.currentTarget.getBoundingClientRect();
              const i = Math.round(((e.clientX - r.left) / r.width) * (pontos.length - 1));
              setFoco(Math.min(pontos.length - 1, Math.max(0, i)));
            }}
          >
            <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="absolute inset-0 h-full w-full overflow-visible">
              {[0, 50, 100].map((g) => (
                <line key={g} x1="0" x2="100" y1={g} y2={g} stroke="var(--border)" strokeWidth="1" vectorEffect="non-scaling-stroke" />
              ))}
              <polygon points={area} fill="var(--accent)" opacity="0.08" />
              <polyline points={linha('bruto')} fill="none" stroke="var(--accent)" strokeWidth="2" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
              <polyline points={linha('liquido')} fill="none" stroke="var(--green)" strokeWidth="2" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
              {foco != null && (
                <line x1={x(foco)} x2={x(foco)} y1="0" y2="100" stroke="var(--fg-4)" strokeWidth="1" strokeDasharray="3 3" vectorEffect="non-scaling-stroke" />
              )}
            </svg>
            {p && foco != null && (
              <>
                <span className="pointer-events-none absolute h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--accent)]"
                  style={{ left: `${x(foco)}%`, top: `${y(p.bruto)}%` }} aria-hidden />
                <span className="pointer-events-none absolute h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--green)]"
                  style={{ left: `${x(foco)}%`, top: `${y(p.liquido)}%` }} aria-hidden />
                <div
                  className="pointer-events-none absolute top-1 z-10 w-max max-w-[220px] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-xs shadow-lg"
                  style={x(foco) > 60 ? { right: `${100 - x(foco) + 1}%` } : { left: `${x(foco) + 1}%` }}
                >
                  <div className="font-semibold text-[var(--fg)]">{p.rotulo}</div>
                  <div className="tabular text-[var(--fg-2)]">Bruto {fmtBRL(p.bruto)}</div>
                  <div className="tabular text-[var(--green)]">Líquido {fmtBRL(p.liquido)}</div>
                  <div className="tabular text-[var(--fg-3)]">{p.vendas} venda{p.vendas === 1 ? '' : 's'}</div>
                </div>
              </>
            )}
          </div>
          <div className="relative mt-1 h-4 text-[10px] tabular text-[var(--fg-4)]" aria-hidden>
            {marcas.map((i) => (
              <span key={i} className="absolute whitespace-nowrap"
                style={i === 0 ? { left: 0 } : i === pontos.length - 1 ? { right: 0 } : { left: `${x(i)}%`, transform: 'translateX(-50%)' }}>
                {pontos[i].curto}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
