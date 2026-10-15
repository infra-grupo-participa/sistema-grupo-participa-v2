'use client';

import { useRef, useState, useSyncExternalStore, type CSSProperties, type KeyboardEvent, type PointerEvent } from 'react';
import { EmptyState } from '@/shared/ui/components';
import type { DiaAcumulado } from '../domain/filtro-graficos';

/*
 * Gráficos interativos do modal de pessoas (Ações da Black, 15/10/2026): animação de entrada, destaque no cursor com
 * tooltip e clique que alterna o filtro. SVG próprio, sem biblioteca nova (o v2 não usa nenhuma de gráfico). As cores
 * vêm só de tokens; a animação é CSS (globals.css, `gp-graf-*`) e some com prefers-reduced-motion.
 */

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const pct = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const CORES = ['var(--accent)', 'var(--cyan)', 'var(--purple)', 'var(--green)', 'var(--yellow)', 'var(--red)'];
const um = (n: number, rotulo: string) => `${inteiro.format(n)} ${n === 1 && rotulo.endsWith('s') ? rotulo.slice(0, -1) : rotulo}`;
const diaCurto = (dia: string) => `${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
const diaLongo = (dia: string) => {
  const d = new Date(`${dia}T12:00:00Z`);
  const semana = d.toLocaleDateString('pt-BR', { weekday: 'long', timeZone: 'UTC' });
  return `${semana}, ${dia.slice(8, 10)}/${dia.slice(5, 7)}/${dia.slice(0, 4)}`;
};

export type FatiaInterativa = { rotulo: string; quantidade: number };

type Dica = { x: number; y: number; linhas: string[]; abaixo?: boolean };
const ALTURA_DICA = 78;

function Dica({ dica }: { dica: Dica | null }) {
  if (!dica) return null;
  return <div role="tooltip" className="pointer-events-none absolute z-10 w-max max-w-[16rem] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-4)] px-2.5 py-1.5 text-xs text-[var(--fg)] shadow-[var(--shadow-md)] gp-fade-in" style={{ left: dica.x, top: dica.y, transform: dica.abaixo ? 'translate(-50%, 14px)' : 'translate(-50%, calc(-100% - 10px))' }}>
    {dica.linhas.map((t, i) => <div key={i} className={i === 0 ? 'font-semibold' : 'tabular text-[var(--fg-2)]'}>{t}</div>)}
  </div>;
}

/** Posição do ponteiro dentro do container, para ancorar o tooltip. Mantém o balão dentro da largura do container. */
function posicao(e: PointerEvent<Element>, caixa: HTMLElement | null): { x: number; y: number; abaixo: boolean } {
  const r = caixa?.getBoundingClientRect();
  if (!r) return { x: 0, y: 0, abaixo: false };
  const x = Math.min(Math.max(e.clientX - r.left, 80), Math.max(80, r.width - 80));
  const y = e.clientY - r.top;
  return { x, y, abaixo: y < ALTURA_DICA };
}

export function RoscaInterativa({ titulo, fatias, rotuloCentro, selecionado, onSelecionar }: {
  titulo: string; fatias: FatiaInterativa[]; rotuloCentro: string; selecionado: string | null; onSelecionar: (rotulo: string) => void;
}) {
  const [sobre, setSobre] = useState<string | null>(null);
  const [dica, setDica] = useState<Dica | null>(null);
  const caixa = useRef<HTMLDivElement>(null);
  const R = 42, C = 2 * Math.PI * R;
  const itens = fatias.map((f, i) => ({ ...f, cor: CORES[i % CORES.length] }));
  const positivas = itens.filter((f) => f.quantidade > 0);
  const total = positivas.reduce((s, f) => s + f.quantidade, 0);
  const foco = sobre ?? selecionado;
  const emFoco = foco ? positivas.find((f) => f.rotulo === foco) ?? null : null;
  const arcos = positivas.map((f, i) => ({ ...f, len: (f.quantidade / total) * C, inicio: (positivas.slice(0, i).reduce((s, a) => s + a.quantidade, 0) / total) * C }));
  const apagada = (rotulo: string) => foco !== null && foco !== rotulo;
  const texto = (f: FatiaInterativa) => [f.rotulo, `${inteiro.format(f.quantidade)} ${rotuloCentro} · ${pct.format((f.quantidade / total) * 100)}%`];

  return <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
    <h3 className="mb-3 text-sm font-semibold text-[var(--fg)]">{titulo}</h3>
    {total === 0 ? <EmptyState title="Sem dados para este gráfico" /> : <div ref={caixa} className="relative flex flex-col items-center gap-5 sm:flex-row" onPointerLeave={() => { setSobre(null); setDica(null); }}>
      <svg width="176" height="176" viewBox="0 0 176 176" role="img" aria-label={`${titulo}: ${inteiro.format(total)} ${rotuloCentro}. Clique numa fatia para filtrar os outros gráficos.`} className="shrink-0">
        <circle cx="88" cy="88" r={R} fill="none" stroke="var(--surface-3)" strokeWidth="25" />
        <g transform="rotate(-90 88 88)">
          {arcos.map((f) => <circle key={f.rotulo} cx="88" cy="88" r={R} fill="none" stroke={f.cor}
            className="gp-graf-arco cursor-pointer" style={{ '--gp-circ': C, strokeDasharray: `${f.len} ${C - f.len}`, strokeDashoffset: -f.inicio, strokeWidth: foco === f.rotulo ? 31 : 25, opacity: apagada(f.rotulo) ? 0.28 : 1 } as CSSProperties}
            onClick={() => { setDica(null); onSelecionar(f.rotulo); }}
            onPointerEnter={(e) => { setSobre(f.rotulo); setDica({ ...posicao(e, caixa.current), linhas: texto(f) }); }}
            onPointerMove={(e) => setDica({ ...posicao(e, caixa.current), linhas: texto(f) })} />)}
        </g>
        <text x="88" y="84" textAnchor="middle" fill="var(--fg)" fontSize="22" fontWeight="700" className="tabular">{inteiro.format(emFoco ? emFoco.quantidade : total)}</text>
        <text x="88" y="104" textAnchor="middle" fill="var(--fg-2)" fontSize="10">{emFoco ? `${pct.format((emFoco.quantidade / total) * 100)}%` : rotuloCentro}</text>
      </svg>
      <ul className="min-w-0 w-full flex-1 space-y-1 text-sm sm:w-auto">{itens.map((f) => <li key={f.rotulo}>
        <button type="button" aria-pressed={selecionado === f.rotulo} onClick={() => onSelecionar(f.rotulo)}
          onPointerEnter={() => setSobre(f.rotulo)} onFocus={() => setSobre(f.rotulo)} onBlur={() => setSobre(null)}
          className={'flex w-full items-center justify-between gap-3 rounded-[var(--r-sm)] px-1.5 py-1 text-left transition-opacity max-md:min-h-11 hover:bg-[var(--surface-3)] focus-visible:outline-2 focus-visible:outline-[var(--accent)] ' + (apagada(f.rotulo) ? 'opacity-50' : '') + (selecionado === f.rotulo ? ' bg-[var(--surface-3)]' : '')}>
          <span className="flex min-w-0 flex-1 items-center gap-2"><span aria-hidden="true" className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: f.cor }} /><span className="break-words text-[var(--fg-2)]">{f.rotulo}</span></span>
          <strong className="shrink-0 tabular text-[var(--fg)]">{inteiro.format(f.quantidade)}</strong>
        </button>
      </li>)}</ul>
      <Dica dica={dica} />
    </div>}
  </section>;
}

/** Largura do elemento, para o SVG desenhar nítido (texto do tamanho certo) do celular ao desktop. */
function useLargura(ref: React.RefObject<HTMLElement | null>, padrao: number): number {
  return useSyncExternalStore(
    (avisar) => { const el = ref.current; if (!el || typeof ResizeObserver === 'undefined') return () => {}; const o = new ResizeObserver(avisar); o.observe(el); return () => o.disconnect(); },
    () => Math.round(ref.current?.clientWidth || padrao),
    () => padrao,
  );
}

export function EvolucaoInterativa({ rows, rotulo, chaveAnimacao, diaSelecionado, onSelecionarDia }: { rows: DiaAcumulado[]; rotulo: string; chaveAnimacao: string; diaSelecionado: string | null; onSelecionarDia: (dia: string) => void }) {
  const caixa = useRef<HTMLDivElement>(null);
  const largura = Math.max(280, useLargura(caixa, 640));
  const [ativo, setAtivo] = useState<number | null>(null);
  const [dica, setDica] = useState<Dica | null>(null);
  if (!rows.length) return <EmptyState title={`Sem evolução de ${rotulo}`} hint="nenhuma data no conjunto" />;

  const compacto = largura < 480;
  const esq = compacto ? 30 : 40, dir = compacto ? 34 : 44, topo = 16, base = 34, altura = compacto ? 230 : 270;
  const areaW = largura - esq - dir, areaH = altura - topo - base;
  const n = rows.length;
  const passo = areaW / n;
  const larguraBarra = Math.max(3, Math.min(34, passo * 0.62));
  const arredondar = (max: number) => Math.max(4, Math.ceil(max / 4) * 4);
  const tetoDia = arredondar(Math.max(...rows.map((r) => r.quantidade)));
  const tetoAcum = arredondar(rows[n - 1].acumulado);
  const cx = (i: number) => esq + passo * (i + 0.5);
  const yDia = (v: number) => topo + areaH - (v / tetoDia) * areaH;
  const yAcum = (v: number) => topo + areaH - (v / tetoAcum) * areaH;
  const linha = rows.map((r, i) => `${i === 0 ? 'M' : 'L'}${cx(i).toFixed(1)},${yAcum(r.acumulado).toFixed(1)}`).join(' ');
  const passoRotulo = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(areaW / 46))));
  const texto = (r: DiaAcumulado) => [diaLongo(r.dia), `No dia: ${um(r.quantidade, rotulo)}`, `Acumulado: ${um(r.acumulado, rotulo)}`];
  const mostrar = (i: number) => { setAtivo(i); setDica({ x: Math.min(Math.max(cx(i), 90), Math.max(90, largura - dir - 90)), y: Math.min(yDia(rows[i].quantidade), yAcum(rows[i].acumulado)), linhas: texto(rows[i]), abaixo: Math.min(yDia(rows[i].quantidade), yAcum(rows[i].acumulado)) < ALTURA_DICA + 28 }); };
  const sair = () => { setAtivo(null); setDica(null); };
  const aoTeclar = (e: KeyboardEvent<SVGGElement>) => { if (e.key === 'ArrowRight') mostrar(Math.min(n - 1, (ativo ?? -1) + 1)); else if (e.key === 'ArrowLeft') mostrar(Math.max(0, (ativo ?? n) - 1)); else if (e.key === 'Escape') sair(); };
  const ticks = [0, 1, 2, 3, 4];
  const resumo = `${um(rows[n - 1].acumulado, rotulo)} em ${n} ${n === 1 ? 'dia' : 'dias'}`;

  return <div ref={caixa} className="relative" onPointerLeave={sair}>
    <div className="mb-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-[var(--fg-2)]">
      <span className="flex items-center gap-1.5"><span aria-hidden="true" className="h-2.5 w-2.5 rounded-sm" style={{ background: 'var(--accent)' }} />Por dia (eixo esquerdo)</span>
      <span className="flex items-center gap-1.5"><span aria-hidden="true" className="h-0.5 w-4 rounded-full" style={{ background: 'var(--cyan)' }} />Acumulado (eixo direito)</span>
    </div>
    <svg width={largura} height={altura} viewBox={`0 0 ${largura} ${altura}`} role="group" aria-label={`Evolução diária de ${rotulo}: ${resumo}. Use as setas para percorrer os dias e Enter para filtrar por um dia.`} className="block max-w-full" onKeyDown={(e) => { aoTeclar(e); if ((e.key === 'Enter' || e.key === ' ') && ativo !== null) { e.preventDefault(); onSelecionarDia(rows[ativo].dia); } }} tabIndex={0} onBlur={sair}>
      {ticks.map((k) => <g key={k}>
        <line x1={esq} x2={largura - dir} y1={yDia((tetoDia / 4) * k)} y2={yDia((tetoDia / 4) * k)} stroke="var(--border)" strokeWidth="1" />
        <text x={esq - 6} y={yDia((tetoDia / 4) * k) + 3} textAnchor="end" fontSize="10" fill="var(--fg-3)" className="tabular">{inteiro.format((tetoDia / 4) * k)}</text>
        <text x={largura - dir + 6} y={yAcum((tetoAcum / 4) * k) + 3} fontSize="10" fill="var(--cyan)" className="tabular">{inteiro.format((tetoAcum / 4) * k)}</text>
      </g>)}
      <g key={chaveAnimacao}>
        {rows.map((r, i) => r.quantidade > 0 && <rect key={r.dia} x={cx(i) - larguraBarra / 2} y={yDia(r.quantidade)} width={larguraBarra} height={topo + areaH - yDia(r.quantidade)} rx="3"
          fill="var(--accent)" className="gp-graf-barra" style={{ opacity: (ativo !== null && ativo !== i) || (diaSelecionado !== null && diaSelecionado !== r.dia) ? 0.3 : 1, animationDelay: `${Math.min(i * 25, 400)}ms` }} />)}
        <path d={linha} fill="none" stroke="var(--cyan)" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" pathLength={1} className="gp-graf-linha" />
        {rows.map((r, i) => <circle key={r.dia} cx={cx(i)} cy={yAcum(r.acumulado)} r={ativo === i ? 5.5 : n > 20 ? 0 : 3.5} fill="var(--cyan)" stroke="var(--surface-2)" strokeWidth="1.5" className="gp-graf-ponto" />)}
      </g>
      <line x1={esq} x2={largura - dir} y1={topo + areaH} y2={topo + areaH} stroke="var(--fg-3)" strokeWidth="1" />
      {rows.map((r, i) => i % passoRotulo === 0 && <text key={r.dia} x={cx(i)} y={topo + areaH + 16} textAnchor="middle" fontSize="10" fill={ativo === i ? 'var(--fg)' : 'var(--fg-3)'}>{diaCurto(r.dia)}</text>)}
      {ativo !== null && <rect x={cx(ativo) - passo / 2} y={topo} width={passo} height={areaH} fill="var(--accent)" opacity="0.1" pointerEvents="none" />}
      {rows.map((r, i) => <rect key={r.dia} x={esq + passo * i} y={topo} width={passo} height={areaH} fill="transparent" className="cursor-pointer"
        onPointerEnter={() => mostrar(i)} onPointerMove={() => mostrar(i)} onClick={() => { mostrar(i); onSelecionarDia(r.dia); }} aria-pressed={diaSelecionado === r.dia}><title>{texto(r).join(' · ')}</title></rect>)}
    </svg>
    <Dica dica={dica} />
    <p className="mt-1 text-xs text-[var(--fg-3)]">{resumo}. Passe o cursor em um dia para ver o detalhe; clique para filtrar os outros gráficos e a tabela por aquele dia.</p>
  </div>;
}
