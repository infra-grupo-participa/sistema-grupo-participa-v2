// Helpers de exibição compartilhados entre a lista e o drawer 360 de Alunos.

import type { Aluno360 } from '../domain/aluno-360';

export type Tone = 'success' | 'danger' | 'warning' | 'neutral' | 'info' | 'accent';

export const sitTone = (cls: string): Tone =>
  cls === 'green' ? 'success' : cls === 'red' ? 'danger' : cls === 'yellow' ? 'warning' : 'neutral';

export const tel = (v: string | null) => v || '—';

/** Turma THB + Aurum num só texto (HM e Aurum). */
export const turmaCombo = (a: Aluno360) => [a.turma_codigo, a.turma_aurum_codigo].filter(Boolean).join(' · ');
