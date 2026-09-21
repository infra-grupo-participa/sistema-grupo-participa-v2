import { describe, it, expect } from 'vitest';
import { ehEmailDaEquipe } from './gp-user';

describe('ehEmailDaEquipe', () => {
  it('aceita o domínio da equipe, com ruído de caixa e espaço', () => {
    expect(ehEmailDaEquipe('isabela@advmais.com')).toBe(true);
    expect(ehEmailDaEquipe('  Isabela@AdvMais.com ')).toBe(true);
  });

  it('recusa aluno, lead e nulo', () => {
    expect(ehEmailDaEquipe('renan@raconsulting.adv.br')).toBe(false);
    expect(ehEmailDaEquipe('aluno@gmail.com')).toBe(false);
    expect(ehEmailDaEquipe(null)).toBe(false);
    expect(ehEmailDaEquipe('')).toBe(false);
  });

  it('recusa domínio parecido: sufixo extra, prefixo colado e subdomínio', () => {
    expect(ehEmailDaEquipe('x@advmais.com.br')).toBe(false);
    expect(ehEmailDaEquipe('x@fakeadvmais.com')).toBe(false);
    expect(ehEmailDaEquipe('x@sub.advmais.com')).toBe(false);
  });
});
