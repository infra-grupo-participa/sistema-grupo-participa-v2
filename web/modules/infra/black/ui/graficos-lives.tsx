'use client';

// Gráficos da aba Lives, em SVG puro e só tokens de cor. Três gráficos, cada um com uma pergunta:
// - CurvaMinuto: quando a sala enche e esvazia, e o chat acompanha? (espectadores + faixa de chat/reações no MESMO eixo)
// - CurvaComparativa: a live no ar está acima ou abaixo da última do mesmo tipo, no mesmo minuto?
// - GraficoEvolucao: a audiência cresce de uma live para a outra até a venda?
// Todos: cursor com valor, teclado (setas), tabela equivalente para leitor de tela, sem animação com movimento reduzido.
import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import { minutoDe, ROTULO_TIPO_LIVE, type Live, type MarcosCurva, type MinutoLive, type PontoComparativo, type PontoEvolucao } from '../domain/lives';
import { COR_TIPO, dataCurta, numeroDe, pctDe, posicaoTexto, tituloDe } from './lives/formatos';
import { inteiro, usePrefereMenosMovimento } from './pecas';


function useLargura() {
  const caixa = useRef<HTMLDivElement>(null);
  const [largura, setLargura] = useState(640);
  useEffect(() => {
    const el = caixa.current; if (!el) return;
    const ro = new ResizeObserver(([e]) => setLargura(Math.max(280, Math.round(e.contentRect.width))));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return { caixa, largura };
}

/** Passo "redondo" do eixo (1, 2, 5 × 10^n) com no máximo 5 divisões. */
function passoBonito(max: number): number {
  const alvo = Math.max(1, max);
  for (let p = 1; ; p *= 10) for (const f of [1, 2, 5]) if (alvo / (f * p) <= 5) return f * p;
}
const tetoDe = (max: number) => { const p = passoBonito(max); return { passo: p, teto: Math.max(p, Math.ceil(max / p) * p) }; };

/** Caminho de linha com quebra onde o valor é null (sem dado não vira zero). */
function caminho(pontos: { x: number; y: number | null }[]): string {
  let d = ''; let aberto = false;
  for (const p of pontos) {
    if (p.y === null) { aberto = false; continue; }
    d += `${aberto ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)} `; aberto = true;
  }
  return d.trim();
}

/** Desenha a linha aos poucos (WAAPI), como o GraficoLinha do dashboard. */
function useDesenhar(dep: unknown) {
  const ref = useRef<SVGPathElement>(null);
  const menos = usePrefereMenosMovimento();
  useEffect(() => {
    const el = ref.current; if (!el || menos || typeof el.animate !== 'function') return;
    const anim = el.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 900, easing: 'cubic-bezier(.2,.8,.2,1)' });
    return () => anim.cancel();
  }, [menos, dep]);
  return { ref, menos };
}

function Dica({ esquerda, largura, children }: { esquerda: number; largura: number; children: ReactNode }) {
  return (
    <div role="tooltip" className="pointer-events-none absolute top-1 z-10 -translate-x-1/2 whitespace-nowrap rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-3)] px-2.5 py-1.5 text-xs shadow-[var(--shadow-md)]"
      style={{ left: Math.min(largura - 96, Math.max(96, esquerda)) }}>
      {children}
    </div>
  );
}

// ─── Curva minuto a minuto com faixa de chat e reações ─────────────────────────────────────────────────────────

interface Marcador { id: string; letra: string; cor: string; seg: number; rotulo: string }

/** Marcadores a desenhar e a listar: pico, sala cheia e as quedas. A mesma lista alimenta o gráfico e os chips. */
export function marcadoresDe(marcos: MarcosCurva): Marcador[] {
  const lista: Marcador[] = [];
  if (marcos.pico) lista.push({ id: 'pico', letra: 'P', cor: 'var(--green)', seg: marcos.pico.seg, rotulo: `Pico: ${inteiro(marcos.pico.espectadores)} no min ${marcos.pico.minuto}` });
  if (marcos.salaCheia) lista.push({ id: 'cheia', letra: 'S', cor: 'var(--cyan)', seg: marcos.salaCheia.seg, rotulo: `Sala cheia (90% do pico) a partir do min ${marcos.salaCheia.minuto}` });
  marcos.quedas.forEach((q, i) => lista.push({
    id: `queda-${i}`, letra: `Q${i + 1}`, cor: 'var(--red)', seg: q.deSeg,
    rotulo: `Queda: ${inteiro(q.de)} para ${inteiro(q.ate)} (-${inteiro(q.perda)}) do min ${q.deMinuto} ao ${q.ateMinuto}`,
  }));
  return lista;
}

export function CurvaMinuto({ minutos, marcos, selecionado, onSelecionar, rotulo }: {
  minutos: MinutoLive[]; marcos: MarcosCurva; selecionado: number | null; onSelecionar: (minuto: number | null) => void; rotulo: string;
}) {
  const { caixa, largura } = useLargura();
  const grad = `grad-${useId().replace(/:/g, '')}`;
  const { ref: linha, menos } = useDesenhar(minutos.length);
  const [ativo, setAtivo] = useState<number | null>(null);

  const ordenados = [...minutos].sort((a, b) => a.seg - b.seg);
  const esq = largura < 480 ? 40 : 52; const dir = 12; const topo = 34; const aCurva = 200; const gap = 10; const aFaixa = 52; const base = 26;
  const A = topo + aCurva + gap + aFaixa + base;
  const w = largura - esq - dir;
  const xMax = Math.max(1, (ordenados[ordenados.length - 1]?.seg ?? 60) / 60);
  const x = (min: number) => esq + (min / xMax) * w;
  const valoresEsp = ordenados.map((m) => m.espectadores).filter((v): v is number => v !== null);
  const { passo, teto } = tetoDe(Math.max(0, ...valoresEsp));
  const y = (v: number) => topo + aCurva - (v / teto) * aCurva;
  const maxChat = Math.max(1, ...ordenados.map((m) => m.chat ?? 0));
  const temChat = ordenados.some((m) => m.chat !== null);
  const temReacao = ordenados.some((m) => m.reacoes !== null);
  const yFaixa = topo + aCurva + gap;
  const largBarra = Math.max(1, Math.min(8, (w / Math.max(1, ordenados.length)) - 1));

  const d = caminho(ordenados.map((m) => ({ x: x(m.seg / 60), y: m.espectadores === null ? null : y(m.espectadores) })));
  const area = (() => {
    let s = ''; let seg: MinutoLive[] = [];
    const fecha = () => {
      if (seg.length > 1) s += `M${x(seg[0].seg / 60).toFixed(1)},${(topo + aCurva).toFixed(1)} ${seg.map((m) => `L${x(m.seg / 60).toFixed(1)},${y(m.espectadores as number).toFixed(1)}`).join(' ')} L${x(seg[seg.length - 1].seg / 60).toFixed(1)},${(topo + aCurva).toFixed(1)} Z `;
      seg = [];
    };
    for (const m of ordenados) { if (m.espectadores === null) fecha(); else seg.push(m); }
    fecha();
    return s;
  })();

  const passoX = [5, 10, 15, 20, 30, 60].find((p) => (p / xMax) * w >= 44) ?? 60;
  const ticksX: number[] = []; for (let m = 0; m <= xMax; m += passoX) ticksX.push(m);
  const ticksY = Array.from({ length: Math.round(teto / passo) + 1 }, (_, i) => i * passo);

  const indiceDoX = (cx: number) => {
    const r = caixa.current?.getBoundingClientRect(); if (!r || ordenados.length === 0) return null;
    const min = ((cx - r.left - esq) / Math.max(1, w)) * xMax;
    let melhor = 0; let dist = Infinity;
    ordenados.forEach((m, i) => { const dd = Math.abs(m.seg / 60 - min); if (dd < dist) { dist = dd; melhor = i; } });
    return melhor;
  };
  const noTeclado = (e: KeyboardEvent<HTMLDivElement>) => {
    const ultimo = ordenados.length - 1;
    const atual = ativo ?? Math.max(0, ordenados.findIndex((m) => m.seg / 60 === selecionado));
    if (e.key === 'ArrowRight') { e.preventDefault(); setAtivo(Math.min(ultimo, atual + 1)); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); setAtivo(Math.max(0, atual - 1)); }
    else if (e.key === 'Home') { e.preventDefault(); setAtivo(0); }
    else if (e.key === 'End') { e.preventDefault(); setAtivo(ultimo); }
    else if ((e.key === 'Enter' || e.key === ' ') && ativo !== null) {
      e.preventDefault();
      const min = minutoDe(ordenados[ativo].seg);
      onSelecionar(selecionado === min ? null : min);
    } else if (e.key === 'Escape') setAtivo(null);
  };

  // Etiquetas dos marcos: se duas ficam a menos de 22 px, a segunda desce uma linha.
  const marcadores = marcadoresDe(marcos);
  const etiquetas = (() => {
    const colocadas: { x: number; linha: number }[] = [];
    return [...marcadores].sort((a, b) => a.seg - b.seg).map((mk) => {
      const px = x(mk.seg / 60);
      let linhaE = 0;
      while (colocadas.some((c) => c.linha === linhaE && Math.abs(c.x - px) < 24) && linhaE < 1) linhaE++;
      colocadas.push({ x: px, linha: linhaE });
      return { mk, px, linha: linhaE };
    });
  })();

  const p = ativo !== null ? ordenados[ativo] : null;
  const xAtivo = p ? x(p.seg / 60) : 0;
  const selX = selecionado !== null ? x(selecionado + 0.5) : null;
  const larguraMinuto = Math.max(3, w / xMax);

  return (
    <div ref={caixa} className="relative w-full select-none rounded-[var(--r-md)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]" tabIndex={0}
      aria-label={`${rotulo}. Use as setas para percorrer os minutos e Enter para filtrar o chat do minuto.`}
      onKeyDown={noTeclado} onBlur={() => setAtivo(null)}
      onMouseMove={(e) => setAtivo(indiceDoX(e.clientX))} onMouseLeave={() => setAtivo(null)}
      onTouchMove={(e) => setAtivo(indiceDoX(e.touches[0].clientX))}
      onClick={(e) => {
        const i = indiceDoX(e.clientX); if (i === null) return;
        const min = minutoDe(ordenados[i].seg);
        onSelecionar(selecionado === min ? null : min);
      }}>
      <svg width={largura} height={A} role="img" aria-label={rotulo} className="block cursor-crosshair">
        <defs>
          <linearGradient id={grad} x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.3} />
            <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
          </linearGradient>
        </defs>
        {ticksY.map((t) => (
          <g key={t}>
            <line x1={esq} x2={esq + w} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeDasharray={t === 0 ? undefined : '3 4'} />
            <text x={esq - 8} y={y(t)} dy="0.32em" textAnchor="end" fontSize={11} fill="var(--fg-3)">{inteiro(t)}</text>
          </g>
        ))}
        {ticksX.map((m) => <text key={m} x={x(m)} y={A - 8} textAnchor="middle" fontSize={11} fill="var(--fg-3)">{m}</text>)}

        {quedasSombra(marcos, x, topo, aCurva, aFaixa + gap)}
        {selX !== null && <rect x={selX - larguraMinuto / 2} y={topo} width={larguraMinuto} height={aCurva + gap + aFaixa} fill="var(--accent)" fillOpacity={0.16} />}

        <path d={area} fill={`url(#${grad})`} className={menos ? '' : 'gp-fade-in'} />
        <path ref={linha} d={d} fill="none" stroke="var(--accent)" strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" pathLength={1} strokeDasharray="1 1" />

        {/* Faixa do chat (barras) e das reações (pontos), no mesmo eixo de minutos */}
        <line x1={esq} x2={esq + w} y1={yFaixa + aFaixa} y2={yFaixa + aFaixa} stroke="var(--border)" />
        {temChat ? ordenados.map((m) => m.chat === null || m.chat === 0 ? null : (
          <rect key={`c${m.seg}`} x={x(m.seg / 60) - largBarra / 2} width={largBarra} y={yFaixa + aFaixa - (m.chat / maxChat) * (aFaixa - 10)} height={(m.chat / maxChat) * (aFaixa - 10)}
            rx={1} fill="var(--info)" fillOpacity={0.85} />
        )) : <text x={esq + w / 2} y={yFaixa + aFaixa / 2} textAnchor="middle" fontSize={11} fill="var(--fg-3)">Sem dado de chat por minuto</text>}
        {temReacao && ordenados.map((m) => m.reacoes === null || m.reacoes === 0 ? null : (
          <circle key={`r${m.seg}`} cx={x(m.seg / 60)} cy={yFaixa + 5} r={Math.min(5, 2 + m.reacoes / 4)} fill="var(--purple)" fillOpacity={0.9} />
        ))}
        <text x={esq - 8} y={yFaixa + aFaixa} textAnchor="end" fontSize={10} fill="var(--fg-3)">{temChat ? inteiro(maxChat) : ''}</text>
        <text x={esq - 8} y={yFaixa + 10} textAnchor="end" fontSize={10} fill="var(--fg-3)">chat</text>

        {/* Marcos automáticos */}
        {etiquetas.map(({ mk, px, linha: ln }) => {
          const ponto = ordenados.find((m) => m.seg === mk.seg);
          return (
            <g key={mk.id}>
              <line x1={px} x2={px} y1={topo - 4 + ln * 15} y2={topo + aCurva} stroke={mk.cor} strokeDasharray="2 3" opacity={0.7} />
              {ponto?.espectadores != null && <circle cx={px} cy={y(ponto.espectadores)} r={4.5} fill={mk.cor} stroke="var(--surface-2)" strokeWidth={2} />}
              <g transform={`translate(${px},${12 + ln * 15})`}>
                <rect x={-11} y={-9} width={22} height={16} rx={8} fill={mk.cor} />
                <text textAnchor="middle" y={3} fontSize={9} fontWeight={700} fill="var(--surface-1)">{mk.letra}</text>
              </g>
            </g>
          );
        })}

        {p && (
          <g>
            <line x1={xAtivo} x2={xAtivo} y1={topo} y2={yFaixa + aFaixa} stroke="var(--fg-3)" strokeDasharray="2 3" />
            {p.espectadores !== null && <circle cx={xAtivo} cy={y(p.espectadores)} r={5} fill="var(--accent)" stroke="var(--surface-2)" strokeWidth={2} />}
          </g>
        )}
      </svg>
      {p && (
        <Dica esquerda={xAtivo} largura={largura}>
          <span className="text-[var(--fg-3)]">Min {minutoDe(p.seg)} ({posicaoTexto(p.seg)}) · </span>
          <strong className="tabular text-[var(--fg)]">{numeroDe(p.espectadores)} na sala</strong>
          <span className="text-[var(--fg-3)]"> · chat {numeroDe(p.chat)} · reações {numeroDe(p.reacoes)}</span>
        </Dica>
      )}
      <div className="sr-only"><table>
        <caption>{rotulo}</caption>
        <thead><tr><th>Minuto</th><th>Espectadores</th><th>Chat</th><th>Reações</th></tr></thead>
        <tbody>{ordenados.map((m) => <tr key={m.seg}><th scope="row">{minutoDe(m.seg)}</th><td>{numeroDe(m.espectadores)}</td><td>{numeroDe(m.chat)}</td><td>{numeroDe(m.reacoes)}</td></tr>)}</tbody>
      </table></div>
    </div>
  );
}

function quedasSombra(marcos: MarcosCurva, x: (min: number) => number, topo: number, aCurva: number, extra: number) {
  return marcos.quedas.map((q, i) => {
    const x1 = x(q.deSeg / 60); const x2 = x(q.ateSeg / 60);
    return <rect key={`q${i}`} x={x1} y={topo} width={Math.max(4, x2 - x1)} height={aCurva + extra} fill="var(--red)" fillOpacity={0.14} />;
  });
}

// ─── Curva ao vivo contra a anterior do mesmo tipo ─────────────────────────────────────────────────────────────

export function CurvaComparativa({ pontos, rotuloAtual, rotuloAnterior, rotulo }: {
  pontos: PontoComparativo[]; rotuloAtual: string; rotuloAnterior: string | null; rotulo: string;
}) {
  const { caixa, largura } = useLargura();
  const { ref: linha, menos } = useDesenhar(pontos.length);
  const [ativo, setAtivo] = useState<number | null>(null);
  const esq = largura < 480 ? 40 : 52; const dir = 12; const topo = 14; const aCurva = 210; const base = 26;
  const A = topo + aCurva + base; const w = largura - esq - dir;
  const xMax = Math.max(1, pontos.length - 1);
  const x = (m: number) => esq + (m / xMax) * w;
  const todos = pontos.flatMap((p) => [p.atual, p.anterior]).filter((v): v is number => v !== null);
  const { passo, teto } = tetoDe(Math.max(0, ...todos));
  const y = (v: number) => topo + aCurva - (v / teto) * aCurva;
  const dAtual = caminho(pontos.map((p) => ({ x: x(p.minuto), y: p.atual === null ? null : y(p.atual) })));
  const dAnt = caminho(pontos.map((p) => ({ x: x(p.minuto), y: p.anterior === null ? null : y(p.anterior) })));
  const ultimoAtual = [...pontos].reverse().find((p) => p.atual !== null) ?? null;
  const passoX = [5, 10, 15, 20, 30, 60].find((p) => (p / xMax) * w >= 44) ?? 60;
  const ticksX: number[] = []; for (let m = 0; m <= xMax; m += passoX) ticksX.push(m);
  const ticksY = Array.from({ length: Math.round(teto / passo) + 1 }, (_, i) => i * passo);
  const mover = (cx: number) => {
    const r = caixa.current?.getBoundingClientRect(); if (!r || pontos.length === 0) return;
    setAtivo(Math.max(0, Math.min(pontos.length - 1, Math.round(((cx - r.left - esq) / Math.max(1, w)) * xMax))));
  };
  const noTeclado = (e: KeyboardEvent<HTMLDivElement>) => {
    const atual = ativo ?? Math.max(0, pontos.findIndex((p) => p.minuto === ultimoAtual?.minuto));
    if (e.key === 'ArrowRight') { e.preventDefault(); setAtivo(Math.min(pontos.length - 1, atual + 1)); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); setAtivo(Math.max(0, atual - 1)); }
    else if (e.key === 'Escape') setAtivo(null);
  };
  const p = ativo !== null ? pontos[ativo] : null;
  if (todos.length === 0) return <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Sem dado de espectadores ainda.</p>;

  return (
    <div ref={caixa} className="relative w-full select-none rounded-[var(--r-md)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]" tabIndex={0}
      aria-label={`${rotulo}. Use as setas para percorrer os minutos.`} onKeyDown={noTeclado} onBlur={() => setAtivo(null)}
      onMouseMove={(e) => mover(e.clientX)} onMouseLeave={() => setAtivo(null)} onTouchMove={(e) => mover(e.touches[0].clientX)} onTouchEnd={() => setAtivo(null)}>
      <svg width={largura} height={A} role="img" aria-label={rotulo} className="block">
        {ticksY.map((t) => (
          <g key={t}>
            <line x1={esq} x2={esq + w} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeDasharray={t === 0 ? undefined : '3 4'} />
            <text x={esq - 8} y={y(t)} dy="0.32em" textAnchor="end" fontSize={11} fill="var(--fg-3)">{inteiro(t)}</text>
          </g>
        ))}
        {ticksX.map((m) => <text key={m} x={x(m)} y={A - 8} textAnchor="middle" fontSize={11} fill="var(--fg-3)">{m}</text>)}
        <path d={dAnt} fill="none" stroke="var(--fg-3)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" opacity={0.7} />
        <path ref={linha} d={dAtual} fill="none" stroke="var(--accent)" strokeWidth={3} strokeLinejoin="round" strokeLinecap="round" pathLength={1} strokeDasharray="1 1" />
        {ultimoAtual && ultimoAtual.atual !== null && (
          <g>
            {!menos && <circle cx={x(ultimoAtual.minuto)} cy={y(ultimoAtual.atual)} r={6} fill="var(--accent)" opacity={0.4}>
              <animate attributeName="r" values="6;14;6" dur="2s" repeatCount="indefinite" />
              <animate attributeName="opacity" values="0.45;0;0.45" dur="2s" repeatCount="indefinite" />
            </circle>}
            <circle cx={x(ultimoAtual.minuto)} cy={y(ultimoAtual.atual)} r={5} fill="var(--accent)" stroke="var(--surface-2)" strokeWidth={2} />
          </g>
        )}
        {p && (
          <g>
            <line x1={x(p.minuto)} x2={x(p.minuto)} y1={topo} y2={topo + aCurva} stroke="var(--fg-3)" strokeDasharray="2 3" />
            {p.anterior !== null && <circle cx={x(p.minuto)} cy={y(p.anterior)} r={4} fill="var(--fg-3)" stroke="var(--surface-2)" strokeWidth={2} />}
            {p.atual !== null && <circle cx={x(p.minuto)} cy={y(p.atual)} r={5} fill="var(--accent)" stroke="var(--surface-2)" strokeWidth={2} />}
          </g>
        )}
      </svg>
      {p && (
        <Dica esquerda={p ? x(p.minuto) : 0} largura={largura}>
          <span className="text-[var(--fg-3)]">Min {p.minuto} · </span>
          <strong className="tabular text-[var(--accent)]">{numeroDe(p.atual)}</strong>
          <span className="text-[var(--fg-3)]"> agora · {rotuloAnterior ?? 'anterior'} </span>
          <strong className="tabular text-[var(--fg-2)]">{numeroDe(p.anterior)}</strong>
        </Dica>
      )}
      <div className="sr-only"><table>
        <caption>{rotulo}</caption>
        <thead><tr><th>Minuto</th><th>{rotuloAtual}</th><th>{rotuloAnterior ?? 'Anterior'}</th></tr></thead>
        <tbody>{pontos.map((q) => <tr key={q.minuto}><th scope="row">{q.minuto}</th><td>{numeroDe(q.atual)}</td><td>{numeroDe(q.anterior)}</td></tr>)}</tbody>
      </table></div>
    </div>
  );
}

// ─── Evolução do pico, live a live ─────────────────────────────────────────────────────────────────────────────

export function GraficoEvolucao({ pontos, lives, rotulo, onAbrir }: {
  pontos: PontoEvolucao[]; lives: readonly Live[]; rotulo: string; onAbrir: (videoId: string) => void;
}) {
  const { caixa, largura } = useLargura();
  const [ativo, setAtivo] = useState<string | null>(null);
  const esq = largura < 480 ? 40 : 52; const dir = 14; const topo = 16; const aCurva = 200; const base = 40;
  const A = topo + aCurva + base; const w = largura - esq - dir;
  const n = Math.max(1, pontos.length);
  const x = (i: number) => esq + ((i + 0.5) / n) * w;
  const picos = pontos.map((q) => q.pico).filter((v): v is number => v !== null);
  const { passo, teto } = tetoDe(Math.max(0, ...picos));
  const y = (v: number) => topo + aCurva - (v / teto) * aCurva;
  const ticksY = Array.from({ length: Math.round(teto / passo) + 1 }, (_, i) => i * passo);
  const porId = new Map(lives.map((l) => [l.videoId, l]));
  // A linha de cada tipo liga só os pontos do próprio tipo (sem passar por cima do outro).
  const ligar = (tipo: 'consultoria' | 'produto') => {
    const idx = pontos.map((q, i) => (q.tipo === tipo && q.pico !== null ? i : -1)).filter((i) => i >= 0);
    return idx.map((i, k) => `${k === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(pontos[i].pico as number).toFixed(1)}`).join(' ');
  };
  const q = ativo ? pontos.find((p) => p.videoId === ativo) ?? null : null;
  const iAtivo = q ? pontos.indexOf(q) : -1;
  const vazio = picos.length === 0;

  return (
    <div ref={caixa} className="relative w-full select-none">
      <svg width={largura} height={A} role="img" aria-label={rotulo} className="block">
        {ticksY.map((t) => (
          <g key={t}>
            <line x1={esq} x2={esq + w} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeDasharray={t === 0 ? undefined : '3 4'} />
            <text x={esq - 8} y={y(t)} dy="0.32em" textAnchor="end" fontSize={11} fill="var(--fg-3)">{inteiro(t)}</text>
          </g>
        ))}
        {pontos.map((p, i) => (
          <g key={p.videoId}>
            {p.tipo === 'black' && <line x1={x(i)} x2={x(i)} y1={topo} y2={topo + aCurva} stroke="var(--accent)" strokeDasharray="4 4" opacity={0.7} />}
            <text x={x(i)} y={topo + aCurva + 16} textAnchor="middle" fontSize={largura < 480 ? 10 : 11} fill={p.tipo === 'black' ? 'var(--accent)' : 'var(--fg-3)'} fontWeight={p.tipo === 'black' ? 700 : 400}>{dataCurta(p.dataPrevista)}</text>
            <circle cx={x(i)} cy={topo + aCurva + 28} r={3.5} fill={COR_TIPO[p.tipo]} />
          </g>
        ))}
        {(['consultoria', 'produto'] as const).map((t) => <path key={t} d={ligar(t)} fill="none" stroke={COR_TIPO[t]} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" />)}
        {pontos.map((p, i) => {
          if (p.pico === null) return null;
          const live = porId.get(p.videoId);
          const amostra = live ? !live.temStudio : false;
          const cor = COR_TIPO[p.tipo];
          return (
            <g key={p.videoId} tabIndex={0} role="button" aria-label={`${tituloDe({ titulo: p.titulo })}, ${dataCurta(p.dataPrevista)}, pico ${numeroDe(p.pico)}. Enter abre o detalhe.`}
              className="cursor-pointer outline-none [&:focus-visible>circle:last-child]:stroke-[var(--accent)]"
              onMouseEnter={() => setAtivo(p.videoId)} onMouseLeave={() => setAtivo(null)} onFocus={() => setAtivo(p.videoId)} onBlur={() => setAtivo(null)}
              onClick={() => onAbrir(p.videoId)} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onAbrir(p.videoId); } }}>
              <circle cx={x(i)} cy={y(p.pico)} r={14} fill="transparent" />
              <circle cx={x(i)} cy={y(p.pico)} r={6} fill={amostra ? 'var(--surface-2)' : cor} stroke={cor} strokeWidth={2.5} />
            </g>
          );
        })}
        {vazio && <text x={esq + w / 2} y={topo + aCurva / 2} textAnchor="middle" fontSize={12} fill="var(--fg-3)">Nenhum pico medido ainda</text>}
        {q && q.pico !== null && iAtivo >= 0 && <line x1={x(iAtivo)} x2={x(iAtivo)} y1={topo} y2={topo + aCurva} stroke="var(--fg-3)" strokeDasharray="2 3" />}
      </svg>
      {q && q.pico !== null && iAtivo >= 0 && (
        <Dica esquerda={x(iAtivo)} largura={largura}>
          <span className="text-[var(--fg-3)]">{ROTULO_TIPO_LIVE[q.tipo]} {dataCurta(q.dataPrevista)} · pico </span>
          <strong className="tabular text-[var(--fg)]">{numeroDe(q.pico)}</strong>
          <span className="text-[var(--fg-3)]"> · contra a anterior </span>
          <strong className="tabular text-[var(--fg)]">{pctDe(q.contraAnterior)}</strong>
        </Dica>
      )}
      <div className="sr-only"><table>
        <caption>{rotulo}</caption>
        <thead><tr><th>Data</th><th>Tipo</th><th>Pico</th><th>Pico contra a anterior do mesmo tipo</th></tr></thead>
        <tbody>{pontos.map((p) => <tr key={p.videoId}><th scope="row">{dataCurta(p.dataPrevista)}</th><td>{ROTULO_TIPO_LIVE[p.tipo]}</td><td>{numeroDe(p.pico)}</td><td>{pctDe(p.contraAnterior)}</td></tr>)}</tbody>
      </table></div>
    </div>
  );
}
