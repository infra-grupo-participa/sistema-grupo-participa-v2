// Programa do aluno e selo de nível comprovado: tradução de fn_aluno_programas_safe e fn_aluno_nivel_selo
// (20261002d/e). A regra é do SQL; aqui só rótulo, ordem e filtro. fn_aluno_programa_evidencias segue no banco,
// sem consumidor na tela desde 30/09/2026 (bloco "Por que está no programa" removido da ficha a pedido do João).
import { nivelLabel } from '@/shared/domain/nivel-resultado';

// Ligado por padrão; NEXT_PUBLIC_ALUNO_PROGRAMA=off tira coluna e filtros (inlined no build).
export const PROGRAMA_ATIVO = process.env.NEXT_PUBLIC_ALUNO_PROGRAMA !== 'off';

export interface ProgramaAluno {
  aluno_id: string;
  programas: string[];
  /** { programa: status } — status: confirmado | confirmado_cadastro | a_revisar | reservou. */
  status_programa: Record<string, string>;
  revisar_motivos: string[];
}

export interface SeloNivel {
  aluno_id: string;
  nivel_comprovado: string | null;
  comprovado_em: string | null;
  /** comprovado | nao_comprovado | outro_nivel | null (abaixo de ouro). */
  selo: string | null;
}

export const PROGRAMA_ORDEM = ['implementacao', 'hm', 'aurum', 'mastermind_diamante', 'platina', 'diamante_vermelho'] as const;

export const ROTULO_PROGRAMA: Record<string, string> = {
  implementacao: 'Implementação',
  hm: 'Holding Masters',
  aurum: 'Aurum',
  mastermind_diamante: 'Mastermind Diamante',
  platina: 'Platina',
  diamante_vermelho: 'Diamante Vermelho',
};

export const ROTULO_STATUS_PROGRAMA: Record<string, string> = {
  confirmado: 'Confirmado',
  confirmado_cadastro: 'Pelo cadastro',
  a_revisar: 'A revisar',
  reservou: 'Reservou',
};

export const ROTULO_MOTIVO: Record<string, string> = {
  impl_gps_sem_pagamento: 'Está no GPS, sem pagamento de HM localizado',
  impl_pago_fora_gps: 'Pagou o Programa, mas não está no GPS',
  impl_espaco_fora_gps: 'Espaço de Implementação, mas não está no GPS',
  aurum_so_pagamento: 'Aurum pago, sem turma, espaço ou plano Aurum',
  aurum_so_cadastro: 'Aurum no cadastro, sem pagamento localizado',
  mastermind_diamante_so_pagamento: 'Mastermind Diamante pago, sem espaço ou plano',
  mastermind_diamante_so_cadastro: 'Mastermind Diamante no cadastro, sem pagamento localizado',
};

const humano = (c: string) => c.replace(/_/g, ' ');
export const rotuloPrograma = (p: string | null): string => (p ? ROTULO_PROGRAMA[p] ?? humano(p) : '—');
export const rotuloStatusPrograma = (s: string): string => ROTULO_STATUS_PROGRAMA[s] ?? humano(s);
export const rotuloMotivo = (m: string): string => ROTULO_MOTIVO[m] ?? humano(m);

/** Programas na ordem fixa (Implementação primeiro); desconhecido vai para o fim. */
export function ordenarProgramas(ps: string[]): string[] {
  const r = (p: string) => { const i = (PROGRAMA_ORDEM as readonly string[]).indexOf(p); return i < 0 ? 99 : i; };
  return [...ps].sort((a, b) => r(a) - r(b) || a.localeCompare(b));
}

/** "A revisar" = algum programa com status a_revisar OU algum motivo de revisão. */
export const aRevisar = (p: ProgramaAluno | undefined): boolean =>
  !!p && (p.revisar_motivos.length > 0 || Object.values(p.status_programa).includes('a_revisar'));

/** Valor extra do filtro Programa. */
export const FILTRO_A_REVISAR = '__a_revisar__';

/** Filtro Programa: OR entre as opções (programa ou "A revisar"). Aluno sem linha na RPC não passa. */
export function passaFiltroPrograma(p: ProgramaAluno | undefined, valores: string[]): boolean {
  if (!valores.length) return true;
  return valores.some((v) =>
    v === FILTRO_A_REVISAR ? aRevisar(p) : !!p && p.programas.includes(v));
}

export const ROTULO_SELO: Record<string, string> = {
  comprovado: 'Comprovado',
  outro_nivel: 'Comprovado em outro nível',
  nao_comprovado: 'Sem comprovação',
};
/** Filtro Comprovação do nível: `selo` cru (comprovado | outro_nivel | nao_comprovado). */
export function passaFiltroComprovacao(s: SeloNivel | undefined, valores: string[]): boolean {
  if (!valores.length) return true;
  return !!s?.selo && valores.includes(s.selo);
}

/**
 * Selo ao lado do nível gravado — o nível gravado não muda, o selo é informação extra.
 * "Ouro · comprovado" · "Ouro · comprovado Platina" · "Ouro · sem comprovação". Abaixo de ouro: null.
 */
export function textoSelo(nivelResultado: string | null | undefined, s: SeloNivel | undefined): string | null {
  if (!s?.selo) return null;
  const nivel = nivelLabel(nivelResultado) || '—';
  if (s.selo === 'comprovado') return `${nivel} · comprovado`;
  if (s.selo === 'outro_nivel') return `${nivel} · comprovado ${nivelLabel(s.nivel_comprovado) || 'outro nível'}`;
  if (s.selo === 'nao_comprovado') return `${nivel} · sem comprovação`;
  return null;
}

/** Linha crua de fn_aluno_programas_safe → tipo (arrays/objetos nulos viram vazios). */
export function normalizarProgramas(linhas: unknown[]): ProgramaAluno[] {
  const out: ProgramaAluno[] = [];
  for (const l of linhas) {
    const r = (l ?? {}) as Record<string, unknown>;
    if (typeof r.aluno_id !== 'string') continue;
    const arr = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
    const sp = r.status_programa && typeof r.status_programa === 'object' ? (r.status_programa as Record<string, string>) : {};
    out.push({ aluno_id: r.aluno_id, programas: arr(r.programas), status_programa: sp, revisar_motivos: arr(r.revisar_motivos) });
  }
  return out;
}
