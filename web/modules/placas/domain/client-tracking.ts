// Domínio puro — visão de ACOMPANHAMENTO do cliente (5 marcos). Porta de solicitar-placa.

export const CLIENT_TRACKING_STEPS = [
  { title: 'Documentação em Análise', note: 'Sua documentação foi recebida e está sendo analisada pela equipe.' },
  { title: 'Documentação Aprovada', note: 'Documentação aprovada. Agende sua entrevista.' },
  { title: 'Entrevista Realizada', note: 'Entrevista concluída com sucesso.' },
  { title: 'Placa em Confecção', note: 'Sua placa está sendo produzida pela equipe.' },
  { title: 'Placa Enviada', note: 'Sua placa foi enviada! Acompanhe pelo código de rastreio.' },
] as const;

const AUDIT_STEP_INTERVIEW_SCHEDULED = 2;
const AUDIT_STEP_INTERVIEW_FINALIZED = 3;
const AUDIT_STEP_EM_CONFECCAO = 4;
const AUDIT_STEP_SHIPPED = 5;

export interface TrackingInput {
  status?: string | null;
  auditoria_step?: number | null;
  token?: string | null;
}

/** Índice do marco ativo (-1 = somente cadastro; -2 = rejeitado). Porta de getClientTrackingState. */
export function getClientTrackingState(data: TrackingInput): { activeIndex: number; rejected?: boolean } {
  const status = data?.status || '';
  const auditStep = Number(data?.auditoria_step ?? -1);

  if (status === 'cadastro_concluido') return { activeIndex: -1 };
  // Rejeitado precisa de representação própria: cair na timeline normal mostrava
  // "Documentação Aprovada" ativa — progresso falso para uma solicitação recusada.
  if (status === 'rejeitado') return { activeIndex: -2, rejected: true };

  const docsApproved = auditStep >= AUDIT_STEP_INTERVIEW_SCHEDULED || status === 'docs_aprovados' || status === 'concluido';
  const interviewDone = auditStep >= AUDIT_STEP_INTERVIEW_FINALIZED || status === 'concluido';
  const inProduction = auditStep >= AUDIT_STEP_EM_CONFECCAO || status === 'placa_postada' || status === 'concluido';
  const shipped = auditStep >= AUDIT_STEP_SHIPPED || status === 'placa_postada' || status === 'concluido';

  const doneFlags = [Boolean(data?.token || status), docsApproved, interviewDone, inProduction, shipped];
  let activeIndex = doneFlags.findIndex((done) => !done);
  if (activeIndex === -1) activeIndex = doneFlags.length - 1;
  return { activeIndex };
}
