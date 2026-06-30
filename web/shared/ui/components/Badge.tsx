import { nivelLabel, nivelNormalize } from '@/shared/domain/nivel-resultado';

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

const TONES: Record<Tone, { fg: string; bg: string; bd: string }> = {
  neutral: { fg: 'var(--fg-2)', bg: 'var(--surface-3)', bd: 'var(--border)' },
  accent: { fg: 'var(--accent)', bg: 'var(--accent-subtle)', bd: 'var(--accent-border)' },
  success: { fg: 'var(--green)', bg: 'var(--green-subtle)', bd: 'var(--green-border)' },
  warning: { fg: 'var(--yellow)', bg: 'var(--yellow-subtle)', bd: 'var(--yellow-border)' },
  danger: { fg: 'var(--red)', bg: 'var(--red-subtle)', bd: 'var(--red-border)' },
  info: { fg: 'var(--info)', bg: 'var(--info-subtle)', bd: 'var(--info-border)' },
};

/** Pill/badge de status — base da linguagem visual. */
export function Badge({ children, tone = 'neutral', dot = false }: { children: React.ReactNode; tone?: Tone; dot?: boolean }) {
  const t = TONES[tone];
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-[var(--r-pill)] px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap border"
      style={{ color: t.fg, background: t.bg, borderColor: t.bd }}
    >
      {dot && <span className="w-1.5 h-1.5 rounded-full" style={{ background: t.fg }} />}
      {children}
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

/** Assinatura: nível como dot colorido por metal/pedra. */
export function NivelBadge({ nivel }: { nivel: string | null | undefined }) {
  const key = nivelNormalize(nivel);
  if (!key) return <span className="text-[var(--fg-3)]">—</span>;
  const color = NIVEL_COLOR[key] || 'var(--nivel-base)';
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-[var(--r-pill)] px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap border"
      style={{ color, background: `color-mix(in srgb, ${color} 12%, transparent)`, borderColor: `color-mix(in srgb, ${color} 30%, transparent)` }}
    >
      <span className="w-2 h-2 rounded-full" style={{ background: color }} />
      {nivelLabel(key)}
    </span>
  );
}
