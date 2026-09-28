'use client';

// Gráfico de linha compacto do Faturamento (pedido do João, 27/09: "um representativo visual da nossa performance",
// sem ocupar muito espaço; depois: "mais embelezado, com marcações"). SVG próprio — o projeto não tem biblioteca de
// gráfico e não vale uma dependência para duas linhas. O traço é SVG esticado (preserveAspectRatio none +
// vector-effect non-scaling-stroke); texto, pontos e marcadores são HTML por cima, para não deformarem.
//
// Marcações: grade em 4 faixas com teto "redondo", linha tracejada da MÉDIA do bruto, marcador do PICO e do ÚLTIMO
// período (com valor), pontos em cada período quando há poucos, e a variação do último contra o anterior no cabeçalho.
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

const ALTURA = 190;

/** "R$ 1,2 mi" / "R$ 350 mil" — só para eixo e marcadores; valores exatos ficam na dica e na tabela. */
function compacto(v: number): string {
  if (v >= 1_000_000) return `R$ ${(v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`;
  if (v >= 1_000) return `R$ ${Math.round(v / 1_000).toLocaleString('pt-BR')} mil`;
  return `R$ ${Math.round(v)}`;
}

/** Teto "redondo" do eixo (1, 2, 2,5, 5 × 10^k) para a grade cair em números legíveis. */
export function tetoRedondo(max: number): number {
  if (max <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(max)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * exp >= max) return m * exp;
  return 10 * exp;
}

/** Camadas opcionais do painel de cruzamentos (FaturamentoDiario): período anterior, média móvel e vendas. */
export interface CamadasGrafico {
  /** Bruto do período anterior alinhado por posição (null = sem dado). */
  anterior?: (number | null)[] | null;
  /** Média móvel do bruto. */
  media?: number[] | null;
  /** Barras com a QUANTIDADE de vendas no pé do gráfico. */
  vendas?: boolean;
}

export function GraficoLinha({ pontos, titulo, camadas, selecionado, onSelecionar }: {
  pontos: PontoGrafico[]; titulo: string; camadas?: CamadasGrafico;
  /** Período clicado (índice) — o detalhe aparece no painel abaixo do gráfico. */
  selecionado?: number | null; onSelecionar?: (i: number | null) => void;
}) {
  const [foco, setFoco] = useState<number | null>(null);
  const calc = useMemo(() => {
    const maxBruto = Math.max(0, ...pontos.map((p) => p.bruto), ...(camadas?.anterior ?? []).map((v) => v ?? 0));
    const teto = tetoRedondo(maxBruto);
    const totalBruto = pontos.reduce((s, p) => s + p.bruto, 0);
    const totalLiquido = pontos.reduce((s, p) => s + p.liquido, 0);
    const media = pontos.length ? totalBruto / pontos.length : 0;
    const pico = pontos.reduce((best, p, i) => (p.bruto > pontos[best].bruto ? i : best), 0);
    const ult = pontos[pontos.length - 1];
    const ant = pontos[pontos.length - 2];
    const variacao = ult && ant && ant.bruto > 0 ? ((ult.bruto - ant.bruto) / ant.bruto) * 100 : null;
    return { teto, totalBruto, totalLiquido, media, pico, variacao };
  }, [pontos, camadas?.anterior]);
  if (pontos.length < 2) return null;

  const { teto, totalBruto, totalLiquido, media, pico, variacao } = calc;
  const ultimo = pontos.length - 1;
  const x = (i: number) => (i / ultimo) * 100;
  const y = (v: number) => 100 - (v / teto) * 100;
  const linha = (k: 'bruto' | 'liquido') => pontos.map((p, i) => `${x(i)},${y(p[k])}`).join(' ');
  // período anterior em trechos (quebra onde não há dado)
  const trechosAnterior: string[] = [];
  if (camadas?.anterior) {
    let atual: string[] = [];
    camadas.anterior.forEach((v, i) => {
      if (v == null) { if (atual.length > 1) trechosAnterior.push(atual.join(' ')); atual = []; return; }
      atual.push(`${x(i)},${y(v)}`);
    });
    if (atual.length > 1) trechosAnterior.push(atual.join(' '));
  }
  const maxVendas = Math.max(1, ...pontos.map((pt) => pt.vendas));
  const area = `0,100 ${linha('bruto')} 100,100`;
  const passo = Math.max(1, Math.ceil(ultimo / 5));
  // rótulo do meio colado no último (fica por cima dele em tela estreita) sai; o último sempre fica
  const marcas = pontos.map((_, i) => i).filter((i) => i === ultimo || (i % passo === 0 && (ultimo - i) / ultimo > 0.2));
  const comPontos = pontos.length <= 40;
  const p = foco != null ? pontos[foco] : null;
  const picoLabelDireita = x(pico) < 70;

  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-4">
      <div className="mb-3 flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
        <div>
          <div className="text-sm font-semibold text-[var(--fg)]">{titulo}</div>
          <div className="mt-0.5 flex flex-wrap items-center gap-x-3 text-[11px] text-[var(--fg-3)]">
            <span>média {compacto(media)} por período</span>
            {variacao != null && (
              <span className={variacao >= 0 ? 'text-[var(--green)]' : 'text-[var(--red)]'}>
                {variacao >= 0 ? '▲' : '▼'} {Math.abs(variacao).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}% no último vs. anterior
              </span>
            )}
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <span className="flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-1 text-xs text-[var(--fg-3)]">
            <span className="h-2 w-2 rounded-full bg-[var(--accent)]" aria-hidden />Bruto <strong className="tabular text-[var(--fg)]">{fmtBRL(totalBruto)}</strong>
          </span>
          <span className="flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-1 text-xs text-[var(--fg-3)]">
            <span className="h-2 w-2 rounded-full bg-[var(--green)]" aria-hidden />Líquido <strong className="tabular text-[var(--fg)]">{fmtBRL(totalLiquido)}</strong>
          </span>
        </div>
      </div>
      <div className="flex gap-2">
        {/* eixo Y: 4 faixas do teto redondo */}
        <div className="relative w-14 shrink-0 text-right text-[10px] tabular text-[var(--fg-4)]" style={{ height: ALTURA }} aria-hidden>
          {[1, 0.75, 0.5, 0.25, 0].map((f) => (
            <span key={f} className="absolute right-0 -translate-y-1/2" style={{ top: `${(1 - f) * 100}%` }}>{f === 0 ? 'R$ 0' : compacto(teto * f)}</span>
          ))}
        </div>
        <div className="relative min-w-0 flex-1">
          <div
            className="relative"
            style={{ height: ALTURA }}
            role="img"
            aria-label={`${titulo}: ${pontos.length} períodos, de ${pontos[0].rotulo} a ${pontos[ultimo].rotulo}. Bruto ${fmtBRL(totalBruto)}, líquido ${fmtBRL(totalLiquido)}. Pico em ${pontos[pico].rotulo}: ${fmtBRL(pontos[pico].bruto)}. Média ${fmtBRL(media)} por período. Os valores de cada período estão na tabela abaixo.`}
            onMouseLeave={() => setFoco(null)}
            onClick={() => onSelecionar?.(foco != null && foco === selecionado ? null : foco)}
            onMouseMove={(e) => {
              const r = e.currentTarget.getBoundingClientRect();
              const i = Math.round(((e.clientX - r.left) / r.width) * ultimo);
              setFoco(Math.min(ultimo, Math.max(0, i)));
            }}
          >
            <svg viewBox="0 0 100 100" preserveAspectRatio="none" className={`absolute inset-0 h-full w-full overflow-visible ${onSelecionar ? 'cursor-pointer' : ''}`}>
              <defs>
                <linearGradient id="fat-area" x1="0" x2="0" y1="0" y2="1">
                  <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.28" />
                  <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
                </linearGradient>
              </defs>
              {[0, 25, 50, 75, 100].map((g) => (
                <line key={g} x1="0" x2="100" y1={g} y2={g} stroke="var(--border)" strokeWidth="1"
                  strokeDasharray={g === 100 ? undefined : '2 4'} vectorEffect="non-scaling-stroke" />
              ))}
              <polygon points={area} fill="url(#fat-area)" />
              {/* média do bruto */}
              <line x1="0" x2="100" y1={y(media)} y2={y(media)} stroke="var(--fg-3)" strokeWidth="1" strokeDasharray="6 4" vectorEffect="non-scaling-stroke" opacity="0.7" />
              {camadas?.vendas && pontos.map((pt, i) => (
                <rect key={`v${i}`} x={x(i) - 40 / pontos.length / 2} width={Math.max(0.3, 40 / pontos.length)}
                  y={100 - (pt.vendas / maxVendas) * 22} height={(pt.vendas / maxVendas) * 22}
                  fill="var(--fg-3)" opacity="0.25" />
              ))}
              {trechosAnterior.map((t, i) => (
                <polyline key={`a${i}`} points={t} fill="none" stroke="var(--fg-3)" strokeWidth="1.5" strokeDasharray="4 4"
                  vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
              ))}
              {camadas?.media && (
                <polyline points={camadas.media.map((v, i) => `${x(i)},${y(v)}`).join(' ')} fill="none" stroke="var(--cyan)"
                  strokeWidth="1.75" vectorEffect="non-scaling-stroke" strokeLinejoin="round" opacity="0.9" />
              )}
              <polyline points={linha('liquido')} fill="none" stroke="var(--green)" strokeWidth="1.75" vectorEffect="non-scaling-stroke" strokeLinejoin="round" strokeLinecap="round" />
              <polyline points={linha('bruto')} fill="none" stroke="var(--accent)" strokeWidth="2.5" vectorEffect="non-scaling-stroke" strokeLinejoin="round" strokeLinecap="round" />
              {selecionado != null && selecionado < pontos.length && (
                <line x1={x(selecionado)} x2={x(selecionado)} y1="0" y2="100" stroke="var(--accent)" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
              )}
              {foco != null && (
                <line x1={x(foco)} x2={x(foco)} y1="0" y2="100" stroke="var(--fg-4)" strokeWidth="1" strokeDasharray="3 3" vectorEffect="non-scaling-stroke" />
              )}
            </svg>

            {/* rótulo da média, na ponta esquerda da linha tracejada */}
            <span className="pointer-events-none absolute left-1 -translate-y-full pb-0.5 text-[9px] font-medium uppercase tracking-wide text-[var(--fg-3)]"
              style={{ top: `${y(media)}%` }} aria-hidden>média</span>

            {/* pontos de cada período (poucos períodos) */}
            {comPontos && pontos.map((pt, i) => (
              <span key={i} className="pointer-events-none absolute h-1.5 w-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full border border-[var(--accent)] bg-[var(--surface-1)]"
                style={{ left: `${x(i)}%`, top: `${y(pt.bruto)}%` }} aria-hidden />
            ))}

            {/* pico */}
            <span className="pointer-events-none absolute h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[var(--surface-1)] bg-[var(--accent)]"
              style={{ left: `${x(pico)}%`, top: `${y(pontos[pico].bruto)}%` }} aria-hidden />
            <span className="pointer-events-none absolute whitespace-nowrap rounded-[var(--r-sm)] border border-[var(--accent-border)] bg-[var(--accent-subtle)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--accent)]"
              style={{ top: `calc(${y(pontos[pico].bruto)}% + 2px)`, ...(picoLabelDireita ? { left: `calc(${x(pico)}% + 9px)` } : { right: `calc(${100 - x(pico)}% + 9px)` }) }}
              aria-hidden>
              pico {compacto(pontos[pico].bruto)} · {pontos[pico].curto}
            </span>

            {/* último período */}
            {pico !== ultimo && (
              <>
                <span className="pointer-events-none absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[var(--surface-1)] bg-[var(--accent)]"
                  style={{ left: '100%', top: `${y(pontos[ultimo].bruto)}%` }} aria-hidden />
                <span className="pointer-events-none absolute right-2 -translate-y-full pb-1 text-[10px] font-semibold tabular text-[var(--fg)]"
                  style={{ top: `${y(pontos[ultimo].bruto)}%` }} aria-hidden>
                  {compacto(pontos[ultimo].bruto)}
                </span>
              </>
            )}

            {p && foco != null && (
              <>
                <span className="pointer-events-none absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--accent)] ring-2 ring-[var(--surface-1)]"
                  style={{ left: `${x(foco)}%`, top: `${y(p.bruto)}%` }} aria-hidden />
                <span className="pointer-events-none absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[var(--green)] ring-2 ring-[var(--surface-1)]"
                  style={{ left: `${x(foco)}%`, top: `${y(p.liquido)}%` }} aria-hidden />
                <div
                  className="pointer-events-none absolute bottom-2 z-10 w-max max-w-[220px] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1.5 text-xs shadow-lg"
                  style={x(foco) > 60 ? { right: `${100 - x(foco) + 1}%` } : { left: `${x(foco) + 1}%` }}
                >
                  <div className="font-semibold text-[var(--fg)]">{p.rotulo}</div>
                  <div className="tabular text-[var(--fg-2)]">Bruto {fmtBRL(p.bruto)}</div>
                  <div className="tabular text-[var(--green)]">Líquido {fmtBRL(p.liquido)}</div>
                  <div className="tabular text-[var(--fg-3)]">{p.vendas} venda{p.vendas === 1 ? '' : 's'}</div>
                  {camadas?.anterior && camadas.anterior[foco] != null && (
                    <div className="tabular text-[var(--fg-3)]">período anterior {fmtBRL(camadas.anterior[foco] as number)}</div>
                  )}
                  {onSelecionar && <div className="mt-0.5 text-[10px] text-[var(--fg-4)]">clique para fixar</div>}
                </div>
              </>
            )}
          </div>
          <div className="relative mt-1.5 h-4 text-[10px] tabular text-[var(--fg-4)]" aria-hidden>
            {marcas.map((i) => (
              <span key={i} className="absolute whitespace-nowrap"
                style={i === 0 ? { left: 0 } : i === ultimo ? { right: 0 } : { left: `${x(i)}%`, transform: 'translateX(-50%)' }}>
                {pontos[i].curto}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
