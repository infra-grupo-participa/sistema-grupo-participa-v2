'use client';

// Mapa da Jornada (fluxograma do Arthur, vivo). SVG só de 640 px para cima; abaixo disso, a lista de etapas na
// mesma ordem. Espessura da seta = sqrt(volume), fluxo animado só sem movimento reduzido. O filtro de funil apaga
// os outros caminhos (opacidade 0,25, fora do teclado), sem tirá-los do lugar.
import { useId, type KeyboardEvent } from 'react';
import {
  NO, NOS, PAINEIS, ROTULOS_SOLTOS, SETAS, VIEWBOX_JORNADA, espessura, noApagado, resumoDoNo,
  type DefinicaoNo, type MapaMetricas, type MetricaNo,
} from '../domain/jornada';
import type { FiltroFunil } from '../domain/tipos';
import { dicaTaxa, formatar, usePrefereMenosMovimento } from './pecas';

const P = 14; // margem interna da caixa
const valorTexto = (x: MetricaNo) => formatar(x.valor, x.formato);

function linhasDoNo(n: DefinicaoNo, metricas: MetricaNo[]) {
  const resumo = resumoDoNo(n, metricas);
  const semDado = n.recorte === null ? (n.semFonte ? 'Sem dado' : null) : resumo.length === 0 && n.resumo ? 'Sem dado no período' : null;
  return { resumo, semDado };
}

function No({ n, metricas, apagado, ativo, onAbrir }: { n: DefinicaoNo; metricas: MetricaNo[]; apagado: boolean; ativo: boolean; onAbrir: () => void }) {
  const { resumo, semDado } = linhasDoNo(n, metricas);
  const cx = n.x + n.w / 2;
  const centro = n.forma !== 'caixa';
  const tx = centro ? cx : n.x + P;
  const anchor = centro ? 'middle' : 'start';
  // Linhas de texto empilhadas; a decisão centraliza na vertical.
  type L = { t: string; cls: string; h: number; valor?: string; dica?: string };
  const ls: L[] = [];
  if (n.kicker) ls.push({ t: n.kicker, cls: 'fill-[var(--accent)] text-[10px] font-semibold uppercase tracking-wide', h: 14 });
  ls.push({ t: n.titulo, cls: 'fill-[var(--fg)] text-[14px] font-bold', h: 17 });
  for (const s of n.sub) ls.push({ t: s, cls: 'fill-[var(--fg-3)] text-[10.5px]', h: 13 });
  if (resumo.length || semDado) ls.push({ t: '', cls: '', h: 4 });
  for (const r of resumo) ls.push({ t: r.rotulo, cls: 'fill-[var(--fg-2)] text-[11px]', h: 15, valor: valorTexto(r), dica: r.taxa ? dicaTaxa(r.taxa) : r.nota });
  if (semDado) ls.push({ t: semDado, cls: 'fill-[var(--fg-3)] text-[11px] italic', h: 15, dica: n.semFonte });
  const altura = ls.reduce((s, l) => s + l.h, 0);
  let y = n.forma === 'caixa' ? n.y + P + 4 : n.y + (n.h - altura) / 2 + 11;

  const teclado = (e: KeyboardEvent) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onAbrir(); } };
  const contorno = ativo ? 'var(--accent)' : n.destaque ? 'var(--border-accent)' : 'var(--border-strong)';
  const forma = n.forma === 'decisao'
    ? <polygon points={`${cx},${n.y} ${n.x + n.w},${n.y + n.h / 2} ${cx},${n.y + n.h} ${n.x},${n.y + n.h / 2}`} fill="var(--surface-2)" stroke={contorno} strokeWidth={ativo ? 2.5 : 1.2} />
    : <rect x={n.x} y={n.y} width={n.w} height={n.h} rx={n.forma === 'pilula' ? Math.min(n.h / 2, 26) : 10} fill="var(--surface-2)" stroke={contorno} strokeWidth={ativo ? 2.5 : n.destaque ? 1.6 : 1.2} />;

  return (
    <g role="button" tabIndex={apagado ? -1 : 0} aria-disabled={apagado || undefined} aria-label={`${n.kicker ? n.kicker + ': ' : ''}${n.titulo}. ${resumo.map((r) => `${r.rotulo} ${valorTexto(r)}`).join(', ')}${semDado ? semDado : ''}`}
      onClick={apagado ? undefined : onAbrir} onKeyDown={apagado ? undefined : teclado}
      className={'outline-none focus-visible:[&>*:first-child]:stroke-[var(--accent)] ' + (apagado ? '' : 'cursor-pointer atm-historico-interativo')}
      style={{ opacity: apagado ? 0.25 : 1, pointerEvents: apagado ? 'none' : undefined, transition: 'opacity .3s' }}>
      {forma}
      {ls.map((l, i) => {
        y += i === 0 ? 0 : ls[i - 1].h;
        if (!l.t) return null;
        return (
          <g key={i}>
            <text x={l.valor !== undefined ? n.x + P : tx} y={y} textAnchor={l.valor !== undefined ? 'start' : anchor} className={l.cls}>
              {l.dica && <title>{l.dica}</title>}{l.t}
            </text>
            {l.valor !== undefined && <text x={n.x + n.w - P} y={y} textAnchor="end" className={'tabular text-[11px] font-semibold ' + (l.valor === 'Sem dado' ? 'fill-[var(--fg-3)]' : 'fill-[var(--fg)]')}>{l.valor}</text>}
          </g>
        );
      })}
    </g>
  );
}

export function MapaJornada({ metricas, funil, ativo, onAbrir }: { metricas: MapaMetricas; funil: FiltroFunil; ativo: string | null; onAbrir: (id: string) => void }) {
  const menos = usePrefereMenosMovimento();
  const seta = useId().replace(/:/g, '');
  const volumes = SETAS.map((s) => (s.volume ? s.volume(metricas) : null));
  const max = Math.max(0, ...volumes.map((v) => v ?? 0));

  return (
    <>
      <svg viewBox={`0 0 ${VIEWBOX_JORNADA.largura} ${VIEWBOX_JORNADA.altura}`} className="hidden h-auto w-full sm:block" role="group" aria-label="Jornada do lead">
        <defs>
          <marker id={`ponta-${seta}`} viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse" markerUnits="userSpaceOnUse">
            <path d="M0 0 L10 5 L0 10 z" fill="var(--fg-3)" />
          </marker>
        </defs>
        {PAINEIS.map((p) => (
          <g key={p.titulo}>
            <rect x={p.x} y={p.y} width={p.w} height={p.h} rx={14} fill="none" stroke="var(--border)" strokeDasharray="6 6" />
            <text x={p.tituloX} y={p.tituloY} className="fill-[var(--fg-3)] text-[11px] font-semibold uppercase tracking-wide">{p.titulo}</text>
          </g>
        ))}
        {ROTULOS_SOLTOS.map((r) => <text key={r.texto} x={r.x} y={r.y} className="fill-[var(--fg-3)] text-[10.5px] italic">{r.texto}</text>)}
        {SETAS.map((s, i) => {
          const de = NO.get(s.de); const para = NO.get(s.para);
          const apagada = (de && noApagado(de, funil)) || (para && noApagado(para, funil));
          const v = volumes[i];
          const w = espessura(v, max);
          return (
            <g key={`${s.de}-${s.para}`} style={{ opacity: apagada ? 0.25 : 1, transition: 'opacity .3s' }}>
              <path d={s.d} fill="none" stroke="var(--border-strong)" strokeWidth={w} strokeDasharray={s.tracejada ? '6 5' : undefined} markerEnd={`url(#ponta-${seta})`} strokeLinejoin="round">
                {v !== null && <title>{`Volume: ${formatar(v, 'int')}`}</title>}
              </path>
              {!menos && !apagada && v !== null && v > 0 && (
                <path d={s.d} fill="none" stroke="var(--accent)" strokeOpacity={0.7} strokeWidth={Math.max(1.5, w / 3)} strokeDasharray="3 15" strokeLinecap="round" aria-hidden="true">
                  <animate attributeName="stroke-dashoffset" from="18" to="0" dur="1.1s" repeatCount="indefinite" />
                </path>
              )}
              {s.rotulo && s.rotuloX !== undefined && s.rotuloY !== undefined && (
                <text x={s.rotuloX} y={s.rotuloY} transform={s.rotuloGiro ? `rotate(${s.rotuloGiro} ${s.rotuloX} ${s.rotuloY})` : undefined}
                  textAnchor={s.rotuloGiro ? 'middle' : 'start'} className="fill-[var(--fg-3)] text-[10.5px]">
                  {s.rotulo.map((t, j) => <tspan key={j} x={s.rotuloX} dy={j === 0 ? 0 : 13}>{t}</tspan>)}
                </text>
              )}
            </g>
          );
        })}
        {NOS.map((n) => (
          <No key={n.id} n={n} metricas={metricas[n.id] ?? []} apagado={noApagado(n, funil)} ativo={ativo === n.id} onAbrir={() => onAbrir(n.id)} />
        ))}
      </svg>

      {/* Abaixo de 640 px: as etapas em lista, na ordem do mapa. */}
      <ol className="space-y-2 sm:hidden">
        {NOS.filter((n) => !noApagado(n, funil)).map((n) => {
          const { resumo, semDado } = linhasDoNo(n, metricas[n.id] ?? []);
          return (
            <li key={n.id}>
              <button type="button" onClick={() => onAbrir(n.id)} aria-pressed={ativo === n.id}
                className={'w-full rounded-[var(--r-md)] border bg-[var(--surface-2)] p-3 text-left ' + (ativo === n.id ? 'border-[var(--accent)]' : n.destaque ? 'border-[var(--border-accent)]' : 'border-[var(--border)]')}>
                {n.kicker && <span className="block text-[10px] font-semibold uppercase tracking-wide text-[var(--accent)]">{n.kicker}</span>}
                <span className="block text-sm font-bold text-[var(--fg)]">{n.titulo}</span>
                {n.sub.map((s) => <span key={s} className="block text-xs text-[var(--fg-3)]">{s}</span>)}
                {resumo.map((r) => (
                  <span key={r.rotulo} className="mt-1 flex justify-between gap-3 text-xs"><span className="text-[var(--fg-2)]">{r.rotulo}</span><span className="tabular font-semibold text-[var(--fg)]">{valorTexto(r)}</span></span>
                ))}
                {semDado && <span className="mt-1 block text-xs italic text-[var(--fg-3)]">{semDado}</span>}
              </button>
            </li>
          );
        })}
      </ol>
    </>
  );
}
