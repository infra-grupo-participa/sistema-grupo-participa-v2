import { describe, expect, it } from 'vitest';
import { deveAvisarNoDesktop, emSilencio } from './regras-notificacao';
import type { PreferenciasNotificacao } from '../../domain/types';

const p: PreferenciasNotificacao = {
  vendedorId: 'v', desktop: true, silencioInicio: '20:00', silencioFim: '08:00',
  gatilhos: { lead_novo: true, lead_respondeu: false, prazo_estourado: true, venda_aprovada: true, ficha_para_aprovar: true, atividade_vencendo: true },
};
const as = (h: number, m = 0) => new Date(2026, 9, 5, h, m);

describe('notificações no desktop', () => {
  it('silêncio que vira a noite', () => {
    expect(emSilencio(p, as(21))).toBe(true);
    expect(emSilencio(p, as(7, 59))).toBe(true);
    expect(emSilencio(p, as(8))).toBe(false);
    expect(emSilencio(p, as(14))).toBe(false);
  });
  it('silêncio no mesmo dia e sem silêncio', () => {
    expect(emSilencio({ silencioInicio: '12:00', silencioFim: '13:00' }, as(12, 30))).toBe(true);
    expect(emSilencio({ silencioInicio: null, silencioFim: null }, as(3))).toBe(false);
  });
  it('respeita desktop, gatilho e silêncio', () => {
    expect(deveAvisarNoDesktop(p, 'lead_novo', as(10))).toBe(true);
    expect(deveAvisarNoDesktop(p, 'lead_respondeu', as(10))).toBe(false);
    expect(deveAvisarNoDesktop(p, 'lead_novo', as(22))).toBe(false);
    expect(deveAvisarNoDesktop({ ...p, desktop: false }, 'lead_novo', as(10))).toBe(false);
  });
});
