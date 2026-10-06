import { describe, expect, it } from 'vitest';
import { etiquetaEncontrada, filtrarEtiquetas } from './etiquetas';

// Exemplos do painel de KPIs citados na revisão do Victor (06/10/2026); fontes de exemplo.
const TODAS = [
  { etiqueta: 'seminario-atm', fontes: ['kpi'] },
  { etiqueta: 'seminario-conjunto', fontes: ['kpi'] },
  { etiqueta: 'seminario-conjunto-2026-11', fontes: ['kpi'] },
  { etiqueta: 'seminario-conjunto-2026-11', fontes: ['trafego'] },
  { etiqueta: 'seminario-zanella', fontes: ['kpi'] },
  { etiqueta: 'black-friday-2026-10', fontes: ['trafego'] },
  { etiqueta: 'Fora Do Formato', fontes: ['kpi'] },
];

describe('busca de etiqueta do ClickUp', () => {
  it('"seminario" acha as que contêm, sem repetir e juntando as fontes', () => {
    const r = filtrarEtiquetas(TODAS, 'seminario');
    expect(r.map((e) => e.etiqueta)).toEqual(['seminario-atm', 'seminario-conjunto', 'seminario-conjunto-2026-11', 'seminario-zanella']);
    expect(r[2].fontes).toEqual(['kpi', 'trafego']);
  });
  it('sem acento e sem diferença de maiúscula', () => {
    expect(filtrarEtiquetas(TODAS, 'SEMINÁRIO-Z').map((e) => e.etiqueta)).toEqual(['seminario-zanella']);
  });
  it('igual ao digitado primeiro, depois as que começam com ele', () => {
    expect(filtrarEtiquetas(TODAS, 'seminario-conjunto').map((e) => e.etiqueta)).toEqual(['seminario-conjunto', 'seminario-conjunto-2026-11']);
    expect(filtrarEtiquetas(TODAS, '2026').map((e) => e.etiqueta)).toEqual(['black-friday-2026-10', 'seminario-conjunto-2026-11']);
  });
  it('fora do formato da chave não entra; limite respeitado', () => {
    expect(filtrarEtiquetas(TODAS, 'fora')).toEqual([]);
    expect(filtrarEtiquetas(TODAS, '', 2)).toHaveLength(2);
  });
  it('etiqueta digitada que não está na lista: não encontrada', () => {
    const r = filtrarEtiquetas(TODAS, 'seminario-novo-2027-01');
    expect(etiquetaEncontrada(r, 'seminario-novo-2027-01')).toBe(false);
    expect(etiquetaEncontrada(filtrarEtiquetas(TODAS, 'seminario-atm'), 'seminario-atm')).toBe(true);
    expect(etiquetaEncontrada(null, 'x')).toBe(true);
    expect(etiquetaEncontrada([], '')).toBe(true);
  });
});
