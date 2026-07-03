// Domínio puro — SOLICITAÇÃO de placa: status, predicados e status de exibição.
// Porta fiel de relatorios.html (STATUS_LABELS/COLORS + isSolicitacao* + computeDisplayStatus).

import { AUDIT_STEP_INDEX, AUDIT_STEP_TOTAL, DOCS_APROVADOS_LABEL } from './auditoria';

export type SolicitacaoStatus =
  | 'rascunho'
  | 'enviado'
  | 'em_auditoria'
  | 'docs_aprovados'
  | 'placa_postada' // legado
  | 'cadastro_concluido'
  | 'concluido'
  | 'rejeitado';

export const REGULARIZACAO_LABEL = 'Cliente reprovado · aguardando nova documentação';

/** Forma mínima de solicitação usada pelos predicados de domínio. */
export interface SolicitacaoLike {
  id?: string;
  status?: string | null;
  auditoria_step?: number | null;
  step_index?: number | null;
  regularizacao_pendente?: boolean | null;
  proof_url?: string | null;
  declaracao_url?: string | null;
  admin_seen_at?: string | null;
  admin_attention_at?: string | null;
  updated_at?: string | null;
  created_at?: string | null;
}

export const STATUS_LABELS: Record<string, string> = {
  rascunho: 'Rascunho',
  enviado: 'Enviado',
  em_auditoria: 'Em auditoria',
  docs_aprovados: DOCS_APROVADOS_LABEL,
  placa_postada: 'Placa postada',
  aguardando_regularizacao: REGULARIZACAO_LABEL,
  cadastro_concluido: 'Somente cadastro',
  concluido: 'Placa recebida',
  rejeitado: 'Rejeitado',
};

export const STATUS_COLORS: Record<string, string> = {
  rascunho: 'sp-aguardando',
  enviado: 'sp-andamento',
  em_auditoria: 'sp-andamento',
  docs_aprovados: 'sp-aguardando',
  placa_postada: 'sp-entregue',
  aguardando_regularizacao: 'sp-regularizacao',
  cadastro_concluido: 'sp-aguardando',
  concluido: 'sp-entregue',
  rejeitado: 'sp-encerrado',
};

const statusStr = (sol: SolicitacaoLike) => String(sol?.status || '').trim();
const toDate = (raw?: string | null): Date | null => {
  if (!raw) return null;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
};

export function getSolicitacaoLastTouchedAt(sol: SolicitacaoLike): Date | null {
  return toDate(sol?.updated_at || sol?.created_at || null);
}

export function getSolicitacaoAttentionAt(sol: SolicitacaoLike): Date | null {
  return toDate(sol?.admin_attention_at || sol?.updated_at || sol?.created_at || null);
}

export function isSolicitacaoRegularizacao(sol: SolicitacaoLike): boolean {
  return Boolean(sol?.regularizacao_pendente);
}

/** Reprovado que JÁ reenviou a documentação completa (aguardando nova revisão). */
export function isSolicitacaoReenvioPosReprovacao(sol: SolicitacaoLike): boolean {
  return isSolicitacaoRegularizacao(sol) && Boolean(sol?.proof_url) && Boolean(sol?.declaracao_url);
}

export function isSolicitacaoSeen(sol: SolicitacaoLike): boolean {
  const seenAt = toDate(sol?.admin_seen_at);
  if (!seenAt) return false;
  const attentionAt = getSolicitacaoAttentionAt(sol);
  return !attentionAt || seenAt.getTime() + 5000 >= attentionAt.getTime();
}

export function isSolicitacaoSomenteCadastro(sol: SolicitacaoLike): boolean {
  return statusStr(sol) === 'cadastro_concluido' && !isSolicitacaoRegularizacao(sol);
}

export function isSolicitacaoRascunho(sol: SolicitacaoLike): boolean {
  return statusStr(sol) === 'rascunho' && !isSolicitacaoRegularizacao(sol);
}

export function isSolicitacaoFinalizada(sol: SolicitacaoLike): boolean {
  return ['concluido', 'rejeitado'].includes(statusStr(sol));
}

export function isSolicitacaoEmAndamento(sol: SolicitacaoLike): boolean {
  return !isSolicitacaoRascunho(sol) && !isSolicitacaoFinalizada(sol);
}

export function isSolicitacaoProcesso(sol: SolicitacaoLike): boolean {
  return (
    !isSolicitacaoRascunho(sol) && !isSolicitacaoSomenteCadastro(sol) && !isSolicitacaoFinalizada(sol)
  );
}

export function isSolicitacaoQuestionarioFinalizado(sol: SolicitacaoLike): boolean {
  return ['concluido', 'rejeitado'].includes(statusStr(sol));
}

export type SolicitacaoBucket = 'cadastro' | 'rascunhos' | 'questionarios' | 'processo';

export function getSolicitacaoBucketMatch(sol: SolicitacaoLike, bucket: SolicitacaoBucket): boolean {
  if (bucket === 'cadastro') return isSolicitacaoSomenteCadastro(sol);
  if (bucket === 'rascunhos') return isSolicitacaoRascunho(sol);
  if (bucket === 'questionarios') return isSolicitacaoQuestionarioFinalizado(sol);
  return isSolicitacaoProcesso(sol);
}

export function getSolicitacaoQueuePriority(sol: SolicitacaoLike): number {
  const status = statusStr(sol);
  if (isSolicitacaoRegularizacao(sol)) return 0;
  if (status === 'enviado') return 1;
  if (status === 'em_auditoria') return 2;
  if (status === 'docs_aprovados') return 3;
  if (status === 'placa_postada') return 4;
  if (status === 'concluido') return 5;
  if (status === 'cadastro_concluido') return 6;
  if (status === 'rejeitado') return 7;
  return isSolicitacaoRascunho(sol) ? 8 : 4;
}

export function getSolicitacaoStatusFilterKey(sol: SolicitacaoLike): string {
  const status = statusStr(sol);
  const auditStep = Number(sol?.auditoria_step);

  if (isSolicitacaoRegularizacao(sol)) return 'aguardando_regularizacao';
  if (status === 'rejeitado') return 'rejeitado';
  if (status === 'cadastro_concluido') return 'cadastro_concluido';
  if (status === 'rascunho') return 'rascunho';
  if (status === 'placa_postada') return `audit_${AUDIT_STEP_INDEX.PLACA_ENVIADA}`;
  if (status === 'concluido') return `audit_${AUDIT_STEP_INDEX.PLACA_RECEBIDA}`;

  if (
    Number.isFinite(auditStep) &&
    auditStep >= AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE &&
    auditStep <= AUDIT_STEP_INDEX.PLACA_RECEBIDA
  ) {
    return `audit_${auditStep}`;
  }

  if (status === 'docs_aprovados') return `audit_${AUDIT_STEP_INDEX.DOCS_APROVADOS}`;
  if (status === 'em_auditoria') return `audit_${AUDIT_STEP_INDEX.DOCUMENTACAO_EM_ANALISE}`;
  if (status === 'enviado') return 'enviado';
  return status;
}

export interface DisplayStatus {
  label: string;
  cls: string;
}

// AUDIT_STEP_STATUS (label curto + classe por etapa) — derivado de AUDIT_STEPS.
const AUDIT_STEP_STATUS = [
  { label: 'Documentação em análise', cls: 'sp-andamento' },
  { label: DOCS_APROVADOS_LABEL, cls: 'sp-aguardando' },
  { label: 'Entrevista agendada', cls: 'sp-andamento' },
  { label: 'Entrevista concluída', cls: 'sp-andamento' },
  { label: 'Placa em confecção', cls: 'sp-andamento' },
  { label: 'Placa enviada', cls: 'sp-andamento' },
  { label: 'Placa recebida', cls: 'sp-entregue' },
];

export function computeDisplayStatus(sol: SolicitacaoLike): DisplayStatus {
  if (sol.status === 'placa_postada')
    return { label: `${AUDIT_STEP_TOTAL}/${AUDIT_STEP_TOTAL} · Placa enviada`, cls: 'sp-entregue' };
  if (sol.status === 'concluido')
    return { label: `${AUDIT_STEP_TOTAL}/${AUDIT_STEP_TOTAL} · Placa recebida`, cls: 'sp-entregue' };
  if (isSolicitacaoRegularizacao(sol)) {
    return isSolicitacaoReenvioPosReprovacao(sol)
      ? { label: 'Reenviou · revisar documentos', cls: 'sp-andamento' }
      : { label: REGULARIZACAO_LABEL, cls: 'sp-regularizacao' };
  }
  if (sol.status === 'rejeitado') return { label: 'Rejeitado', cls: 'sp-encerrado' };
  if (sol.status === 'cadastro_concluido') return { label: 'Somente cadastro', cls: 'sp-aguardando' };

  const step = sol.auditoria_step != null ? Number(sol.auditoria_step) : -1;
  if (step >= 0 && step < AUDIT_STEP_STATUS.length) {
    const s = AUDIT_STEP_STATUS[step];
    return { label: `${step + 1}/${AUDIT_STEP_TOTAL} · ${s.label}`, cls: s.cls };
  }

  return {
    label: STATUS_LABELS[String(sol.status)] || String(sol.status) || '—',
    cls: STATUS_COLORS[String(sol.status)] || 'sp-aguardando',
  };
}

/**
 * Tom do Badge (DS) para a classe visual do status — mapeamento único usado pelas fichas
 * fora do módulo de placas (ex.: ficha 360 do aluno), para o status do processo nunca
 * aparecer cru/despadronizado.
 */
export function displayStatusTone(cls: string): 'neutral' | 'accent' | 'success' | 'warning' | 'danger' | 'info' {
  switch (cls) {
    case 'sp-entregue': return 'success'; // placa enviada/recebida
    case 'sp-andamento': return 'info'; // em análise/andamento
    case 'sp-aguardando': return 'warning'; // aguardando ação (cliente ou equipe)
    case 'sp-regularizacao': return 'warning'; // reprovado · aguardando nova documentação
    case 'sp-encerrado': return 'danger'; // rejeitado definitivo
    default: return 'neutral';
  }
}

/** Patch para marcar/desmarcar "visto" pelo admin (porta de buildAdminSeenPatch). */
export function buildAdminSeenPatch(isSeen = true): { admin_seen_at: string | null } {
  return { admin_seen_at: isSeen ? new Date().toISOString() : null };
}
