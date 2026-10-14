'use client';

// Peças pequenas do dashboard da Black: número com "Sem dado" (nunca zero por falta), taxa com numerador e
// denominador na dica, farol da régua do Caio, contador animado (molde ValorAnimado do Histórico do ATM) e o
// hook de movimento reduzido. Só tokens de cor.
import { useEffect, useState, useSyncExternalStore, type ReactNode } from 'react';
import type { Farol as TipoFarol, Taxa as TipoTaxa } from '../domain/metricas';
import type { FormatoMetrica } from '../domain/jornada';
import { avaliarFaixa, avaliarMeta, distanciaDaMeta } from '../domain/meta';
import type { Valor } from '../domain/tipos';

const CONSULTA_MOVIMENTO = '(prefers-reduced-motion: reduce)';
function assinarMovimento(cb: () => void) {
  const mq = window.matchMedia(CONSULTA_MOVIMENTO);
  mq.addEventListener('change', cb);
  return () => mq.removeEventListener('change', cb);
}

/** true quando o sistema pede menos movimento (no servidor, true: nada anima antes de hidratar). */
export function usePrefereMenosMovimento(): boolean {
  return useSyncExternalStore(assinarMovimento, () => window.matchMedia(CONSULTA_MOVIMENTO).matches, () => true);
}

const INTEIRO = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const MOEDA = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const DECIMAL = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const PCT = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 });

export const SEM_DADO = 'Sem dado';

/** Até 1320 px o rótulo com `truncate` (KpiCard e listas) quebra linha em vez de cortar: nome é string exata da fonte. */
export const ROTULO_INTEIRO = 'max-[1320px]:[&_.truncate]:overflow-visible max-[1320px]:[&_.truncate]:whitespace-normal max-[1320px]:[&_.truncate]:break-words';
/** Somado ao `width` do Modal: abaixo de 768 px o modal ocupa a tela inteira (o centro do overlay absorve o respiro de 16 px). */
export const MODAL_TELA_CHEIA = 'max-md:max-h-[calc(100dvh-2rem)] max-md:w-[calc(100vw-2rem)] max-md:max-w-none max-md:shrink-0';

/** Formata um valor. Taxas chegam como fração (0,123 = 12,3%). null = "Sem dado". */
export function formatar(v: Valor, formato: FormatoMetrica): string {
  if (v === null || !Number.isFinite(v)) return SEM_DADO;
  if (formato === 'brl') return MOEDA.format(v);
  if (formato === 'pct') return `${PCT.format(v * 100)}%`;
  if (formato === 'dec') return DECIMAL.format(v);
  return INTEIRO.format(v);
}
export const inteiro = (v: Valor) => formatar(v, 'int');
export const moeda = (v: Valor) => formatar(v, 'brl');
export const pct = (v: Valor) => formatar(v, 'pct');

/** Texto da dica de uma taxa: "123 ÷ 1.000" + nota. */
export function dicaTaxa(t: TipoTaxa, formatoNum: FormatoMetrica = 'int', formatoDen: FormatoMetrica = 'int'): string {
  const conta = t.num === null || t.den === null ? 'Sem dado para a conta' : `${formatar(t.num, formatoNum)} ÷ ${formatar(t.den, formatoDen)}`;
  return t.nota ? `${conta}. ${t.nota}` : conta;
}

/** Contador animado de 0 ao valor em 620 ms (easing 1-(1-t)^3). Sem animação com movimento reduzido. */
export function ContadorAnimado({ valor, formato }: { valor: Valor; formato: FormatoMetrica }) {
  const menos = usePrefereMenosMovimento();
  const [progresso, setProgresso] = useState(1);
  useEffect(() => {
    if (valor === null || valor === 0 || menos) return;
    const inicio = performance.now();
    let frame = 0;
    const animar = (agora: number) => {
      const t = Math.min(1, (agora - inicio) / 620);
      setProgresso(1 - (1 - t) ** 3);
      if (t < 1) frame = requestAnimationFrame(animar);
    };
    frame = requestAnimationFrame(animar);
    return () => cancelAnimationFrame(frame);
  }, [valor, menos]);
  return <>{formatar(valor === null ? null : valor * (menos ? 1 : progresso), formato)}</>;
}

/**
 * Número da tela. null vira "Sem dado" tracejado, com a fonte que falta na dica. Zero medido aparece como zero.
 */
export function Numero({ valor, formato, falta, animado = true, className = '' }: {
  valor: Valor; formato: FormatoMetrica; falta?: string; animado?: boolean; className?: string;
}) {
  if (valor === null) {
    return <span title={falta ? `Sem dado: ${falta}` : 'Sem dado'} className={'inline-block rounded-[var(--r-sm)] border border-dashed border-[var(--border-strong)] px-1.5 text-[var(--fg-3)] ' + className}>{SEM_DADO}</span>;
  }
  return <span className={'tabular ' + className}>{animado ? <ContadorAnimado valor={valor} formato={formato} /> : formatar(valor, formato)}</span>;
}

/** Taxa com numerador e denominador na dica (title e texto para leitor de tela). */
export function Taxa({ taxa, formatoNum = 'int', formatoDen = 'int', className = '' }: {
  taxa: TipoTaxa; formatoNum?: FormatoMetrica; formatoDen?: FormatoMetrica; className?: string;
}) {
  const dica = dicaTaxa(taxa, formatoNum, formatoDen);
  if (taxa.valor === null) return <span title={dica} className={'inline-block rounded-[var(--r-sm)] border border-dashed border-[var(--border-strong)] px-1.5 text-[var(--fg-3)] ' + className}>{SEM_DADO}<span className="sr-only"> ({dica})</span></span>;
  return <span title={dica} className={'tabular underline decoration-dotted decoration-[var(--fg-3)] underline-offset-2 ' + className}>{pct(taxa.valor)}<span className="sr-only"> ({dica})</span></span>;
}

const COR_FAROL: Record<TipoFarol, string> = { verde: 'var(--green)', amarelo: 'var(--yellow)', vermelho: 'var(--red)', sem: 'var(--fg-3)' };
const TEXTO_FAROL: Record<TipoFarol, string> = { verde: 'dentro da meta', amarelo: 'entre a meta e o teto', vermelho: 'acima do teto', sem: 'sem farol' };

/** Farol da régua do Caio (CPL meta R$ 15, teto R$ 20). */
export function Farol({ farol, className = '' }: { farol: TipoFarol; className?: string }) {
  return <span className={'inline-flex items-center gap-1 ' + className} title={`Farol: ${TEXTO_FAROL[farol]}`}>
    <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: COR_FAROL[farol] }} />
    <span className="sr-only">Farol: {TEXTO_FAROL[farol]}</span>
  </span>;
}
export const corFarol = (f: TipoFarol) => COR_FAROL[f];

/**
 * Indicador de meta de um card com fórmula: bolinha + "Bom"/"Atenção"/"Ruim" + % da meta + a meta. A cor nunca vai sozinha (o
 * texto diz o estado). Sem valor ou sem meta, mostra "Sem meta" em vez de sumir.
 */
export function IndicadorMeta({ valor, meta, ideal, menorMelhor = false, formato, className = '', compacto = false }: {
  valor: Valor; meta: Valor; /** Com `ideal`, vira faixa de duas linhas (ideal e `meta` como limite); só para menor-melhor. */ ideal?: Valor;
  menorMelhor?: boolean; formato: FormatoMetrica; className?: string; compacto?: boolean;
}) {
  const faixa = ideal !== undefined;
  const a = faixa ? avaliarFaixa(valor, ideal, meta) : avaliarMeta(valor, meta, menorMelhor);
  if (a.estado === 'sem') {
    const motivo = meta === null ? 'Sem meta' : 'Sem dado para comparar';
    return <span className={'text-[11px] font-normal text-[var(--fg-3)] ' + className}>{motivo}</span>;
  }
  const rotulo = a.estado === 'bom' ? 'Bom' : a.estado === 'atencao' ? 'Atenção' : 'Ruim';
  const cor = a.estado === 'bom' ? 'var(--green)' : a.estado === 'atencao' ? 'var(--yellow)' : 'var(--red)';
  const pctMeta = distanciaDaMeta(a.pctDaMeta) ?? 'sem comparação';
  const dica = `${rotulo}: ${formatar(valor, formato)} contra ${faixa ? `ideal de ${formatar(ideal, formato)} e limite de ${formatar(meta, formato)}` : `meta de ${formatar(meta, formato)}`} (${pctMeta}). ${menorMelhor || faixa ? 'Quanto menor, melhor.' : 'Quanto maior, melhor.'}`;
  return (
    <span title={dica} className={'inline-flex flex-wrap items-center gap-x-1.5 text-[11px] font-normal text-[var(--fg-2)] ' + className}>
      <span aria-hidden="true" className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: cor }} />
      <span className="font-semibold text-[var(--fg)]">{rotulo}</span>
      <span>{pctMeta}</span>
      {!compacto && <span className="text-[var(--fg-3)]">{faixa ? `· ideal ${formatar(ideal, formato)}, máx. ${formatar(meta, formato)}` : `· meta ${formatar(meta, formato)}`}</span>}
    </span>
  );
}

/** Selo de dado fictício (modo demonstração e mensageria sem fonte real). */
export function SeloFicticio({ children = 'dado fictício' }: { children?: ReactNode }) {
  return <span className="inline-flex items-center rounded-full border border-[var(--yellow)]/50 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-[var(--yellow)]">{children}</span>;
}

/** Aviso de bloco que falhou: segura o último valor, esmaece e mostra a idade. */
export function AvisoBloco({ erro, lidoEm, agora }: { erro: string | null; lidoEm: Date | null; agora: Date }) {
  if (!erro) return null;
  const idade = lidoEm ? Math.max(0, Math.round((agora.getTime() - lidoEm.getTime()) / 60_000)) : null;
  return <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-2 text-xs text-[var(--yellow)]">
    {erro}{idade !== null ? ` Mostrando a última leitura, de ${idade} min atrás.` : ' Sem leitura anterior.'}
  </p>;
}

/** Chip clicável com estado (filtros, ordem, sub-abas internas). */
export function Chip({ ativo, onClick, children, title }: { ativo: boolean; onClick: () => void; children: ReactNode; title?: string }) {
  return <button type="button" aria-pressed={ativo} title={title} onClick={onClick}
    className={'min-h-9 rounded-full border px-3 py-1 text-xs transition-colors ' + (ativo ? 'border-[var(--accent)] bg-[var(--accent)] font-semibold text-black' : 'border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg-2)] hover:text-[var(--fg)]')}>
    {children}
  </button>;
}
