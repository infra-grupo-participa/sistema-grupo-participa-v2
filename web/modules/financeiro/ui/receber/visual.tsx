// Vocabulário visual do Contas a Receber — o mesmo do Faturamento: número grande, verde quando é bom, vermelho quando
// pede ação, seta para cima/baixo na variação, e semana sem valor RASURADA (listras), nunca uma barra de altura zero que
// some da tela. Só desenho: recebe números já calculados pelo domínio; não consulta nada.
import type { ReactNode } from 'react';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtBRLc } from '@/shared/ui/format';
import { compacto, tetoRedondo } from '../hotmart/GraficoLinha';

export type TomFin = 'bom' | 'ruim' | 'atencao' | 'neutro';

const COR: Record<TomFin, string> = {
  bom: 'text-[var(--green)]', ruim: 'text-[var(--red)]', atencao: 'text-[var(--yellow)]', neutro: 'text-[var(--fg)]',
};
const BORDA: Record<TomFin, string> = {
  bom: 'border-[var(--green-border)]', ruim: 'border-[var(--red-border)]', atencao: 'border-[var(--yellow-border)]', neutro: 'border-[var(--border)]',
};

/** Listras diagonais: "aqui não entrou/não entra nada" — o mesmo gatilho do mês sem venda no Faturamento. */
const RASURA = 'repeating-linear-gradient(135deg, var(--border) 0 2px, transparent 2px 7px)';
export const RASURA_CSS = RASURA;

/** Uma linha dizendo PARA QUE SERVE a aba — quem abre sabe o que está vendo antes de ler o número. */
export function Intencao({ children }: { children: ReactNode }) {
  return (
    <p className="flex items-start gap-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2 text-xs text-[var(--fg-2)]">
      <Icon name="eye" size={13} className="mt-0.5 shrink-0 text-[var(--accent)]" />
      <span>{children}</span>
    </p>
  );
}

/** Seta + % contra o período anterior. Subir é bom (verde), cair é ruim (vermelho) — a menos que `inverso`.
 * `sufixo` troca a unidade (ex.: " p.p." para diferença de acerto). */
export function Seta({ pct, inverso = false, sufixo = '%' }: { pct: number | null; inverso?: boolean; sufixo?: string }) {
  if (pct == null || !Number.isFinite(pct)) return null;
  const subiu = pct >= 0;
  const bom = inverso ? !subiu : subiu;
  return (
    <span className={`inline-flex items-center gap-0.5 text-[11px] font-semibold tabular ${bom ? 'text-[var(--green)]' : 'text-[var(--red)]'}`}>
      <Icon name={subiu ? 'arrow-up' : 'arrow-down'} size={12} />
      {Math.abs(pct).toLocaleString('pt-BR', { maximumFractionDigits: sufixo === '%' ? 0 : 1 })}{sufixo}
      <span className="sr-only">{subiu ? ' a mais' : ' a menos'}</span>
    </span>
  );
}

/** Cor de cada tom como valor CSS (para `style`: barra, borda lateral). Só tokens. */
export const COR_TOM: Record<TomFin, string> = {
  bom: 'var(--green)', ruim: 'var(--red)', atencao: 'var(--yellow)', neutro: 'var(--fg-3)',
};
const CHIP: Record<TomFin, string> = {
  bom: 'border-[var(--green-border)] bg-[var(--green-subtle)] text-[var(--green)]',
  ruim: 'border-[var(--red-border)] bg-[var(--red-subtle)] text-[var(--red)]',
  atencao: 'border-[var(--yellow-border)] bg-[var(--yellow-subtle)] text-[var(--yellow)]',
  neutro: 'border-[var(--border)] bg-[var(--surface-2)] text-[var(--fg-2)]',
};
const ICONE_TOM: Record<TomFin, string | null> = { bom: 'check', ruim: 'alert', atencao: 'alert', neutro: null };

/** Situação em chip: o texto diz a situação, a cor e o ícone reforçam (nunca a cor sozinha). */
export function Chip({ tom = 'neutro', children, icone }: { tom?: TomFin; children: ReactNode; icone?: string | null }) {
  const ic = icone === undefined ? ICONE_TOM[tom] : icone;
  return (
    <span className={`inline-flex items-center gap-1 whitespace-nowrap rounded-full border px-1.5 py-px text-[11px] font-semibold ${CHIP[tom]}`}>
      {ic && <Icon name={ic} size={11} />}{children}
    </span>
  );
}

/** Acerto da previsão em chip: ≥ 90% verde, ≥ 70% âmbar, abaixo vermelho. Sem medida: traço. */
export function Acerto({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-[var(--fg-4)]">—</span>;
  const tom: TomFin = pct >= 90 ? 'bom' : pct >= 70 ? 'atencao' : 'ruim';
  return <Chip tom={tom}>{`${pct.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`}</Chip>;
}

// Tabela estilizada (classes literais — o Tailwind só gera o que aparece escrito). Longa: a caixa rola e o cabeçalho fica.
/** Caixa de tabela longa: rola dentro de si, então o `sticky top-0` do cabeçalho tem a quem se prender. */
export const CX_TABELA_LONGA = 'max-h-[70vh] overflow-auto rounded-[var(--r-md)] border border-[var(--border)]';
export const THEAD_FIXO = 'sticky top-0 z-[2] bg-[var(--surface-2)] shadow-[0_1px_0_var(--border)]';
/** Linha de dado: zebra discreta + hover. */
export const LINHA = 'border-t border-[var(--border-faint)] even:bg-[var(--surface-1)] hover:bg-[var(--surface-2)]';

/** Lista vazia com instrução (não um "0" que parece dado). */
export function Vazio({ children }: { children: ReactNode }) {
  return <span className="inline-flex items-center gap-1.5 text-[var(--fg-3)]"><Icon name="circle" size={10} />{children}</span>;
}

export interface ItemBarra {
  rotulo: string;
  /** NULL = sem medida (listrado, texto `textoNulo`), nunca uma barra zerada. */
  valor: number | null;
  tom?: TomFin;
  /** Texto à direita do valor (n, %). */
  detalhe?: string;
}

/** Barras horizontais com o valor escrito ao lado; a maior define a escala. Uma série só, legível sem legenda. */
export function BarrasH({ titulo, itens, textoNulo = 'sem medida', formato = fmtBRLc, extra }: {
  titulo: string; itens: ItemBarra[]; textoNulo?: string; formato?: (v: number) => string; extra?: ReactNode;
}) {
  if (itens.length === 0) return null;
  const max = Math.max(0, ...itens.map((i) => i.valor ?? 0));
  const descricao = itens.map((i) => `${i.rotulo}: ${i.valor == null ? textoNulo : formato(i.valor)}${i.detalhe ? ` (${i.detalhe})` : ''}`).join('; ');
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
        <div className="text-sm font-semibold text-[var(--fg)]">{titulo}</div>
        {extra}
      </div>
      <ul role="img" aria-label={`${titulo}. ${descricao}`} className="space-y-1.5">
        {itens.map((i, k) => {
          const w = i.valor == null || max <= 0 || Math.round(i.valor * 100) === 0 ? 0 : Math.max(1.5, (i.valor / max) * 100);
          return (
            <li key={k} className="grid grid-cols-[minmax(0,11rem)_minmax(0,1fr)_auto] items-center gap-2 text-xs" aria-hidden>
              <span className="truncate text-[var(--fg-2)]" title={i.rotulo}>{i.rotulo}</span>
              <span className="h-3 rounded-[var(--r-sm)] bg-[var(--surface-3)]">
                {i.valor == null ? (
                  <span className="block h-3 rounded-[var(--r-sm)] border border-dashed border-[var(--border)]" style={{ backgroundImage: RASURA }} />
                ) : (
                  <span className="block h-3 rounded-[var(--r-sm)]" style={{ width: `${w}%`, background: COR_TOM[i.tom ?? 'bom'] }} />
                )}
              </span>
              <span className="min-w-[7rem] text-right tabular">
                <span className={i.valor == null ? 'text-[var(--fg-4)]' : 'font-semibold text-[var(--fg)]'}>{i.valor == null ? textoNulo : formato(i.valor)}</span>
                {i.detalhe && <span className="ml-1 text-[var(--fg-3)]">{i.detalhe}</span>}
              </span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/** Barras divergentes a partir do zero: entrou (verde, à direita, ▲) × saiu (vermelho, à esquerda, ▼). Conta o PORQUÊ
 * de um saldo mudar, que a tabela por grupo espalha. */
export function Divergentes({ titulo, itens, rodape }: {
  titulo: string; itens: { rotulo: string; valor: number; detalhe?: string }[]; rodape?: ReactNode;
}) {
  if (itens.length === 0) return null;
  const max = Math.max(...itens.map((i) => Math.abs(i.valor)), 0.01);
  const descricao = itens.map((i) => `${i.rotulo}: ${i.valor >= 0 ? '+' : ''}${fmtBRLc(i.valor)}`).join('; ');
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
      <div className="mb-2 text-sm font-semibold text-[var(--fg)]">{titulo}</div>
      <ul role="img" aria-label={`${titulo}. ${descricao}`} className="space-y-1.5">
        {itens.map((i, k) => {
          const pos = i.valor >= 0;
          const w = `${Math.max(1.5, (Math.abs(i.valor) / max) * 100)}%`;
          const barra = <span className="block h-3 rounded-[var(--r-sm)]" style={{ width: w, background: pos ? 'var(--green)' : 'var(--red)' }} />;
          return (
            <li key={k} className="grid grid-cols-[minmax(0,14rem)_minmax(0,1fr)_minmax(0,1fr)_auto] items-center gap-x-2 text-xs" aria-hidden>
              <span className="truncate text-[var(--fg-2)]" title={i.rotulo}>{i.rotulo}</span>
              <span className="flex justify-end border-r border-[var(--border)] pr-px">{!pos && barra}</span>
              <span className="flex">{pos && barra}</span>
              <span className={`inline-flex min-w-[8rem] items-center justify-end gap-0.5 tabular font-semibold ${pos ? 'text-[var(--green)]' : 'text-[var(--red)]'}`}>
                <Icon name={pos ? 'arrow-up' : 'arrow-down'} size={12} />{pos ? '+' : ''}{fmtBRLc(i.valor)}
                {i.detalhe && <span className="ml-1 font-normal text-[var(--fg-3)]">{i.detalhe}</span>}
              </span>
            </li>
          );
        })}
      </ul>
      {rodape && <div className="mt-2 border-t border-[var(--border-faint)] pt-1.5 text-xs text-[var(--fg-2)]">{rodape}</div>}
    </div>
  );
}

/** Número grande com rótulo, contexto numa linha e (opcional) link para onde o número mora. */
export function KpiFin({ rotulo, valor, detalhe, tom = 'neutro', href, onClick, variacao, icone }: {
  rotulo: string; valor: string; detalhe?: ReactNode; tom?: TomFin; href?: string;
  /** Ação local (ex.: filtrar a lista da própria sub-aba) — sem trocar o hash nem remontar nada. */
  onClick?: () => void;
  variacao?: ReactNode; icone?: string;
}) {
  // Só <span> dentro: o cartão pode ser <a> ou <button>, que não aceitam <div>.
  const corpo = (
    <>
      <span className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">
        {icone && <Icon name={icone} size={12} />}{rotulo}
      </span>
      <span className="mt-1 flex flex-wrap items-baseline gap-x-2">
        <span className={`text-xl font-bold tabular ${COR[tom]}`}>{valor}</span>
        {variacao}
      </span>
      {detalhe && <span className="mt-0.5 block text-[11px] text-[var(--fg-3)]">{detalhe}</span>}
    </>
  );
  const classe = `block rounded-[var(--r-lg)] border ${BORDA[tom]} bg-[var(--surface-1)] px-3 py-2.5`;
  if (onClick) return <button type="button" onClick={onClick} className={`${classe} w-full text-left hover:bg-[var(--surface-2)]`}>{corpo}</button>;
  return href
    ? <a href={href} className={`${classe} hover:bg-[var(--surface-2)]`}>{corpo}</a>
    : <div className={classe}>{corpo}</div>;
}

export function FaixaKpis({ children }: { children: ReactNode }) {
  return <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">{children}</div>;
}

export interface BarraSemana {
  /** Rótulo curto (S2, 05–11/10…). */
  rotulo: string;
  /** Segunda linha do rótulo (período). */
  sub?: string;
  /** Parte certa (sólida, verde). */
  certo: number;
  /** Parte estimada (empilhada por cima, laranja translúcido). */
  estimado?: number;
  /** Acumulado até esta barra (texto no pé). */
  acumulado?: number;
}

/** Barras por semana com o valor escrito em cima de cada uma. Semana zerada = coluna rasurada com "sem valor".
 * A cor diz a certeza (verde = certo, laranja = estimado), a seta no título diz se a última semana subiu ou caiu. */
export function BarrasSemanas({ titulo, barras, legendaEstimado = true }: {
  titulo: string; barras: BarraSemana[]; legendaEstimado?: boolean;
}) {
  if (barras.length === 0) return null;
  const tot = (b: BarraSemana) => b.certo + (b.estimado ?? 0);
  const teto = tetoRedondo(Math.max(0, ...barras.map(tot)));
  const soma = barras.reduce((s, b) => s + tot(b), 0);
  const media = soma / barras.length;
  const maior = barras.reduce((m, b, i) => (tot(b) > tot(barras[m]) ? i : m), 0);
  const temEstimado = barras.some((b) => (b.estimado ?? 0) > 0);
  const ALT = 150;
  const descricao = barras.map((b) => `${b.rotulo}: ${fmtBRL(tot(b))}`).join('; ');
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-4">
      <div className="mb-3 flex flex-wrap items-start justify-between gap-x-4 gap-y-1">
        <div>
          <div className="text-sm font-semibold text-[var(--fg)]">{titulo}</div>
          <div className="mt-0.5 text-[11px] text-[var(--fg-3)]">média {compacto(media)} por semana · maior: {barras[maior].rotulo}</div>
        </div>
        <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg-3)]">
          <span className="flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-1">
            <span className="h-2 w-2 rounded-full bg-[var(--green)]" aria-hidden />Certo
          </span>
          {legendaEstimado && temEstimado && (
            <span className="flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-1">
              <span className="h-2 w-2 rounded-full bg-[var(--accent)]" aria-hidden />Estimado
            </span>
          )}
          <span className="flex items-center gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-1">
            Total <strong className="tabular text-[var(--fg)]">{fmtBRL(soma)}</strong>
          </span>
        </div>
      </div>
      <div role="img" aria-label={`${titulo}. ${descricao}`} className="flex items-end gap-2 overflow-x-auto pb-1">
        {barras.map((b, i) => {
          const t = tot(b);
          const hC = teto > 0 ? (b.certo / teto) * ALT : 0;
          const hE = teto > 0 ? ((b.estimado ?? 0) / teto) * ALT : 0;
          const vazio = Math.round(t * 100) === 0;
          return (
            <div key={i} className="flex min-w-[64px] flex-1 flex-col items-center" aria-hidden>
              <div className="flex w-full max-w-[64px] flex-col items-center justify-end" style={{ height: ALT + 18 }}>
                <div className={`mb-1 text-[11px] font-semibold tabular ${vazio ? 'text-[var(--fg-4)]' : i === maior ? 'text-[var(--green)]' : 'text-[var(--fg)]'}`}>
                  {vazio ? 'sem valor' : compacto(t)}
                </div>
                <div className="flex w-full max-w-[56px] flex-col justify-end" style={{ height: vazio ? ALT : undefined }}>
                {vazio ? (
                  <div className="h-full rounded-[var(--r-sm)] border border-dashed border-[var(--border)]" style={{ backgroundImage: RASURA }} />
                ) : (
                  <>
                    {hE > 0 && <div className="rounded-t-[var(--r-sm)] bg-[var(--accent)] opacity-60" style={{ height: Math.max(2, hE) }} />}
                    <div className={`bg-[var(--green)] ${hE > 0 ? '' : 'rounded-t-[var(--r-sm)]'} rounded-b-[2px]`} style={{ height: Math.max(3, hC) }} />
                  </>
                )}
                </div>
              </div>
              <div className="mt-1.5 text-center text-[11px] leading-tight">
                <div className="font-semibold text-[var(--fg-2)]">{b.rotulo}</div>
                {b.sub && <div className="text-[var(--fg-4)]">{b.sub}</div>}
                {b.acumulado != null && <div className="mt-0.5 tabular text-[var(--fg-3)]">acum. {compacto(b.acumulado).replace('R$ ', '')}</div>}
              </div>
            </div>
          );
        })}
      </div>
      <p className="sr-only">{descricao}</p>
    </div>
  );
}

/** Farol de um alerta: verde "em dia" quando é zero, vermelho/âmbar com o valor quando pede ação. */
export function Farol({ ok, children }: { ok: boolean; children: ReactNode }) {
  return (
    <span className={`inline-flex items-center gap-1 ${ok ? 'text-[var(--green)]' : 'font-semibold text-[var(--red)]'}`}>
      <Icon name={ok ? 'check' : 'alert'} size={12} />{children}
    </span>
  );
}

export const brlc = fmtBRLc;
