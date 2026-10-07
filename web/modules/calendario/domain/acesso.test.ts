import { describe, expect, it } from 'vitest';
import { podeVerCalendario } from './acesso';

describe('podeVerCalendario', () => {
  it('equipe ativa vê, qualquer cargo', () => {
    expect(podeVerCalendario({ email: 'Fulano@AdvMais.com', status: 'ativo' })).toBe(true);
  });
  it('fora do domínio, inativo ou sem usuário não vê', () => {
    expect(podeVerCalendario({ email: 'aluno@gmail.com', status: 'ativo' })).toBe(false);
    expect(podeVerCalendario({ email: 'fulano@advmais.com', status: 'pendente' })).toBe(false);
    expect(podeVerCalendario({ email: 'fulano@advmais.com.br', status: 'ativo' })).toBe(false);
    expect(podeVerCalendario(null)).toBe(false);
  });
});
