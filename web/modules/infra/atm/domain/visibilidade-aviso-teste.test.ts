import { describe, expect, it } from 'vitest';
import { ATM_TEST_NOTICE_USER_ID, deveExibirAvisoTesteAtm } from './visibilidade-aviso-teste';

describe('visibilidade do aviso de marcação de teste do ATM', () => {
  it('exibe o aviso só para o usuário configurado', () => {
    expect(deveExibirAvisoTesteAtm(ATM_TEST_NOTICE_USER_ID)).toBe(true);
    expect(deveExibirAvisoTesteAtm('outro-usuario')).toBe(false);
    expect(deveExibirAvisoTesteAtm(null)).toBe(false);
    expect(deveExibirAvisoTesteAtm(undefined)).toBe(false);
  });
});
