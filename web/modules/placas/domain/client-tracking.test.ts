import { describe, it, expect } from 'vitest';
import { getClientTrackingState } from './client-tracking';

describe('client-tracking — marco ativo', () => {
  it('cadastro_concluido → -1', () => {
    expect(getClientTrackingState({ status: 'cadastro_concluido' }).activeIndex).toBe(-1);
  });
  it('submetido (em_auditoria) → marco 0 feito, marco 1 ativo (aguardando aprovação)', () => {
    expect(getClientTrackingState({ status: 'em_auditoria', auditoria_step: 0 }).activeIndex).toBe(1);
  });
  it('docs aprovados (step 2) → entrevista é o próximo', () => {
    expect(getClientTrackingState({ status: 'docs_aprovados', auditoria_step: 2 }).activeIndex).toBe(2);
  });
  it('placa enviada → último marco', () => {
    expect(getClientTrackingState({ status: 'placa_postada', auditoria_step: 5 }).activeIndex).toBe(4);
  });
  it('concluído → todos os marcos feitos (último ativo)', () => {
    expect(getClientTrackingState({ status: 'concluido', auditoria_step: 6 }).activeIndex).toBe(4);
  });
});
