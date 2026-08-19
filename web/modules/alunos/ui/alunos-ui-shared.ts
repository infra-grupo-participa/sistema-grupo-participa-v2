// Helpers de exibição compartilhados entre a lista e o drawer 360 de Alunos.

import type { Aluno360 } from '../domain/aluno-360';

export type Tone = 'success' | 'danger' | 'warning' | 'neutral' | 'info' | 'accent';

export const sitTone = (cls: string): Tone =>
  cls === 'green' ? 'success' : cls === 'red' ? 'danger' : cls === 'yellow' ? 'warning' : 'neutral';

export const tel = (v: string | null) => v || '—';

/** Turma THB + Aurum num só texto (HM e Aurum). */
export const turmaCombo = (a: Aluno360) => [a.turma_codigo, a.turma_aurum_codigo].filter(Boolean).join(' · ');

/**
 * Vencimento sem data NÃO é sempre dado faltando, e por isso a célula não pode
 * cair num traço mudo: sócio herda o prazo do titular, cortesia não expira e a
 * base pré-Hotmart nunca teve ano. Devolve o motivo quando ele é conhecido —
 * `null` quando o badge de situação já diz tudo (sócio) ou quando falta mesmo.
 */
export const motivoSemVencimento = (a: Aluno360): string | null => {
  if (a.data_expiracao) return null;
  const t = (a.tempo_acesso || '').trim().toLowerCase();
  if (t === 'sem prazo') return 'Sem prazo';
  if (t === 'ver base atual') return 'Sem data na base';
  return null;
};
