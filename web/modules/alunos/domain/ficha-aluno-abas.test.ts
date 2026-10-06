import { describe, expect, it } from 'vitest';
import { lerHashFicha, montarHashFicha } from './ficha-aluno-abas';

describe('hash da ficha do aluno', () => {
  it('ida e volta', () => {
    const h = montarHashFicha('0b6c-uuid', 'jornada');
    expect(h).toBe('#aluno=0b6c-uuid&aba=jornada');
    expect(lerHashFicha(h)).toEqual({ alunoId: '0b6c-uuid', aba: 'jornada' });
  });
  it('sem aluno → null; aba estranha → aba null', () => {
    expect(lerHashFicha('')).toBeNull();
    expect(lerHashFicha('#responsaveis')).toBeNull();
    expect(lerHashFicha('#aluno=abc&aba=<script>')).toEqual({ alunoId: 'abc', aba: null });
    expect(lerHashFicha('#aluno=abc')).toEqual({ alunoId: 'abc', aba: null });
  });
  it('aba Histórico (pedidos de alteração) entra no link', () => {
    expect(montarHashFicha('abc', 'historico')).toBe('#aluno=abc&aba=historico');
    expect(lerHashFicha('#aluno=abc&aba=historico')).toEqual({ alunoId: 'abc', aba: 'historico' });
  });
});
