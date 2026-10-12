'use client';

// Gráficos do dashboard da Black, só SVG e tokens (sem biblioteca nova):
// - BarrasFase: uma barra grossa por fase do Caio, cada fase com uma cor própria (sem vermelho), marca do previsto,
//   entrada animada e dica com o valor ao passar o mouse ou focar com o teclado.
// - GraficoLinha: série diária (eixo X = dia, eixo Y = métrica do dia), linha desenhada na entrada, cursor que
//   mostra o valor do dia. Dia sem dado quebra a linha (nunca vira zero).
// Tudo respeita prefers-reduced-motion.
import { useEffect, useId, useRef, useState } from 'react';
import type { FormatoMetrica } from '../domain/jornada';
import type { Fase, Valor } from '../domain/tipos';
import { formatar, usePrefereMenosMovimento } from './pecas';

/** Cor de cada fase: distintas entre si, sem vermelho (vermelho é só farol). */
export const COR_FASE: Record<Fase, string> = {
  antecipacao: 'var(--info)',
  distribuicao: 'var(--nivel-ouro)',
  captacao: 'var(--purple)',
  aquecimento: 'var(--cyan)',
  remarketing: 'var(--nivel-diamante)',
  live_carrinho: 'var(--green)',
};

export interface ItemFase { fase: Fase; rotulo: string; valor: Valor; previsto?: Valor }

/** Barras por fase. `previsto` (opcional) vira uma marca vertical na barra e entra na dica. */
export function BarrasFase({ itens, formato }: { itens: ItemFase[]; formato: FormatoMetrica }) {
  const [foco, setFoco] = useState<Fase | null>(null);
  const escala = Math.max(0, ...itens.flatMap((i) => [i.valor ?? 0, i.previsto ?? 0]));
  const pctDe = (v: Valor) => (escala > 0 && v !== null && v > 0 ? Math.min(100, (v / escala) * 100) : 0);
  return (
    <ul className="space-y-6">
      {itens.map((it, i) => {
        const cor = COR_FASE[it.fase];
        const acima = it.previsto != null && it.valor !== null && it.valor > it.previsto;
        const dica = `${it.rotulo}: ${formatar(it.valor, formato)}${it.previsto !== undefined ? ` de ${formatar(it.previsto, formato)} previsto` : ''}${acima ? ' (acima do previsto)' : ''}`;
        return (
          <li key={it.fase}>
            <div className="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5 text-sm">
              <span className="inline-flex items-center gap-2 font-medium text-[var(--fg)]">
                <span aria-hidden="true" className="inline-block h-3 w-3 rounded-[var(--r-sm)]" style={{ background: cor }} />
                {it.rotulo}
              </span>
              <span className="tabular text-[var(--fg)]">
                {formatar(it.valor, formato)}
                {it.previsto !== undefined && <span className="text-[var(--fg-3)]"> de {formatar(it.previsto, formato)}</span>}
                {acima && <span className="ml-2 text-xs text-[var(--fg-2)]">acima do previsto</span>}
              </span>
            </div>
            <div tabIndex={0} role="img" aria-label={dica} title={dica}
              onMouseEnter={() => setFoco(it.fase)} onMouseLeave={() => setFoco(null)} onFocus={() => setFoco(it.fase)} onBlur={() => setFoco(null)}
              className="relative h-4 cursor-default rounded-full bg-[var(--surface-4)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]">
              <div className="atm-historico-barra h-full rounded-full transition-[filter] duration-150"
                style={{ width: `${pctDe(it.valor)}%`, background: cor, animationDelay: `${i * 70}ms`, filter: foco === it.fase ? 'brightness(1.2)' : undefined }} />
              {it.previsto != null && it.previsto > 0 && (
                <span aria-hidden="true" className="absolute -top-1 -bottom-1 w-0.5 rounded-full bg-[var(--fg)]" style={{ left: `calc(${pctDe(it.previsto)}% - 1px)` }} />
              )}
              {foco === it.fase && (
                <span role="tooltip" className="gp-fade-in pointer-events-none absolute bottom-full z-10 mb-2 -translate-x-1/2 whitespace-nowrap rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-3)] px-2.5 py-1.5 text-xs text-[var(--fg)] shadow-[var(--shadow-md)]"
                  style={{ left: `${Math.min(85, Math.max(15, pctDe(it.valor)))}%` }}>
                  <strong className="tabular">{formatar(it.valor, formato)}</strong>
                  {it.previsto !== undefined && <span className="text-[var(--fg-2)]"> de {formatar(it.previsto, formato)} previsto</span>}
                </span>
              )}
            </div>
          </li>
        );
      })}
      {itens.some((i) => i.previsto !== undefined) && (
        <li className="flex items-center gap-2 text-xs text-[var(--fg-3)]"><span aria-hidden="true" className="inline-block h-3 w-0.5 rounded-full bg-[var(--fg)]" /> marca do previsto da fase</li>
      )}
    </ul>
  );
}

const COMPACTO = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 });
function eixo(v: number, formato: FormatoMetrica): string {
  if (formato === 'pct') return `${(v * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
  if (formato === 'brl') return `R$ ${Math.abs(v) >= 1000 ? COMPACTO.format(v) : v.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}`;
  return COMPACTO.format(v);
}
function passoBonito(max: number): number {
  if (max <= 0) return 1;
  const bruto = max / 4; const p = 10 ** Math.floor(Math.log10(bruto)); const n = bruto / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
}

export interface PontoLinha { chave: string; rotulo: string; valor: Valor }

/** Gráfico de linha da série diária, interativo (cursor mostra o valor do dia). */
export function GraficoLinha({ pontos, formato, rotuloSerie }: { pontos: PontoLinha[]; formato: FormatoMetrica; rotuloSerie: string }) {
  const caixa = useRef<HTMLDivElement>(null);
  const linha = useRef<SVGPathElement>(null);
  const grad = `grad-${useId().replace(/:/g, '')}`;
  const menos = usePrefereMenosMovimento();
  const [largura, setLargura] = useState(640);
  const [ativo, setAtivo] = useState<number | null>(null);

  useEffect(() => {
    const el = caixa.current; if (!el) return;
    const ro = new ResizeObserver(([e]) => setLargura(Math.max(280, Math.round(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const A = 240; const esq = 56; const dir = 16; const topo = 16; const base = 28;
  const w = largura - esq - dir; const h = A - topo - base;
  const valores = pontos.map((p) => p.valor).filter((v): v is number => v !== null && Number.isFinite(v));
  const passo = passoBonito(Math.max(0, ...valores));
  const teto = Math.max(passo, Math.ceil(Math.max(0, ...valores) / passo) * passo);
  const x = (i: number) => esq + (pontos.length <= 1 ? w / 2 : (i / (pontos.length - 1)) * w);
  const y = (v: number) => topo + h - (v / teto) * h;

  // Segmentos contínuos (dia sem dado quebra a linha).
  let d = ''; let area = ''; let seg: number[] = [];
  const fechar = () => {
    if (seg.length === 0) return;
    d += seg.map((i, k) => `${k === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(pontos[i].valor as number).toFixed(1)}`).join(' ') + ' ';
    area += `M${x(seg[0]).toFixed(1)},${(topo + h).toFixed(1)} ` + seg.map((i) => `L${x(i).toFixed(1)},${y(pontos[i].valor as number).toFixed(1)}`).join(' ') + ` L${x(seg[seg.length - 1]).toFixed(1)},${(topo + h).toFixed(1)} Z `;
    seg = [];
  };
  pontos.forEach((p, i) => { if (p.valor === null || !Number.isFinite(p.valor)) fechar(); else seg.push(i); });
  fechar();

  useEffect(() => {
    const el = linha.current; if (!el || menos || typeof el.animate !== 'function') return;
    const anim = el.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 900, easing: 'cubic-bezier(.2,.8,.2,1)' });
    return () => anim.cancel();
  }, [menos, pontos.length, rotuloSerie]);

  const ticks = Array.from({ length: Math.round(teto / passo) + 1 }, (_, i) => i * passo);
  const cadaX = Math.max(1, Math.ceil(pontos.length / Math.max(2, Math.floor(w / 56))));
  const mover = (cx: number) => {
    const r = caixa.current?.getBoundingClientRect(); if (!r || pontos.length === 0) return;
    const rel = cx - r.left - esq;
    setAtivo(Math.max(0, Math.min(pontos.length - 1, Math.round((rel / Math.max(1, w)) * (pontos.length - 1)))));
  };
  const p = ativo !== null ? pontos[ativo] : null;

  if (valores.length === 0) return <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Sem dado no período.</p>;

  return (
    <div ref={caixa} className="relative w-full select-none"
      onMouseMove={(e) => mover(e.clientX)} onMouseLeave={() => setAtivo(null)}
      onTouchMove={(e) => mover(e.touches[0].clientX)} onTouchEnd={() => setAtivo(null)}>
      <svg width={largura} height={A} role="img" aria-label={`${rotuloSerie} por dia, ${pontos.length} dias`} className="block">
        <defs>
          <linearGradient id={grad} x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.28} />
            <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
          </linearGradient>
        </defs>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={esq} x2={esq + w} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeDasharray={t === 0 ? undefined : '3 4'} />
            <text x={esq - 8} y={y(t)} dy="0.32em" textAnchor="end" fontSize={11} fill="var(--fg-3)">{eixo(t, formato)}</text>
          </g>
        ))}
        {pontos.map((pt, i) => (i % cadaX === 0 || i === pontos.length - 1) && (
          <text key={pt.chave} x={x(i)} y={A - 8} textAnchor="middle" fontSize={11} fill="var(--fg-3)">{pt.rotulo}</text>
        ))}
        <path d={area} fill={`url(#${grad})`} className={menos ? '' : 'gp-fade-in'} />
        <path ref={linha} d={d} fill="none" stroke="var(--accent)" strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" pathLength={1} strokeDasharray="1 1" />
        {p && ativo !== null && (
          <g>
            <line x1={x(ativo)} x2={x(ativo)} y1={topo} y2={topo + h} stroke="var(--fg-3)" strokeDasharray="2 3" />
            {p.valor !== null && <circle cx={x(ativo)} cy={y(p.valor)} r={5} fill="var(--accent)" stroke="var(--surface-2)" strokeWidth={2} />}
          </g>
        )}
      </svg>
      {p && ativo !== null && (
        <div role="tooltip" className="pointer-events-none absolute top-1 z-10 -translate-x-1/2 whitespace-nowrap rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-3)] px-2.5 py-1.5 text-xs shadow-[var(--shadow-md)]"
          style={{ left: Math.min(largura - 70, Math.max(70, x(ativo))) }}>
          <span className="text-[var(--fg-3)]">{p.rotulo} · </span><strong className="tabular text-[var(--fg)]">{formatar(p.valor, formato)}</strong>
        </div>
      )}
      <table className="sr-only">
        <caption>{rotuloSerie} por dia</caption>
        <tbody>{pontos.map((pt) => <tr key={pt.chave}><th scope="row">{pt.rotulo}</th><td>{formatar(pt.valor, formato)}</td></tr>)}</tbody>
      </table>
    </div>
  );
}
