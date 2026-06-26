// Domínio puro — máquina de estados da AUDITORIA de placa.
// Porta fiel de app/relatorios/placas/relatorios.html (AUDIT_STEP_INDEX/AUDIT_STEPS + helpers).

export const DOCS_APROVADOS_LABEL = 'Documentação Aprovada';

export const AUDIT_STEP_INDEX = {
  DOCUMENTACAO_EM_ANALISE: 0,
  DOCS_APROVADOS: 1,
  ENTREVISTA_AGENDADA: 2,
  ENTREVISTA_FINALIZADA: 3,
  PLACA_EM_CONFECCAO: 4,
  PLACA_ENVIADA: 5,
  PLACA_RECEBIDA: 6,
} as const;

export const AUDIT_STEP_TOTAL = AUDIT_STEP_INDEX.PLACA_RECEBIDA + 1; // 7

export type AuditStepKey =
  | 'documentacao_em_analise'
  | 'docs_aprovados'
  | 'entrevista_agendada'
  | 'entrevista_finalizada'
  | 'placa_em_confeccao'
  | 'placa_enviada'
  | 'placa_recebida';

export interface AuditStep {
  key: AuditStepKey;
  name: string;
  desc: string;
  actionLabel: string;
  /** classe de badge (status pill) usada no painel */
  cls: string;
  shortLabel: string;
}

// Índice = step_index. Ordem e textos replicam o legado 1:1.
export const AUDIT_STEPS: readonly AuditStep[] = [
  {
    key: 'documentacao_em_analise',
    name: 'Documentação em Análise',
    desc: 'Documentação enviada pelo cliente. Aguardando revisão e aprovação pela equipe.',
    actionLabel: 'Aprovar documentação',
    cls: 'sp-andamento',
    shortLabel: 'Documentação em análise',
  },
  {
    key: 'docs_aprovados',
    name: DOCS_APROVADOS_LABEL,
    desc: 'Documentação aprovada pela equipe. Aguardando o cliente agendar a entrevista.',
    actionLabel: '',
    cls: 'sp-aguardando',
    shortLabel: DOCS_APROVADOS_LABEL,
  },
  {
    key: 'entrevista_agendada',
    name: 'Entrevista Agendada',
    desc: 'Cliente agendou a entrevista por videoconferência. Aguardando realização.',
    actionLabel: 'Finalizar entrevista',
    cls: 'sp-andamento',
    shortLabel: 'Entrevista agendada',
  },
  {
    key: 'entrevista_finalizada',
    name: 'Entrevista Concluída',
    desc: 'Entrevista realizada com sucesso. A placa será encaminhada para confecção.',
    actionLabel: 'Placa em confecção',
    cls: 'sp-andamento',
    shortLabel: 'Entrevista concluída',
  },
  {
    key: 'placa_em_confeccao',
    name: 'Placa em Confecção',
    desc: 'Placa em processo de confecção. Aguardando envio com código de rastreio.',
    actionLabel: 'Placa enviada',
    cls: 'sp-andamento',
    shortLabel: 'Placa em confecção',
  },
  {
    key: 'placa_enviada',
    name: 'Placa Enviada',
    desc: 'Placa enviada pelos Correios com código de rastreio. Aguardando confirmação de recebimento.',
    actionLabel: 'Confirmar recebimento',
    cls: 'sp-andamento',
    shortLabel: 'Placa enviada',
  },
  {
    key: 'placa_recebida',
    name: 'Placa Recebida',
    desc: 'Placa recebida pelo aluno. Processo concluído!',
    actionLabel: '— Processo concluído! —',
    cls: 'sp-entregue',
    shortLabel: 'Placa recebida',
  },
];

/** Etapa final (placa recebida) atingida? */
export function isAuditCompletedStep(stepIndex: number | null | undefined): boolean {
  return Number(stepIndex) >= AUDIT_STEP_INDEX.PLACA_RECEBIDA;
}

/**
 * Processo concluído — considera step novo e status legado.
 * 'concluido' → true; 'placa_postada' → false (enviada, aguardando recebimento).
 */
export function isProcessoConcluido(
  stepIndex: number | null | undefined,
  status?: string | null,
): boolean {
  if (status === 'concluido') return true;
  if (status === 'placa_postada') return false;
  return Number(stepIndex) >= AUDIT_STEP_INDEX.PLACA_RECEBIDA;
}

/** Encerrado só vale se ainda não chegou na etapa final. */
export function normalizeAuditEncerrado(
  stepIndex: number | null | undefined,
  encerrado: boolean | null | undefined,
): boolean {
  return Boolean(encerrado) && !isAuditCompletedStep(stepIndex);
}

// ── Transição de etapa (porta de avancarEtapa) ──────────────────────────────

export type SolicitacaoStatusValue =
  | 'em_auditoria'
  | 'docs_aprovados'
  | 'placa_postada'
  | 'concluido';

/** Status da solicitação correspondente a uma etapa de auditoria. */
export function statusForAuditStep(step: number): SolicitacaoStatusValue {
  if (step >= AUDIT_STEP_INDEX.PLACA_RECEBIDA) return 'concluido';
  if (step === AUDIT_STEP_INDEX.PLACA_ENVIADA) return 'placa_postada';
  if (step >= AUDIT_STEP_INDEX.DOCS_APROVADOS) return 'docs_aprovados';
  return 'em_auditoria';
}

/** E-mail disparado ao ENTRAR numa etapa (null = sem e-mail). Porta dos 3 eventos reais. */
export type AuditEmailEvent = 'docs_aprovados' | 'entrevista_finalizada' | 'placa_em_caminho';

export function emailEventForAuditStep(novoStep: number): AuditEmailEvent | null {
  if (novoStep === AUDIT_STEP_INDEX.DOCS_APROVADOS) return 'docs_aprovados';
  if (novoStep === AUDIT_STEP_INDEX.ENTREVISTA_FINALIZADA) return 'entrevista_finalizada';
  if (novoStep === AUDIT_STEP_INDEX.PLACA_ENVIADA) return 'placa_em_caminho';
  return null;
}

export type AdvanceBlock = 'concluido' | 'aguardando_agendamento' | 'sem_rastreio';

export interface AdvancePlan {
  novoStep: number;
  novoStatus: SolicitacaoStatusValue;
  /** chave da etapa ATUAL a carimbar em dates{} */
  stampStepKey: AuditStepKey;
  emailEvent: AuditEmailEvent | null;
  /** entrevista finalizada → remover o slot da agenda */
  removeInterviewSlot: boolean;
}

/**
 * Planeja o avanço de uma etapa de auditoria. Porta fiel das guardas de avancarEtapa:
 *  - etapa final → bloqueio 'concluido';
 *  - DOCS_APROVADOS (1) não avança manualmente → 'aguardando_agendamento';
 *  - PLACA_EM_CONFECCAO (4) exige código de rastreio → 'sem_rastreio'.
 * Retorna AdvancePlan quando permitido.
 */
export function planAuditAdvance(
  stepAtual: number,
  opts: { hasCodigoRastreio?: boolean } = {},
): { blocked: AdvanceBlock } | AdvancePlan {
  if (stepAtual >= AUDIT_STEP_INDEX.PLACA_RECEBIDA) return { blocked: 'concluido' };
  if (stepAtual === AUDIT_STEP_INDEX.DOCS_APROVADOS) return { blocked: 'aguardando_agendamento' };
  if (stepAtual === AUDIT_STEP_INDEX.PLACA_EM_CONFECCAO && !opts.hasCodigoRastreio) {
    return { blocked: 'sem_rastreio' };
  }
  const novoStep = stepAtual + 1;
  return {
    novoStep,
    novoStatus: statusForAuditStep(novoStep),
    stampStepKey: AUDIT_STEPS[stepAtual].key,
    emailEvent: emailEventForAuditStep(novoStep),
    removeInterviewSlot: novoStep === AUDIT_STEP_INDEX.ENTREVISTA_FINALIZADA,
  };
}
