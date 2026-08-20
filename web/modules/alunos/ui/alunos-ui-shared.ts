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

// ── Vínculo titular × sócio ──

/** Nome comparável: sem acento, sem pontuação, em minúsculas e com espaço único. */
const chaveNome = (v: string | null | undefined): string =>
  (v || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();

export interface VinculoSocio {
  /** Quando a pessoa é sócia: o registro do titular, se ele existir na base carregada. */
  titular: Aluno360 | null;
  /** Nome do titular como está no cadastro. Vem preenchido mesmo quando o registro não foi achado. */
  titularNome: string | null;
  /** Quando a pessoa é titular: quem está cadastrado como sócio dela. */
  socios: Aluno360[];
}

/**
 * Liga titular e sócio nos dois sentidos.
 *
 * O vínculo forte é `socio_de_aluno_id`, mas boa parte da base só tem
 * `socio_de_nome` (texto, herdado da planilha) — por isso há o casamento por
 * nome normalizado como segunda tentativa. O nome do titular é devolvido mesmo
 * quando o registro dele não está na base carregada (titular fora da Central,
 * por exemplo), para a ficha nunca ficar muda sobre de quem a pessoa é sócia.
 */
export function vinculoSocio(a: Aluno360, todos: Aluno360[]): VinculoSocio {
  const titularNome = (a.socio_de_nome || '').trim() || null;

  let titular: Aluno360 | null = null;
  if (a.eh_socio || titularNome) {
    if (a.socio_de_aluno_id) titular = todos.find((o) => o.id === a.socio_de_aluno_id) ?? null;
    if (!titular && titularNome) {
      const k = chaveNome(titularNome);
      titular = todos.find((o) => o.id !== a.id && chaveNome(o.nome) === k) ?? null;
    }
  }

  const meuNome = chaveNome(a.nome);
  const socios = todos.filter(
    (o) =>
      o.id !== a.id &&
      (o.socio_de_aluno_id === a.id || (!!meuNome && chaveNome(o.socio_de_nome) === meuNome)),
  );

  return { titular, titularNome, socios };
}
