import { describe, expect, it } from 'vitest';
import { inicialAvatar } from './avatar-inicial';

describe('inicialAvatar', () => {
  it('primeira letra do nome', () => {
    expect(inicialAvatar('ana souza')).toBe('A');
    expect(inicialAvatar('  Élida')).toBe('É');
  });
  it('pula pontuação do começo', () => {
    expect(inicialAvatar('"Dr." Paulo')).toBe('D');
    expect(inicialAvatar('+55 11 98765')).toBe('5');
  });
  it('sem nome vira ícone (null), nunca pontuação', () => {
    expect(inicialAvatar('(sem nome)')).toBeNull();
    expect(inicialAvatar('')).toBeNull();
    expect(inicialAvatar(null)).toBeNull();
    expect(inicialAvatar('—')).toBeNull();
    expect(inicialAvatar('?')).toBeNull();
  });
});
