// Blocos visuais da ficha do aluno — compartilhados entre leitura (AlunoDrawer) e edição (AlunoForm).

import { Icon } from '@/shared/ui/icons';
import { Badge } from '@/shared/ui/components';
import { parseInstrucao, type Aluno360 } from '../domain/aluno-360';

/**
 * Instrução do aluno: nível E papel na mesma etiqueta (`Aurum · sócio`).
 *
 * Existe porque o badge de espaço mostra só o grupo — mais de mil pessoas
 * aparecendo como "Holding Masters", sem dizer quem é titular e quem é sócio.
 * Quem está sem `instrucao` cai no espaço, e aí o rótulo ganha "~" para deixar
 * claro que aquele nível foi inferido, não lido do cadastro.
 */
export function InstrucaoBadge({ a }: { a: Pick<Aluno360, 'instrucao' | 'espaco_instrucao' | 'eh_socio'> }) {
  const i = parseInstrucao(a);
  if (!i) return <span className="text-[var(--fg-3)]">—</span>;
  const badge = <Badge dotColor={i.cor}>{i.inferido ? `~${i.label}` : i.label}</Badge>;
  if (!i.inferido) return badge;
  return <span title="Nível inferido do espaço de instrução — este cadastro está sem instrução">{badge}</span>;
}

/** Cabeçalho de seção com ícone de acento (linguagem do card de Placas). */
export function SecTitle({ icon, children }: { icon: string; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 text-[var(--fg)]">
      <Icon name={icon} size={15} className="text-[var(--accent)]" /> {children}
    </span>
  );
}

export function SubTitle({ children }: { children: React.ReactNode }) {
  return <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] mt-3 mb-1 pt-1 border-t border-[var(--border-faint)]">{children}</div>;
}

export function Section({ children }: { children: React.ReactNode }) {
  return <div className="space-y-1.5">{children}</div>;
}

export function Row({ k, v }: { k: string; v: string | null }) {
  return <div className="flex justify-between gap-3 py-1 border-b border-[var(--border-faint)]"><span className="text-xs text-[var(--fg-3)]">{k}</span><span className="text-sm text-[var(--fg)] text-right">{v || '—'}</span></div>;
}
