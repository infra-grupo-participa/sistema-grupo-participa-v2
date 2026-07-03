import { nivelLabel, nivelNormalize } from '@/shared/domain/nivel-resultado';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

// Corporativo: chip neutro uniforme + ponto de status colorido (sem pílula colorida).
const DOT: Record<Tone, string> = {
  neutral: 'var(--fg-3)',
  accent: 'var(--accent)',
  success: 'var(--green)',
  warning: 'var(--yellow)',
  danger: 'var(--red)',
  info: 'var(--info)',
};

// max-w-full + texto em span com truncate: em célula estreita (table-fixed) o chip
// encolhe com reticências em vez de ser decepado no meio da moldura.
const CHIP =
  'inline-flex max-w-full items-center gap-1.5 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-0.5 text-xs font-medium text-[var(--fg-2)] whitespace-nowrap';

/** Chip de status corporativo — cor só no ponto, texto/fundo neutros.
 *  `dotColor` sobrepõe a cor do ponto (ex.: cor por espaço/valor). */
export function Badge({ children, tone = 'neutral', dot = false, dotColor }: { children: React.ReactNode; tone?: Tone; dot?: boolean; dotColor?: string }) {
  const showDot = dot || tone !== 'neutral' || !!dotColor;
  return (
    <span className={CHIP} title={typeof children === 'string' ? children : undefined}>
      {showDot && <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: dotColor || DOT[tone] }} />}
      <span className="truncate">{children}</span>
    </span>
  );
}

const NIVEL_COLOR: Record<string, string> = {
  iniciante: 'var(--nivel-base)',
  pessoal: 'var(--nivel-base)',
  em_formacao: 'var(--nivel-base)',
  profissional: 'var(--nivel-base)',
  ouro: 'var(--nivel-ouro)',
  platina: 'var(--nivel-platina)',
  diamante: 'var(--nivel-diamante)',
  diamante_vermelho: 'var(--nivel-diamante-vermelho)',
};

/** Assinatura: nível como chip neutro com dot colorido por metal/pedra. */
export function NivelBadge({ nivel }: { nivel: string | null | undefined }) {
  const key = nivelNormalize(nivel);
  if (!key) return <span className="text-[var(--fg-3)]">—</span>;
  const color = NIVEL_COLOR[key] || 'var(--nivel-base)';
  return (
    <span className={CHIP} title={nivelLabel(key)}>
      <span className="w-2 h-2 rounded-full shrink-0" style={{ background: color }} />
      <span className="truncate">{nivelLabel(key)}</span>
    </span>
  );
}
