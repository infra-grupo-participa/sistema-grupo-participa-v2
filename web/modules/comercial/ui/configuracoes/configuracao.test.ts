import { describe, expect, it } from 'vitest';
import type { Vendedor } from '../../domain/types';
import {
  aplicarRascunho, estadoDistribuicao, fmtMinutos, normalizarPercentual, previaSck, rascunhoDe, simularDistribuicao,
} from './configuracao';

const v = (id: string, percentual: number, p: Partial<Vendedor> = {}): Vendedor => ({
  id, nome: id, sigla: id.slice(0, 2).toUpperCase(), papel: 'vendedor', ativo: true, percentual, disparaApi: false, ...p,
});
const equipe = [v('gestor', 0, { papel: 'gestor' }), v('marcos', 50), v('ronan', 50)];

describe('rascunho da distribuição', () => {
  it('começa igual ao salvo e não está alterado', () => {
    const r = rascunhoDe(equipe);
    expect(estadoDistribuicao(equipe, r)).toEqual({ soma: 100, valida: true, alterada: false });
  });
  it('soma só os ativos e detecta alteração', () => {
    const r = { ...rascunhoDe(equipe), ronan: { percentual: 50, ativo: false } };
    expect(estadoDistribuicao(equipe, r)).toEqual({ soma: 50, valida: false, alterada: true });
    expect(aplicarRascunho(equipe, r).find((x) => x.id === 'ronan')!.ativo).toBe(false);
  });
});

describe('normalizarPercentual', () => {
  it('limita a 0–100 e arredonda', () => {
    expect(normalizarPercentual('')).toBe(0);
    expect(normalizarPercentual('abc')).toBe(0);
    expect(normalizarPercentual('150')).toBe(100);
    expect(normalizarPercentual('-3')).toBe(0);
    expect(normalizarPercentual('33,6')).toBe(34);
  });
});

describe('simularDistribuicao', () => {
  it('50/50 alterna entre os dois e ignora quem tem 0%', () => {
    const s = simularDistribuicao(equipe, 10);
    expect(s).toHaveLength(10);
    expect(s.filter((x) => x === 'marcos')).toHaveLength(5);
    expect(s.filter((x) => x === 'ronan')).toHaveLength(5);
    expect(s).not.toContain('gestor');
  });
  it('70/30 respeita a cota em 10 leads', () => {
    const s = simularDistribuicao([v('a', 70), v('b', 30)], 10);
    expect(s.filter((x) => x === 'a')).toHaveLength(7);
  });
  it('ninguém elegível → null', () => {
    expect(simularDistribuicao([v('a', 100, { ativo: false })], 2)).toEqual([null, null]);
  });
});

describe('fmtMinutos', () => {
  it('min, h e dias', () => {
    expect(fmtMinutos(null)).toBe('—');
    expect(fmtMinutos(5)).toBe('5 min');
    expect(fmtMinutos(90)).toBe('1,5 h');
    expect(fmtMinutos(12 * 60)).toBe('12 h');
    expect(fmtMinutos(24 * 60)).toBe('1 dia');
    expect(fmtMinutos(7 * 24 * 60)).toBe('7 dias');
  });
});

describe('previaSck', () => {
  it('monta produto-acao-data-canal-sigla; vazio sem ação ou sigla', () => {
    const d = new Date(2026, 9, 5);
    expect(previaSck('hm', 'Recuperação', 'WhatsApp', 'MP', d)).toBe('hm-recuperacao-20261005-whatsapp-mp');
    expect(previaSck('hm', ' ', 'whatsapp', 'MP', d)).toBeNull();
    expect(previaSck('hm', 'x', 'whatsapp', undefined, d)).toBeNull();
  });
});
