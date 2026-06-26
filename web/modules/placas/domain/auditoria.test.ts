import { describe, it, expect } from 'vitest';
import {
  AUDIT_STEP_INDEX,
  AUDIT_STEP_TOTAL,
  AUDIT_STEPS,
  emailEventForAuditStep,
  isAuditCompletedStep,
  isProcessoConcluido,
  normalizeAuditEncerrado,
  planAuditAdvance,
  statusForAuditStep,
  type AdvancePlan,
} from './auditoria';

describe('auditoria — máquina de estados', () => {
  it('tem 7 etapas e índice final = PLACA_RECEBIDA', () => {
    expect(AUDIT_STEP_TOTAL).toBe(7);
    expect(AUDIT_STEPS).toHaveLength(7);
    expect(AUDIT_STEP_INDEX.PLACA_RECEBIDA).toBe(6);
    expect(AUDIT_STEPS[0].key).toBe('documentacao_em_analise');
    expect(AUDIT_STEPS[6].key).toBe('placa_recebida');
  });

  it('isAuditCompletedStep só na etapa final', () => {
    expect(isAuditCompletedStep(5)).toBe(false);
    expect(isAuditCompletedStep(6)).toBe(true);
    expect(isAuditCompletedStep(7)).toBe(true);
  });

  it('isProcessoConcluido respeita status legado', () => {
    expect(isProcessoConcluido(3, 'concluido')).toBe(true); // status terminal vence
    expect(isProcessoConcluido(6, 'placa_postada')).toBe(false); // enviada, não recebida
    expect(isProcessoConcluido(6, null)).toBe(true);
    expect(isProcessoConcluido(5, null)).toBe(false);
  });

  it('normalizeAuditEncerrado ignora encerrado na etapa final', () => {
    expect(normalizeAuditEncerrado(2, true)).toBe(true);
    expect(normalizeAuditEncerrado(6, true)).toBe(false);
    expect(normalizeAuditEncerrado(2, false)).toBe(false);
  });
});

describe('auditoria — transição de etapa', () => {
  it('statusForAuditStep mapeia status legados corretos', () => {
    expect(statusForAuditStep(0)).toBe('em_auditoria');
    expect(statusForAuditStep(1)).toBe('docs_aprovados');
    expect(statusForAuditStep(5)).toBe('placa_postada');
    expect(statusForAuditStep(6)).toBe('concluido');
  });

  it('emailEventForAuditStep só dispara nos 3 eventos reais', () => {
    expect(emailEventForAuditStep(1)).toBe('docs_aprovados');
    expect(emailEventForAuditStep(3)).toBe('entrevista_finalizada');
    expect(emailEventForAuditStep(5)).toBe('placa_em_caminho');
    expect(emailEventForAuditStep(2)).toBeNull();
    expect(emailEventForAuditStep(6)).toBeNull();
  });

  it('planAuditAdvance bloqueia etapa final, agendamento e falta de rastreio', () => {
    expect(planAuditAdvance(6)).toEqual({ blocked: 'concluido' });
    expect(planAuditAdvance(1)).toEqual({ blocked: 'aguardando_agendamento' });
    expect(planAuditAdvance(4, { hasCodigoRastreio: false })).toEqual({ blocked: 'sem_rastreio' });
  });

  it('planAuditAdvance 0→1 carimba documentacao e envia docs_aprovados', () => {
    const plan = planAuditAdvance(0) as AdvancePlan;
    expect(plan.novoStep).toBe(1);
    expect(plan.novoStatus).toBe('docs_aprovados');
    expect(plan.stampStepKey).toBe('documentacao_em_analise');
    expect(plan.emailEvent).toBe('docs_aprovados');
    expect(plan.removeInterviewSlot).toBe(false);
  });

  it('planAuditAdvance 2→3 finaliza entrevista e remove slot', () => {
    const plan = planAuditAdvance(2) as AdvancePlan;
    expect(plan.novoStep).toBe(3);
    expect(plan.emailEvent).toBe('entrevista_finalizada');
    expect(plan.removeInterviewSlot).toBe(true);
  });

  it('planAuditAdvance 4→5 exige rastreio e envia placa_em_caminho', () => {
    const plan = planAuditAdvance(4, { hasCodigoRastreio: true }) as AdvancePlan;
    expect(plan.novoStep).toBe(5);
    expect(plan.novoStatus).toBe('placa_postada');
    expect(plan.emailEvent).toBe('placa_em_caminho');
  });

  it('planAuditAdvance 5→6 conclui', () => {
    const plan = planAuditAdvance(5) as AdvancePlan;
    expect(plan.novoStep).toBe(6);
    expect(plan.novoStatus).toBe('concluido');
    expect(plan.emailEvent).toBeNull();
  });
});
