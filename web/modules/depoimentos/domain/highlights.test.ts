import { describe, it, expect } from 'vitest';
import { parseGroqHighlights, transcriptApto } from './highlights';

describe('highlights — parsing do Groq', () => {
  it('normaliza tipos, limita a 8 e corta textos', () => {
    const r = parseGroqHighlights({
      highlights: [
        { texto: 'a', tipo: 'gancho' },
        { texto: 'b', tipo: 'invalido' },
        { texto: '', tipo: 'citacao' },
      ],
      gancho: 'g',
      resumo: 'r',
      objecao: 'o',
      antes_depois: { antes: 'x', depois: 'y' },
    });
    expect(r.highlights).toHaveLength(2);
    expect(r.highlights[1].tipo).toBe('citacao'); // tipo inválido vira citacao
    expect(r.antes_depois).toEqual({ antes: 'x', depois: 'y' });
    expect(r.gancho).toBe('g');
  });

  it('campos vazios viram null e antes_depois vazio fica null', () => {
    const r = parseGroqHighlights({ highlights: [], gancho: '', antes_depois: { antes: '', depois: '' } });
    expect(r.gancho).toBeNull();
    expect(r.objecao).toBeNull();
    expect(r.antes_depois).toBeNull();
    expect(r.metricas).toEqual([]);
  });

  it('métricas: filtra vazias, limita a 6 e ausência vira array vazio', () => {
    const r = parseGroqHighlights({ highlights: [], metricas: ['R$ 50k em 3 meses', '', '  ', '2 para 15 clientes'] });
    expect(r.metricas).toEqual(['R$ 50k em 3 meses', '2 para 15 clientes']);
    expect(parseGroqHighlights({ highlights: [] }).metricas).toEqual([]);
  });

  it('transcriptApto exige >= 80 chars', () => {
    expect(transcriptApto('curto')).toBe(false);
    expect(transcriptApto('x'.repeat(80))).toBe(true);
  });
});
