'use client';

// Peças pequenas reaproveitadas pelas telas do Comercial.
// Regra da casa: se uma peça aparece em duas telas, ela mora aqui (cabeçalho, números,
// aviso, campo, segmentado, chip, estados de carga/erro/vazio). Âmbar só para seleção/ação.
import Link from 'next/link';
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { AvatarInicial, Badge, Button, EmptyState, FilterSelect, Loading, Skeleton, type Tone } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { produto } from '../domain/catalogo';
import { situacaoSla, tempoNaEtapa, type SituacaoSla } from '../domain/regras';
import type { MetricaKey, Negocio, ProdutoKey, SessaoComercial, Vendedor } from '../domain/types';
import { InfoIndicador, type TextoIndicador } from './InfoIndicador';
import { SinoNotificacoes } from './notificacoes/SinoNotificacoes';
import { avisarMudanca, MODO_DEMONSTRACAO, repo, useDados } from './repositorio';

// ─────────────────────────────────────────────────────────────────────────────
// Cabeçalho
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Cabeçalho padrão das telas do Comercial: h1 + 1 linha factual + ações à direita.
 * `meta` (opcional) fica logo abaixo, alinhado ao cabeçalho: lugar da FaixaNumeros.
 * `cheia` (opcional) faz o conteúdo ocupar a altura que sobrar (kanban, conversas):
 * sem altura mágica dependendo do aviso de demonstração existir ou não.
 */
export function PaginaComercial({ titulo, subtitulo, acoes, meta, cheia = false, children }: {
  titulo: React.ReactNode; subtitulo?: React.ReactNode; acoes?: React.ReactNode;
  meta?: React.ReactNode; cheia?: boolean; children: React.ReactNode;
}) {
  return (
    <div className={`min-w-0 ${cheia ? 'flex flex-col h-full min-h-0' : ''}`}>
      {MODO_DEMONSTRACAO && <AvisoDemonstracao />}
      <header className="mb-4 shrink-0">
        <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
          <div className="min-w-0 flex-1">
            <h1 className="text-xl font-bold leading-tight text-[var(--fg)] truncate">{titulo}</h1>
            {subtitulo && <p className="mt-0.5 text-sm text-[var(--fg-3)] truncate max-w-[90ch]">{subtitulo}</p>}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {acoes}
            <SeloSomenteLeitura />
            <SinoNotificacoes />
          </div>
        </div>
        {meta && <div className="mt-3">{meta}</div>}
      </header>
      {cheia ? <div className="flex-1 min-h-0 flex flex-col">{children}</div> : children}
    </div>
  );
}

/** Selo discreto para o leitor (admin/dev fora do Comercial, 20261008151801): vê tudo, não altera nada. */
function SeloSomenteLeitura() {
  const { dados: sessao } = useDados(() => repo.sessao());
  if (sessao?.papel !== 'leitor') return null;
  return (
    <span title="Você vê o Comercial inteiro, com e-mail e telefone mascarados, mas não altera nada.">
      <Badge>Somente leitura</Badge>
    </span>
  );
}

// Aviso de demonstração dispensável por sessão (sessionStorage pode falhar: aba privada, bloqueio).
const CHAVE_DEMO = 'gp_comercial_demo_oculto';
const ouvintesDemo = new Set<() => void>();
function lerDemoOculto(): boolean {
  try { return window.sessionStorage.getItem(CHAVE_DEMO) === '1'; } catch { return false; }
}
function gravarDemoOculto(v: boolean) {
  try {
    if (v) window.sessionStorage.setItem(CHAVE_DEMO, '1');
    else window.sessionStorage.removeItem(CHAVE_DEMO);
  } catch { /* sem storage: vale só até recarregar */ }
  ouvintesDemo.forEach((f) => f());
}
let demoOcultoMemoria = false;
function useDemoOculto(): [boolean, (v: boolean) => void] {
  const oculto = useSyncExternalStore(
    (cb) => { ouvintesDemo.add(cb); return () => { ouvintesDemo.delete(cb); }; },
    () => demoOcultoMemoria || lerDemoOculto(),
    () => false,
  );
  return [oculto, (v) => { demoOcultoMemoria = v; gravarDemoOculto(v); }];
}

/** Faixa neutra fina: "Demonstração · dados fictícios" + "Ver como". Nada de âmbar. */
function AvisoDemonstracao() {
  const [oculto, setOculto] = useDemoOculto();
  const { dados: vendedores } = useDados(() => repo.vendedores());
  const { dados: sessao } = useDados(() => repo.sessao());
  if (oculto) {
    return (
      <div className="mb-2 flex justify-end">
        <button type="button" onClick={() => setOculto(false)} className="text-[11px] text-[var(--fg-3)] hover:text-[var(--fg-2)] hover:underline">
          Demonstração · ver como…
        </button>
      </div>
    );
  }
  return (
    <div className="mb-4 flex flex-wrap items-center justify-between gap-x-3 gap-y-1 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-1 text-xs text-[var(--fg-3)] min-h-9 shadow-[var(--highlight-surface)]">
      <span className="inline-flex items-center gap-2 min-w-0">
        <Icon name="eye" size={14} className="shrink-0 text-[var(--fg-3)]" />
        <span className="truncate" title="Pessoas fictícias; nada aqui grava no banco. O backend entra depois.">
          Demonstração · dados fictícios
        </span>
      </span>
      <span className="inline-flex items-center gap-2">
        {repo.verComo && vendedores && sessao && (
          <label className="inline-flex items-center gap-2">
            <span>Ver como</span>
            <FilterSelect
              value={sessao.vendedorId}
              onChange={async (e) => { await repo.verComo!(e.target.value); avisarMudanca(); }}
              className="!py-1 !text-xs min-w-[180px]"
            >
              {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome} ({v.papel})</option>)}
            </FilterSelect>
          </label>
        )}
        <button
          type="button"
          onClick={() => setOculto(true)}
          aria-label="Esconder aviso de demonstração nesta sessão"
          title="Esconder nesta sessão"
          className="grid place-items-center w-8 h-8 rounded-[var(--r-sm)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
        >
          <Icon name="x" size={14} />
        </button>
      </span>
    </div>
  );
}

/** Regras do playbook num botão só, no cabeçalho (em vez de slogan no subtítulo). */
export function BotaoPlaybook({ regras, titulo = 'Playbook' }: { regras: React.ReactNode[]; titulo?: string }) {
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setAberto(false); };
    document.addEventListener('mousedown', fora);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc); };
  }, [aberto]);
  return (
    <div ref={ref} className="relative">
      <Button size="sm" variant="ghost" aria-expanded={aberto} onClick={() => setAberto((a) => !a)}>
        <Icon name="notebook" size={14} /> {titulo}
      </Button>
      {aberto && (
        <div role="dialog" aria-label={titulo} className="gp-pop-in origin-top-right absolute right-0 z-30 mt-1 w-[min(320px,calc(100vw-32px))] rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] p-3 shadow-[var(--highlight-surface),var(--shadow-lg)]">
          <ul className="space-y-2 text-xs leading-relaxed text-[var(--fg-2)]">
            {regras.map((r, i) => (
              <li key={i} className="flex gap-2">
                <span className="tabular text-[var(--fg-3)] shrink-0">{i + 1}.</span><span>{r}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Números (faixa compacta, nunca grade de KpiCards)
// ─────────────────────────────────────────────────────────────────────────────

export interface ItemNumero {
  rotulo: string;
  valor: React.ReactNode;
  /** Viola meta (ex.: meta-zero > 0): valor em vermelho e escrito no title. */
  alerta?: boolean;
  /** Número com filtro correspondente: clicar aplica o filtro. */
  onClick?: () => void;
  /** Filtro do número está aplicado. */
  ativo?: boolean;
  /** Definição exata do indicador. */
  title?: string;
  /** Texto extra só para leitor de tela (ex.: o número do time). */
  extraSr?: string;
  /** Mostra o ícone (i) com a definição do indicador (domain/metricas.ts). */
  metrica?: MetricaKey;
  /** Definição própria, para indicador que não está em domain/metricas.ts. */
  info?: TextoIndicador;
}

/**
 * Até 5 números numa barra só (~40px). Cor só quando viola meta.
 * `onLimpar` mostra "Limpar" quando algum número filtra; `discreta` tira a caixa (ao lado de filtros).
 */
export function FaixaNumeros({ itens, rotulo, onLimpar, discreta = false, className = '' }: {
  itens: ItemNumero[]; rotulo?: string; onLimpar?: () => void; discreta?: boolean; className?: string;
}) {
  const algumAtivo = itens.some((i) => i.ativo);
  const caixa = discreta ? '' : 'min-h-10 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]';
  return (
    <div role="group" aria-label={rotulo} className={`flex flex-wrap items-stretch ${caixa} ${discreta ? '' : 'shadow-[var(--highlight-surface),var(--shadow-xs)]'} ${className}`}>
      {itens.slice(0, 5).map((it, i) => {
        const conteudo = (
          <>
            <span className="text-xs text-[var(--fg-3)] whitespace-nowrap">{it.rotulo}</span>
            <span className={`text-sm font-semibold tabular whitespace-nowrap ${it.alerta ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{it.valor}</span>
            {it.alerta && <span className="sr-only">(fora da meta)</span>}
            {it.extraSr && <span className="sr-only">({it.extraSr})</span>}
          </>
        );
        const base = `inline-flex items-center gap-2 shrink-0 ${discreta ? 'px-2 py-1 rounded-[var(--r-sm)]' : 'px-3 py-2'} ${i > 0 && !discreta ? 'border-l border-[var(--border-faint)]' : ''}`;
        const title = it.title ?? (it.alerta ? `${it.rotulo}: fora da meta` : undefined);
        const info = (it.metrica || it.info) ? <InfoIndicador metrica={it.metrica} texto={it.info} className="-ml-1" /> : null;
        if (info) {
          // Com (i): o número e o ícone ficam lado a lado (botão dentro de botão não pode).
          return (
            <span key={it.rotulo} className={`${base} !gap-1`}>
              {it.onClick ? (
                <button type="button" onClick={it.onClick} aria-pressed={!!it.ativo} title={title ?? `Filtrar: ${it.rotulo}`}
                  className={`inline-flex items-center gap-2 rounded-[var(--r-sm)] -mx-1 px-1 transition-colors ${it.ativo ? 'bg-[var(--surface-4)]' : 'hover:bg-[var(--surface-3)]'}`}>
                  {conteudo}
                </button>
              ) : <span className="inline-flex items-center gap-2" title={title}>{conteudo}</span>}
              {info}
            </span>
          );
        }
        return it.onClick ? (
          <button
            key={it.rotulo}
            type="button"
            onClick={it.onClick}
            aria-pressed={!!it.ativo}
            title={title ?? `Filtrar: ${it.rotulo}`}
            className={`${base} transition-colors ${it.ativo ? 'bg-[var(--surface-4)]' : 'hover:bg-[var(--surface-3)]'}`}
          >
            {conteudo}
          </button>
        ) : (
          <span key={it.rotulo} className={base} title={title}>{conteudo}</span>
        );
      })}
      {algumAtivo && onLimpar && (
        <button type="button" onClick={onLimpar} className="ml-auto inline-flex shrink-0 items-center gap-1 px-3 text-xs text-[var(--fg-2)] hover:text-[var(--fg)]">
          <Icon name="x" size={12} /> Limpar
        </button>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Aviso (um componente só para banner/alerta)
// ─────────────────────────────────────────────────────────────────────────────

export type TomAviso = 'neutral' | 'info' | 'warning' | 'danger' | 'success';

const ESTILO_AVISO: Record<TomAviso, { caixa: string; icone: string; padrao: string }> = {
  neutral: { caixa: 'border-[var(--border)] bg-[var(--surface-2)]', icone: 'text-[var(--fg-3)]', padrao: 'eye' },
  info: { caixa: 'border-[var(--info-border)] bg-[var(--info-subtle)]', icone: 'text-[var(--info)]', padrao: 'message' },
  warning: { caixa: 'border-[var(--yellow-border)] bg-[var(--yellow-subtle)]', icone: 'text-[var(--yellow)]', padrao: 'alert' },
  danger: { caixa: 'border-[var(--red-border)] bg-[var(--red-subtle)]', icone: 'text-[var(--red)]', padrao: 'alert' },
  success: { caixa: 'border-[var(--green-border)] bg-[var(--green-subtle)]', icone: 'text-[var(--green)]', padrao: 'check-circle' },
};

/**
 * Aviso no ponto onde a regra bloqueia algo. Máximo 1 acima da dobra por tela.
 * `alerta` só para erro que acabou de acontecer (vira role="alert"); banner fixo não grita.
 */
export function Aviso({ tom = 'neutral', icone, titulo, children, acao, alerta = false, className = '' }: {
  tom?: TomAviso; icone?: string; titulo?: React.ReactNode; children?: React.ReactNode; acao?: React.ReactNode; alerta?: boolean; className?: string;
}) {
  const e = ESTILO_AVISO[tom];
  return (
    <div role={alerta ? 'alert' : undefined} className={`flex flex-wrap items-center gap-x-3 gap-y-2 rounded-[var(--r-md)] border px-3 py-2 text-sm text-[var(--fg-2)] ${e.caixa} ${className}`}>
      <span className="flex items-start gap-2 flex-1 min-w-[200px]">
        <Icon name={icone ?? e.padrao} size={15} className={`shrink-0 mt-0.5 ${e.icone}`} />
        <span className="min-w-0">
          {titulo && <span className="block font-semibold text-[var(--fg)]">{titulo}</span>}
          {children && <span className={titulo ? 'block text-xs leading-relaxed' : undefined}>{children}</span>}
        </span>
      </span>
      {acao && <span className="shrink-0 flex items-center gap-2">{acao}</span>}
    </div>
  );
}

/** Nota explicativa estática (rodapé de bloco). Não é aviso: não chama atenção. */
export function NotaRodape({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <p className={`text-[11px] leading-relaxed text-[var(--fg-3)] ${className}`}>{children}</p>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulário: Campo, Segmentado, Chip
// ─────────────────────────────────────────────────────────────────────────────

/** Rótulo + controle + dica. Um estilo só para todo formulário do Comercial. */
export function Campo({ rotulo, dica, extra, children, className = '' }: {
  rotulo: React.ReactNode;
  /** Texto curto abaixo do controle (formato, regra). */
  dica?: React.ReactNode;
  /** Marcação à direita do rótulo (ex.: "obrigatório", "para Proposta"). */
  extra?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <label className={`block min-w-0 ${className}`}>
      <span className="mb-1 flex items-center justify-between gap-2 text-xs font-medium text-[var(--fg-2)]">
        <span className="truncate">{rotulo}</span>
        {extra && <span className="shrink-0 text-[11px] font-normal">{extra}</span>}
      </span>
      {children}
      {dica && <span className="mt-1 block text-[11px] text-[var(--fg-3)]">{dica}</span>}
    </label>
  );
}

export interface OpcaoSegmentado<T extends string> {
  valor: T; rotulo: React.ReactNode; n?: number; title?: string;
  /** Contador viola meta (ex.: prazo crítico na etapa): vermelho. */
  alerta?: boolean;
}

/** Controle segmentado (radiogroup): ←/→/Home/End trocam a opção. Selecionado = surface-4 + fg. */
export function Segmentado<T extends string>({ opcoes, valor, onChange, rotulo, className = '' }: {
  opcoes: OpcaoSegmentado<T>[]; valor: T; onChange: (v: T) => void; rotulo: string; className?: string;
}) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const idx = Math.max(0, opcoes.findIndex((o) => o.valor === valor));
  const teclar = (e: React.KeyboardEvent, i: number) => {
    const n = opcoes.length;
    const j = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? (i + 1) % n
      : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? (i - 1 + n) % n
      : e.key === 'Home' ? 0 : e.key === 'End' ? n - 1 : null;
    if (j == null) return;
    e.preventDefault();
    refs.current[j]?.focus();
    onChange(opcoes[j].valor);
  };
  return (
    <div role="radiogroup" aria-label={rotulo} className={`inline-flex max-w-full overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-0.5 ${className}`}>
      {opcoes.map((o, i) => {
        const sel = i === idx;
        return (
          <button
            key={o.valor}
            ref={(el) => { refs.current[i] = el; }}
            type="button"
            role="radio"
            aria-checked={sel}
            tabIndex={sel ? 0 : -1}
            title={o.title}
            onClick={() => onChange(o.valor)}
            onKeyDown={(e) => teclar(e, i)}
            className={`gp-press inline-flex items-center gap-1.5 whitespace-nowrap rounded-[var(--r-sm)] px-3 min-h-8 text-xs ${
              sel ? 'bg-[var(--surface-4)] text-[var(--fg)] font-semibold shadow-[var(--highlight-surface),var(--shadow-xs)]' : 'text-[var(--fg-3)] hover:text-[var(--fg-2)] hover:bg-[var(--surface-3)]'
            }`}
          >
            {o.rotulo}
            {o.n != null && <span className={`tabular ${o.alerta ? 'text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>{o.n}</span>}
          </button>
        );
      })}
    </div>
  );
}

/** Chip selecionável (aria-pressed). Selecionado = borda âmbar (seleção) + surface-3. */
export function Chip({ ativo, onClick, children, icone, disabled, title, className = '' }: {
  ativo: boolean; onClick: () => void; children: React.ReactNode; icone?: string; disabled?: boolean; title?: string; className?: string;
}) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      disabled={disabled}
      title={title}
      onClick={onClick}
      className={`gp-press inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-3 min-h-8 text-xs disabled:opacity-50 disabled:cursor-not-allowed ${
        ativo ? 'border-[var(--border-accent)] bg-[var(--surface-3)] text-[var(--fg)] font-medium' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:border-[var(--border-strong)] hover:text-[var(--fg)]'
      } ${className}`}
    >
      {icone && <Icon name={icone} size={13} />}
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Estados: carregando / erro / vazio
// ─────────────────────────────────────────────────────────────────────────────

/** Erro de carga com "Tentar de novo" (sem isso a tela gira para sempre). */
export function EstadoErro({ mensagem, onTentar }: { mensagem?: string | null; onTentar?: () => void }) {
  return (
    <div role="alert">
      <EmptyState icon="alert" title="Não foi possível carregar" hint={mensagem ?? undefined} />
      {onTentar && (
        <div className="-mt-8 pb-12 flex justify-center">
          <Button size="sm" variant="ghost" onClick={onTentar}><Icon name="refresh" size={14} /> Tentar de novo</Button>
        </div>
      )}
    </div>
  );
}

/**
 * Erro ao ATUALIZAR com dado já na tela: faixa discreta em vez de sumir com a lista (o dado anterior continua à vista).
 * Para o erro da 1ª carga (sem dado nenhum) use `EstadoErro`.
 */
export function FaixaErroAtualizacao({ mensagem, onTentar, className = '' }: { mensagem?: string | null; onTentar: () => void; className?: string }) {
  return (
    <div
      role="alert"
      title={mensagem ?? undefined}
      className={`flex flex-wrap items-center gap-x-2 gap-y-1 rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-3 py-1.5 text-xs text-[var(--fg-2)] ${className}`}
    >
      <Icon name="alert" size={13} className="shrink-0 text-[var(--red)]" />
      <span>Não foi possível atualizar</span>
      <span aria-hidden="true">·</span>
      <button type="button" onClick={onTentar} className="font-semibold text-[var(--fg)] underline-offset-2 hover:underline">
        tentar de novo
      </button>
    </div>
  );
}

/** Vazio com o próximo passo ("Novo negócio", "Limpar filtros", "Agendar atividade"). */
export function Vazio({ titulo, hint, icone, acao }: { titulo: string; hint?: string; icone?: string; acao?: React.ReactNode }) {
  return (
    <div>
      <EmptyState title={titulo} hint={hint} icon={icone} />
      {acao && <div className="-mt-8 pb-12 flex flex-wrap justify-center gap-2">{acao}</div>}
    </div>
  );
}

/** Esqueleto de lista em linhas (para listas fora de tabela). */
export function EsqueletoLista({ linhas = 5, avatar = true }: { linhas?: number; avatar?: boolean }) {
  return (
    <div className="space-y-2" aria-busy="true" aria-label="Carregando">
      {Array.from({ length: linhas }).map((_, i) => (
        <div key={i} className="flex items-center gap-3 rounded-[var(--r-md)] border border-[var(--border-faint)] px-3 py-2">
          {avatar && <span className="gp-skeleton w-7 h-7 rounded-full shrink-0" />}
          <div className="flex-1 space-y-1.5">
            <Skeleton w="40%" h={12} />
            <Skeleton w="25%" h={10} />
          </div>
          <Skeleton w={64} h={12} />
        </div>
      ))}
    </div>
  );
}

type Carga = { dados: unknown; erro: string | null; recarregar: () => Promise<void> | void };

/**
 * Junta vários useDados num estado só:
 * `const est = combinarDados(rNegocios, rFunis); <Carregando {...est}>{([negocios, funis]) => …}</Carregando>`
 */
export function combinarDados<T extends readonly Carga[]>(...cargas: T): {
  dados: { [K in keyof T]: NonNullable<T[K]['dados']> } | null; erro: string | null; onTentar: () => void;
} {
  const erro = cargas.find((c) => c.erro)?.erro ?? null;
  const prontos = cargas.every((c) => c.dados != null);
  return {
    dados: prontos ? (cargas.map((c) => c.dados) as { [K in keyof T]: NonNullable<T[K]['dados']> }) : null,
    erro,
    onTentar: () => { cargas.forEach((c) => { void c.recarregar(); }); },
  };
}

/**
 * Estado de carga padrão: dado pronto → conteúdo; erro → EstadoErro com "Tentar de novo";
 * senão o esqueleto (no formato da lista) ou Loading.
 */
export function Carregando<T>({ dados, erro, onTentar, esqueleto, children }: {
  dados: T | null | undefined; erro?: string | null; onTentar?: () => void; esqueleto?: React.ReactNode;
  children: (d: T) => React.ReactNode;
}) {
  if (dados != null) return <>{children(dados)}</>;
  if (erro) return <EstadoErro mensagem={erro} onTentar={onTentar} />;
  return <>{esqueleto ?? <Loading />}</>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Equipe, pessoa, dono, SLA, produto
// ─────────────────────────────────────────────────────────────────────────────

/** Sessão + vendedores, carregados juntos (quase toda tela precisa dos dois). */
/**
 * `gestor` = PODE agir como gestor (ações). `verTudo` = vê a operação como o gestor (gestor ou leitor): use para
 * filtros/visões padrão. `leitor` (20261008151801) = admin/dev fora do Comercial, só leitura: esconda as ações.
 */
export function useEquipe(): {
  sessao: SessaoComercial | null; vendedores: Vendedor[]; nomeDe: (id: string | null) => string;
  gestor: boolean; verTudo: boolean; leitor: boolean;
} {
  const { dados: sessao } = useDados(() => repo.sessao());
  const { dados: vendedores } = useDados(() => repo.vendedores());
  const lista = vendedores ?? [];
  return {
    sessao,
    vendedores: lista,
    nomeDe: (id) => (id ? lista.find((v) => v.id === id)?.nome ?? '—' : 'Sem dono'),
    gestor: sessao?.papel === 'gestor',
    verTudo: sessao?.papel === 'gestor' || sessao?.papel === 'leitor',
    leitor: sessao?.papel === 'leitor',
  };
}

export const TOM_SLA: Record<SituacaoSla, Tone> = { ok: 'success', atencao: 'warning', critico: 'danger', sem_sla: 'neutral' };

const COR_TEXTO_SLA: Record<SituacaoSla, string> = {
  ok: 'text-[var(--fg-3)]', atencao: 'text-[var(--yellow)]', critico: 'text-[var(--red)]', sem_sla: 'text-[var(--fg-3)]',
};

/**
 * Tempo na etapa com o estado do prazo (5/15 min no primeiro contato etc.).
 * O estado vai escrito ("atenção", "crítico"), nunca só na cor.
 * `variante="texto"` para card/linha que já tem outro status (sem Badge a mais).
 */
export function SlaTag({ n, agora, variante = 'badge' }: {
  n: Pick<Negocio, 'etapa' | 'etapaDesde' | 'status'>; agora: Date; variante?: 'badge' | 'texto';
}) {
  const s = situacaoSla(n, agora);
  if (s === 'sem_sla') return null;
  const txt = tempoNaEtapa(n.etapaDesde, agora);
  const rotulo = s === 'critico' ? `${txt} · crítico` : s === 'atencao' ? `${txt} · atenção` : txt;
  const title = s === 'critico' ? 'Prazo crítico estourado' : s === 'atencao' ? 'Prazo de atenção estourado' : 'Dentro do prazo';
  if (variante === 'texto') {
    return (
      <span title={title} className={`inline-flex items-center gap-1 text-xs tabular whitespace-nowrap ${COR_TEXTO_SLA[s]} ${s === 'critico' ? 'font-semibold' : ''}`}>
        <Icon name="clock" size={12} /> {rotulo}
      </span>
    );
  }
  return <span title={title}><Badge tone={TOM_SLA[s]}>{rotulo}</Badge></span>;
}

/**
 * Produto: texto por padrão (é metadado, não status). Escada pelo ícone, não pela cor.
 * `variante="chip"` só onde o produto É a informação principal (ex.: vendas por produto).
 */
export function ProdutoTag({ k, variante = 'texto' }: { k: ProdutoKey; variante?: 'texto' | 'chip' }) {
  const p = produto(k);
  if (variante === 'chip') return <Badge>{p.nome}</Badge>;
  const escada = p.escada === 'A' ? 'Escada A (serviço)' : 'Escada B (formação)';
  return (
    <span className="inline-flex items-center gap-1 min-w-0 text-xs text-[var(--fg-2)]" title={`${p.nome} · ${escada}`}>
      <Icon name={p.escada === 'A' ? 'briefcase' : 'graduation'} size={12} className="shrink-0 text-[var(--fg-3)]" />
      <span className="truncate">{p.nome}</span>
    </span>
  );
}

/**
 * Avatar + nome + 1 linha (telefone ou e-mail). `flags` = ícones com title (duplicado, opt-out, aluno)
 * na mesma linha do nome, para a altura da linha não mudar. Com `onClick`/`href`, o nome vira
 * o alvo focável da linha (Tr onClick não é acessível por teclado).
 */
export function Pessoa({ nome, sub, size = 28, flags, onClick, href, rotuloAcao }: {
  nome: string; sub?: React.ReactNode; size?: number; flags?: React.ReactNode;
  onClick?: () => void; href?: string; rotuloAcao?: string;
}) {
  const clsNome = 'text-sm font-medium text-[var(--fg)] truncate';
  const nomeEl = href ? (
    <Link href={href} className={`${clsNome} hover:underline focus-visible:underline`} aria-label={rotuloAcao}>{nome}</Link>
  ) : onClick ? (
    <button
      type="button"
      onClick={(e) => { e.stopPropagation(); onClick(); }}
      className={`${clsNome} text-left hover:underline focus-visible:underline`}
      aria-label={rotuloAcao}
    >
      {nome}
    </button>
  ) : <span className={clsNome}>{nome}</span>;
  return (
    <div className="flex items-center gap-2.5 min-w-0">
      <AvatarInicial nome={nome} size={size} />
      <div className="min-w-0">
        <div className="flex items-center gap-1.5 min-w-0">
          {nomeEl}
          {flags && <span className="inline-flex items-center gap-1 shrink-0 text-[var(--fg-3)]">{flags}</span>}
        </div>
        {sub && <div className="text-xs text-[var(--fg-3)] truncate">{sub}</div>}
      </div>
    </div>
  );
}

/** Ícone de sinalização com rótulo (para `flags` da Pessoa): estado nunca só por cor. */
export function Sinal({ icone, rotulo, tom = 'neutral' }: { icone: string; rotulo: string; tom?: 'neutral' | 'danger' | 'warning' }) {
  const cor = tom === 'danger' ? 'text-[var(--red)]' : tom === 'warning' ? 'text-[var(--yellow)]' : 'text-[var(--fg-3)]';
  return (
    <span title={rotulo} className={`inline-flex ${cor}`}>
      <Icon name={icone} size={13} />
      <span className="sr-only">{rotulo}</span>
    </span>
  );
}

/** Rótulo de dono; "Sem dono" escrito em vermelho (a meta é zero), sem Badge a mais na linha. */
export function Dono({ id, nomeDe }: { id: string | null; nomeDe: (id: string | null) => string }) {
  if (!id) {
    return (
      <span className="inline-flex items-center gap-1 text-sm font-medium text-[var(--red)] whitespace-nowrap" title="Sem dono: a meta é zero">
        <Icon name="user-x" size={13} /> Sem dono
      </span>
    );
  }
  return <span className="text-sm text-[var(--fg-2)] truncate">{nomeDe(id)}</span>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ações rápidas de contato (1 clique, sem abrir ficha)
// ─────────────────────────────────────────────────────────────────────────────

const BTN_ICONE = 'inline-grid place-items-center w-8 h-8 rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors disabled:opacity-50 disabled:cursor-not-allowed';

/** Copia um texto (telefone) para a área de transferência. Confirma no próprio botão. */
export function BotaoCopiar({ texto, rotulo = 'Copiar telefone', onCopiado }: { texto: string | null | undefined; rotulo?: string; onCopiado?: (msg: string) => void }) {
  const [ok, setOk] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const copiar = async () => {
    if (!texto) return;
    try {
      await navigator.clipboard.writeText(texto);
      setOk(true);
      onCopiado?.('Copiado.');
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setOk(false), 1500);
    } catch {
      onCopiado?.('Não foi possível copiar.');
    }
  };
  return (
    <button type="button" onClick={copiar} disabled={!texto} className={BTN_ICONE} aria-label={ok ? 'Copiado' : rotulo} title={ok ? 'Copiado' : rotulo}>
      <Icon name={ok ? 'check' : 'copy'} size={14} />
    </button>
  );
}

/** Abre a conversa do contato na caixa do Comercial (navegação interna, sem recarregar). */
export function BotaoConversa({ contatoId, compacto = false }: { contatoId: string; compacto?: boolean }) {
  const href = `/comercial/conversas?contato=${encodeURIComponent(contatoId)}`;
  if (compacto) {
    return <Link href={href} className={BTN_ICONE} aria-label="Abrir conversa" title="Abrir conversa"><Icon name="message" size={14} /></Link>;
  }
  return (
    <Link
      href={href}
      className="inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"
    >
      <Icon name="message" size={14} /> Conversa
    </Link>
  );
}

/**
 * Rodapé de gaveta/modal com a ordem fixa da casa:
 * [destrutivo] ··· [secundário (ghost)] [primário]. Um primário só.
 */
export function RodapeAcoes({ perigo, secundario, primario }: { perigo?: React.ReactNode; secundario?: React.ReactNode; primario?: React.ReactNode }) {
  return (
    <>
      {perigo}
      <span className="flex-1" />
      {secundario}
      {primario}
    </>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// URL
// ─────────────────────────────────────────────────────────────────────────────

/** Abas por hash da URL (#funil, #origens…): a sidebar e links do Slack apontam direto para a aba. */
export function useAbaHash<T extends string>(validas: readonly T[], padrao: T): [T, (a: T) => void] {
  const [aba, setAba] = useState<T>(padrao);
  useEffect(() => {
    const ler = () => {
      const h = window.location.hash.replace('#', '') as T;
      setAba(validas.includes(h) ? h : padrao);
    };
    ler();
    window.addEventListener('hashchange', ler);
    return () => window.removeEventListener('hashchange', ler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const trocar = (a: T) => {
    window.history.replaceState(null, '', `#${a}`);
    setAba(a);
  };
  return [aba, trocar];
}

/** Lê ?param da URL uma vez (ex.: ?negocio=n-3 vindo de um alerta). */
export function useParamUrl(nome: string): string | null {
  const [v, setV] = useState<string | null>(null);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setV(new URLSearchParams(window.location.search).get(nome));
  }, [nome]);
  return v;
}
