import { describe, expect, it } from 'vitest';
import { idsAba, indiceAbaPorTecla, rotuloPendencias } from './tabs-teclado';

describe('indiceAbaPorTecla', () => {
  it('setas circulam nas pontas', () => {
    expect(indiceAbaPorTecla('ArrowRight', 0, 4)).toBe(1);
    expect(indiceAbaPorTecla('ArrowRight', 3, 4)).toBe(0);
    expect(indiceAbaPorTecla('ArrowLeft', 0, 4)).toBe(3);
  });
  it('Home/End', () => {
    expect(indiceAbaPorTecla('Home', 2, 4)).toBe(0);
    expect(indiceAbaPorTecla('End', 0, 4)).toBe(3);
  });
  it('Esc, Tab, Enter e setas verticais não são da aba (seguem borbulhando)', () => {
    for (const k of ['Escape', 'Tab', 'Enter', 'ArrowUp', 'ArrowDown']) expect(indiceAbaPorTecla(k, 1, 4)).toBeNull();
  });
  it('lista vazia', () => {
    expect(indiceAbaPorTecla('ArrowRight', 0, 0)).toBeNull();
  });
});

describe('idsAba / rotuloPendencias', () => {
  it('ids casados', () => {
    expect(idsAba('f', 'jornada')).toEqual({ tab: 'f-tab-jornada', panel: 'f-panel-jornada' });
  });
  it('singular e plural', () => {
    expect(rotuloPendencias(1)).toBe('1 pendência');
    expect(rotuloPendencias(3)).toBe('3 pendências');
  });
});
