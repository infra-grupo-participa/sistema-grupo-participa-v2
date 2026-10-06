'use client';

// Grade de 12 colunas do dashboard (visualização e edição). Em edição: arrastar para reordenar com indicador
// de onde cai, soltar métrica da biblioteca, alça para mudar a largura, menu do widget e teclado
// (setas movem, Enter seleciona, Delete remove). Os visuais vêm do painel do Início (Graficos.tsx).
import { useEffect, useMemo, useRef, useState } from 'react';
import { Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_AGRUPAR, ROTULO_PERIODO } from '../../domain/metricas';
import type { Funil, MetricaKey } from '../../domain/types';
import { InfoIndicador } from '../InfoIndicador';
import { VisualWidgetSvg } from '../inicio/Graficos';
import { calcularWidget, FOTOGRAFIA, type DadosPainel } from '../inicio/metricas-painel';
import {
  larguraPorArraste, pontoDeSoltura, solturaInocua, SPAN_GRADE, type Largura, type WidgetDash,
} from './layout';

/** O que está sendo arrastado agora (estado compartilhado entre biblioteca e grade). */
export type Arrasto = { tipo: 'metrica'; metrica: MetricaKey } | { tipo: 'widget'; id: string } | null;

/** Altura alta: estica os gráficos de Graficos.tsx sem mexer neles (seletores de descendente). */
const ALTURA_VISUAL = { normal: '', alta: 'min-h-[300px] [&_figure_svg]:h-[260px] [&_.-rotate-90]:h-[176px] [&_.-rotate-90]:w-[176px]' };

export interface AcoesGrade {
  selecionar: (id: string) => void;
  mover: (id: string, delta: number) => void;
  soltarWidget: (id: string, ponto: number) => void;
  soltarMetrica: (m: MetricaKey, ponto: number) => void;
  largura: (id: string, lg: Largura, continuo: boolean) => void;
  fimLargura: () => void;
  duplicar: (id: string) => void;
  remover: (id: string) => void;
  pedirMoverPara: (id: string) => void;
}

export function GradeDash({ widgets, dadosPara, funis, nomeDe, edicao }: {
  widgets: WidgetDash[];
  dadosPara: (vendedorId: string | null | undefined) => DadosPainel;
  funis: Funil[];
  nomeDe: (id: string | null) => string;
  /** Sem `edicao`, só visualização. */
  edicao?: {
    selecionado: string | null;
    arrasto: Arrasto;
    setArrasto: (a: Arrasto) => void;
    /** Pedido de foco (novo objeto a cada pedido, mesmo para o mesmo widget). */
    focarId: { id: string; vez: number } | null;
    acoes: AcoesGrade;
  };
}) {
  const grade = useRef<HTMLUListElement>(null);
  const [ponto, setPonto] = useState<number | null>(null);
  const redimensionandoRef = useRef(false);
  const n = widgets.length;

  // Depois de mover pelo teclado, o foco segue o widget.
  const focarId = edicao?.focarId ?? null;
  useEffect(() => {
    if (!focarId) return;
    grade.current?.querySelector<HTMLElement>(`[data-widget="${focarId.id}"]`)?.focus();
  }, [focarId]);

  const deIndex = edicao?.arrasto?.tipo === 'widget' ? widgets.findIndex((w) => w.id === (edicao.arrasto as { id: string }).id) : null;
  const pontoVisivel = ponto != null && !solturaInocua(deIndex, ponto) ? ponto : null;

  const soltar = (p: number) => {
    const a = edicao?.arrasto;
    if (!edicao || !a) return;
    if (a.tipo === 'metrica') edicao.acoes.soltarMetrica(a.metrica, p);
    else edicao.acoes.soltarWidget(a.id, p);
    edicao.setArrasto(null);
    setPonto(null);
  };

  const sobre = (e: React.DragEvent, i: number) => {
    if (!edicao?.arrasto) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = edicao.arrasto.tipo === 'metrica' ? 'copy' : 'move';
    const r = e.currentTarget.getBoundingClientRect();
    setPonto(pontoDeSoltura(i, e.clientX < r.left + r.width / 2 ? 'antes' : 'depois'));
  };

  return (
    <div className="@container min-w-0">
      <ul
        ref={grade}
        aria-label={edicao ? 'Widgets do dashboard (em edição)' : 'Widgets do dashboard'}
        className="grid grid-cols-1 @xl:grid-cols-6 @4xl:grid-cols-12 gap-4"
        onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setPonto(null); }}
      >
        {widgets.map((w, i) => (
          <li
            key={w.id}
            className={`relative min-w-0 ${SPAN_GRADE[w.largura]} ${edicao?.arrasto?.tipo === 'widget' && edicao.arrasto.id === w.id ? 'opacity-40' : ''}`}
            draggable={!!edicao}
            onDragStart={edicao ? (e) => {
              // Começou na alça de largura: não é arrastar o widget.
              if (redimensionandoRef.current) { e.preventDefault(); return; }
              e.dataTransfer.effectAllowed = 'move';
              e.dataTransfer.setData('text/plain', w.titulo);
              edicao.setArrasto({ tipo: 'widget', id: w.id });
            } : undefined}
            onDragEnd={edicao ? () => { edicao.setArrasto(null); setPonto(null); } : undefined}
            onDragOver={edicao ? (e) => sobre(e, i) : undefined}
            onDrop={edicao ? (e) => { e.preventDefault(); if (ponto != null) soltar(ponto); } : undefined}
          >
            {pontoVisivel === i && <Indicador lado="antes" />}
            {pontoVisivel === n && i === n - 1 && <Indicador lado="depois" />}
            <CartaoDash
              w={w} dados={dadosPara(w.vendedorId)} funis={funis} nomeDe={nomeDe}
              edicao={edicao ? {
                selecionado: edicao.selecionado === w.id, primeiro: i === 0, ultimo: i === n - 1, acoes: edicao.acoes,
                larguraGrade: () => grade.current?.clientWidth ?? 0, redimensionandoRef,
              } : undefined}
            />
          </li>
        ))}
        {edicao && (
          <li
            className="min-w-0 @xl:col-span-6 @4xl:col-span-12"
            onDragOver={(e) => { if (!edicao.arrasto) return; e.preventDefault(); setPonto(n); }}
            onDrop={(e) => { e.preventDefault(); soltar(n); }}
          >
            <div className={`grid place-items-center rounded-[var(--r-lg)] border-2 border-dashed px-4 text-center transition-colors ${n ? 'min-h-[84px]' : 'min-h-[260px]'} ${
              edicao.arrasto ? (pontoVisivel === n ? 'border-[var(--accent)] bg-[var(--surface-3)]' : 'border-[var(--border-strong)]') : 'border-[var(--border)]'
            }`}>
              <div>
                <Icon name={n ? 'plus' : 'dashboard'} size={n ? 18 : 28} className="mx-auto text-[var(--fg-3)]" />
                <p className={`mt-1.5 font-medium text-[var(--fg-2)] ${n ? 'text-xs' : 'text-sm'}`}>
                  {n ? 'Solte aqui para colocar no fim' : 'Arraste uma métrica para cá'}
                </p>
                {!n && (
                  <p className="mt-1 max-w-sm text-xs text-[var(--fg-3)]">
                    Escolha na biblioteca à esquerda e arraste, ou clique nela para adicionar. Depois arraste para reordenar e puxe a borda direita para mudar a largura.
                  </p>
                )}
              </div>
            </div>
          </li>
        )}
      </ul>
    </div>
  );
}

function Indicador({ lado }: { lado: 'antes' | 'depois' }) {
  return (
    <span aria-hidden className={`pointer-events-none absolute top-0 bottom-0 z-10 w-1 rounded-full bg-[var(--accent)] ${lado === 'antes' ? '-left-2.5' : '-right-2.5'}`} />
  );
}

function CartaoDash({ w, dados, funis, nomeDe, edicao }: {
  w: WidgetDash; dados: DadosPainel; funis: Funil[]; nomeDe: (id: string | null) => string;
  edicao?: {
    selecionado: boolean; primeiro: boolean; ultimo: boolean; acoes: AcoesGrade;
    larguraGrade: () => number; redimensionandoRef: React.MutableRefObject<boolean>;
  };
}) {
  const serie = useMemo(() => calcularWidget(w, dados), [w, dados]);
  const funil = w.funilId ? funis.find((f) => f.id === w.funilId)?.nome ?? 'Funil arquivado' : null;
  const contexto = [
    FOTOGRAFIA.has(w.metrica) ? 'Agora' : ROTULO_PERIODO[w.periodo],
    w.agrupar !== 'nenhum' ? ROTULO_AGRUPAR[w.agrupar].toLowerCase() : null,
    funil,
    w.vendedorId ? nomeDe(w.vendedorId) : null,
  ].filter(Boolean).join(' · ');
  const titulo = w.titulo.trim() || 'Sem título';

  const teclar = (e: React.KeyboardEvent) => {
    if (!edicao || e.target !== e.currentTarget) return;
    const { acoes } = edicao;
    const delta = e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : 0;
    if (delta) { e.preventDefault(); acoes.mover(w.id, delta); return; }
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); acoes.selecionar(w.id); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); acoes.remover(w.id); }
  };

  return (
    <Card
      data-widget={w.id}
      tabIndex={edicao ? 0 : undefined}
      role={edicao ? 'group' : undefined}
      aria-label={edicao ? `${titulo}. Setas movem, Enter edita, Delete remove.` : undefined}
      aria-current={edicao?.selecionado ? 'true' : undefined}
      onKeyDown={edicao ? teclar : undefined}
      onClick={edicao ? () => edicao.acoes.selecionar(w.id) : undefined}
      className={`relative h-full p-4 flex flex-col gap-3 ${ALTURA_VISUAL[w.altura ?? 'normal']} ${
        edicao ? `select-none cursor-grab active:cursor-grabbing outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] ${
          edicao.selecionado ? 'border-[var(--border-accent)]' : 'border-dashed hover:border-[var(--border-strong)]'
        }` : ''
      }`}
    >
      <div className="flex items-start justify-between gap-2 min-w-0">
        <div className="min-w-0">
          <h3 className="flex items-center gap-1 text-sm font-semibold text-[var(--fg)] min-w-0">
            {edicao && <Icon name="menu" size={13} className="shrink-0 text-[var(--fg-4)]" />}
            <span className="truncate">{titulo}</span>
            <InfoIndicador metrica={w.metrica} className="shrink-0" />
          </h3>
          <p className="text-[11px] text-[var(--fg-3)] truncate">{contexto}</p>
        </div>
        {edicao && <MenuWidget w={w} primeiro={edicao.primeiro} ultimo={edicao.ultimo} acoes={edicao.acoes} />}
      </div>
      <div className="flex-1 min-w-0 flex flex-col justify-center">
        <VisualWidgetSvg visual={w.visual} serie={serie} metrica={w.metrica} />
      </div>
      {edicao && (
        <AlcaLargura
          w={w} titulo={titulo} acoes={edicao.acoes} larguraGrade={edicao.larguraGrade} redimensionandoRef={edicao.redimensionandoRef}
        />
      )}
    </Card>
  );
}

/** Alça na borda direita: arrastar muda a largura em quartos; setas fazem o mesmo pelo teclado. */
function AlcaLargura({ w, titulo, acoes, larguraGrade, redimensionandoRef }: {
  w: WidgetDash; titulo: string; acoes: AcoesGrade; larguraGrade: () => number; redimensionandoRef: React.MutableRefObject<boolean>;
}) {
  const inicio = useRef<{ x: number; lg: Largura; grade: number } | null>(null);

  const fim = (e: React.PointerEvent) => {
    if (!inicio.current) return;
    inicio.current = null;
    redimensionandoRef.current = false;
    e.currentTarget.releasePointerCapture?.(e.pointerId);
    acoes.fimLargura();
  };

  return (
    <span
      role="slider"
      tabIndex={0}
      aria-label={`Largura de ${titulo}`}
      aria-valuemin={1}
      aria-valuemax={4}
      aria-valuenow={w.largura}
      aria-valuetext={`${w.largura} de 4 quartos da linha`}
      title="Arraste para mudar a largura (ou use as setas)"
      draggable={false}
      onClick={(e) => e.stopPropagation()}
      onPointerDown={(e) => {
        e.stopPropagation();
        e.preventDefault();
        redimensionandoRef.current = true;
        inicio.current = { x: e.clientX, lg: w.largura, grade: larguraGrade() };
        e.currentTarget.setPointerCapture?.(e.pointerId);
      }}
      onPointerMove={(e) => {
        const i = inicio.current;
        if (!i) return;
        const lg = larguraPorArraste(i.lg, e.clientX - i.x, i.grade);
        if (lg !== w.largura) acoes.largura(w.id, lg, true);
      }}
      onPointerUp={fim}
      onPointerCancel={fim}
      onKeyDown={(e) => {
        const d = e.key === 'ArrowLeft' || e.key === 'ArrowDown' ? -1 : e.key === 'ArrowRight' || e.key === 'ArrowUp' ? 1 : 0;
        const alvo = e.key === 'Home' ? 1 : e.key === 'End' ? 4 : d ? w.largura + d : null;
        if (alvo == null) return;
        e.preventDefault();
        e.stopPropagation();
        if (alvo >= 1 && alvo <= 4 && alvo !== w.largura) acoes.largura(w.id, alvo as Largura, false);
      }}
      className="group absolute -right-1 top-1/2 -translate-y-1/2 z-10 grid h-12 w-3 cursor-ew-resize place-items-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]"
    >
      <span className="h-8 w-1 rounded-full bg-[var(--border-strong)] transition-colors group-hover:bg-[var(--accent)] group-focus-visible:bg-[var(--accent)]" />
    </span>
  );
}

/** Menu do widget: editar, duplicar, mover para…, remover. Setas navegam, Esc fecha. */
function MenuWidget({ w, primeiro, ultimo, acoes }: { w: WidgetDash; primeiro: boolean; ultimo: boolean; acoes: AcoesGrade }) {
  const [aberto, setAberto] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  const botao = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!aberto) return;
    caixa.current?.querySelector<HTMLButtonElement>('[role="menuitem"]:not([disabled])')?.focus();
    const fora = (e: MouseEvent) => { if (!caixa.current?.contains(e.target as Node) && !botao.current?.contains(e.target as Node)) setAberto(false); };
    document.addEventListener('mousedown', fora);
    return () => document.removeEventListener('mousedown', fora);
  }, [aberto]);

  const fechar = () => { setAberto(false); botao.current?.focus(); };
  const item = (rotulo: string, icone: string, f: () => void, opts: { perigo?: boolean; disabled?: boolean } = {}) => (
    <button
      type="button" role="menuitem" disabled={opts.disabled}
      onClick={(e) => { e.stopPropagation(); setAberto(false); f(); }}
      className={`flex w-full items-center gap-2 rounded-[var(--r-sm)] px-2.5 py-1.5 text-left text-xs outline-none disabled:opacity-40 ${
        opts.perigo ? 'text-[var(--red)] hover:bg-[var(--red-subtle)] focus:bg-[var(--red-subtle)]' : 'text-[var(--fg-2)] hover:bg-[var(--surface-3)] focus:bg-[var(--surface-3)] hover:text-[var(--fg)]'
      }`}
    >
      <Icon name={icone} size={13} /> {rotulo}
    </button>
  );

  const navegar = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); fechar(); return; }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    e.preventDefault();
    e.stopPropagation();
    const itens = [...(caixa.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not([disabled])') ?? [])];
    const i = itens.indexOf(document.activeElement as HTMLButtonElement);
    itens[(i + (e.key === 'ArrowDown' ? 1 : -1) + itens.length) % itens.length]?.focus();
  };

  return (
    <div className="relative shrink-0" draggable={false} onKeyDown={(e) => e.stopPropagation()}>
      <button
        ref={botao} type="button" aria-haspopup="menu" aria-expanded={aberto} aria-label={`Ações de ${w.titulo || 'widget'}`}
        onClick={(e) => { e.stopPropagation(); setAberto((a) => !a); }}
        className="grid place-items-center w-7 h-7 rounded-[var(--r-sm)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
      >
        <Icon name="sliders" size={14} />
      </button>
      {aberto && (
        <div
          ref={caixa} role="menu" aria-label={`Ações de ${w.titulo || 'widget'}`} onKeyDown={navegar}
          className="absolute right-0 top-8 z-30 w-48 rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-1 shadow-[var(--shadow-lg)]"
        >
          {item('Editar propriedades', 'pencil', () => acoes.selecionar(w.id))}
          {item('Duplicar', 'copy', () => acoes.duplicar(w.id))}
          {item('Mover para…', 'arrow-right', () => acoes.pedirMoverPara(w.id), { disabled: primeiro && ultimo })}
          {item('Mover para trás', 'arrow-left', () => acoes.mover(w.id, -1), { disabled: primeiro })}
          {item('Mover para frente', 'arrow-right', () => acoes.mover(w.id, 1), { disabled: ultimo })}
          <div className="my-1 border-t border-[var(--border-faint)]" />
          {item('Remover', 'trash', () => acoes.remover(w.id), { perigo: true })}
        </div>
      )}
    </div>
  );
}
