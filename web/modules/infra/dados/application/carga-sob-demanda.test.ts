import { describe, expect, it, vi } from 'vitest';
import { deveCarregar } from './carga-sob-demanda';

describe('deveCarregar', () => {
  it('abrir o modal no estado ocioso chama a função uma vez', () => {
    let estado: { resultado: unknown; carregando: boolean } = { resultado: null, carregando: false };
    const carregar = vi.fn();
    const abrir = () => { if (!deveCarregar(estado)) return; estado = { resultado: null, carregando: true }; carregar(); };
    abrir(); abrir();
    expect(carregar).toHaveBeenCalledTimes(1);
    estado = { resultado: { data: [] }, carregando: false };
    abrir();
    expect(carregar).toHaveBeenCalledTimes(1);
  });
  it('estado ocioso pede carga; carregando ou com resultado não', () => {
    expect(deveCarregar({ resultado: null, carregando: false })).toBe(true);
    expect(deveCarregar({ resultado: null, carregando: true })).toBe(false);
    expect(deveCarregar({ resultado: { data: [] }, carregando: false })).toBe(false);
  });
});
