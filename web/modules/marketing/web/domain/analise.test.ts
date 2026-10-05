import { describe, expect, it } from 'vitest';
import {
  apelidoSecao, codigoCurto, compararTaxas, duracao, faixaVital, maiorPerda, maisFraco, msVital, nivelDe, nomeOrigem, pct,
} from './analise';
import { diasEntre, somaDias, ultimosDias, validarPeriodo } from './periodo';

describe('estatística (porte do estatistica.ts do Radar)', () => {
  it('selo pela amostra e pela diferença', () => {
    expect(nivelDe(3, 150)).toBe('forte');
    expect(nivelDe(3, 50)).toBe('provavel');
    expect(nivelDe(2, 40)).toBe('provavel');
    expect(nivelDe(2, 20)).toBe('fraco');
    expect(nivelDe(-2.6, 100)).toBe('forte');
  });
  it('duas taxas: 10% x 20% com 1.000 de cada lado é forte', () => {
    const c = compararTaxas(100, 1000, 200, 1000);
    expect(c.a).toBeCloseTo(0.1);
    expect(c.b).toBeCloseTo(0.2);
    expect(c.relativa).toBeCloseTo(1);
    expect(c.z).toBeGreaterThan(5);
    expect(c.confiavel).toBe(true);
    expect(c.nivel).toBe('forte');
  });
  it('amostra pequena fica "fraco" mesmo com diferença grande', () => {
    const c = compararTaxas(1, 10, 5, 10);
    expect(c.poucas).toBe(true);
    expect(c.nivel).toBe('fraco');
  });
  it('sem total não divide por zero', () => {
    const c = compararTaxas(0, 0, 0, 0);
    expect(c.z).toBe(0);
    expect(c.nivel).toBe('fraco');
  });
  it('o achado leva o selo mais fraco', () => {
    expect(maisFraco('forte', 'provavel')).toBe('provavel');
    expect(maisFraco('forte', 'fraco', 'provavel')).toBe('fraco');
    expect(maisFraco()).toBe('forte');
  });
});

describe('funil', () => {
  it('acha a passagem que mais perde', () => {
    expect(maiorPerda([{ sessoes: 1000 }, { sessoes: 400 }, { sessoes: 300 }, { sessoes: 50 }])).toBe(3);
    expect(maiorPerda([{ sessoes: 100 }, { sessoes: 10 }, { sessoes: 9 }])).toBe(1);
  });
  it('etapa anterior zerada não conta; uma etapa só = -1', () => {
    expect(maiorPerda([{ sessoes: 0 }, { sessoes: 0 }])).toBe(-1);
    expect(maiorPerda([{ sessoes: 10 }])).toBe(-1);
  });
});

describe('seções', () => {
  it('vocabulário da casa, número e nome arrumado', () => {
    expect(apelidoSecao('padrao')).toBe('O caminho padrão');
    expect(apelidoSecao('#oque')).toBe('O que é');
    expect(apelidoSecao('sec-3')).toBe('Seção 3');
    expect(apelidoSecao('como_funciona')).toBe('Como funciona');
    expect(apelidoSecao('historia-da-familia')).toBe('História da família');
  });
});

describe('origem', () => {
  it('utm_source em palavras', () => {
    expect(nomeOrigem('ig')).toBe('Instagram · Meta Ads');
    expect(nomeOrigem('GoogleAds')).toBe('Google Ads');
    expect(nomeOrigem(null)).toBe('Direto, sem UTM');
    expect(nomeOrigem('(direto)')).toBe('Direto, sem UTM');
    expect(nomeOrigem('parceiro-x')).toBe('parceiro-x');
  });
  it('id longo do anúncio fica curto', () => {
    expect(codigoCurto('120212345678901234')).toBe('…678901234');
    expect(codigoCurto('ak1')).toBe('ak1');
  });
});

describe('velocidade (régua do Google)', () => {
  it('LCP, INP e CLS nas três faixas', () => {
    expect(faixaVital('lcp', 2500)).toBe('bom');
    expect(faixaVital('lcp', 3000)).toBe('melhorar');
    expect(faixaVital('lcp', 4001)).toBe('ruim');
    expect(faixaVital('inp', 180)).toBe('bom');
    expect(faixaVital('inp', 600)).toBe('ruim');
    expect(faixaVital('cls', 0.1)).toBe('bom');
    expect(faixaVital('cls', 0.2)).toBe('melhorar');
    expect(faixaVital('cls', null)).toBeNull();
  });
  it('formato dos números', () => {
    expect(msVital(2100)).toBe('2,1 s');
    expect(msVital(180)).toBe('180 ms');
    expect(msVital(null)).toBe('–');
    expect(duracao(8000)).toBe('8 s');
    expect(duracao(65000)).toBe('1 min 05 s');
    expect(pct(1, 3)).toBe('33,3%');
    expect(pct(1, 0)).toBe('–');
  });
});

describe('período', () => {
  it('últimos 7 dias incluem hoje', () => {
    expect(ultimosDias(7, '2026-10-05')).toEqual({ de: '2026-09-29', ate: '2026-10-05' });
    expect(somaDias('2026-02-28', 1)).toBe('2026-03-01');
    expect(diasEntre('2026-10-01', '2026-10-05')).toBe(4);
  });
  it('valida como o banco (máx. 92 dias)', () => {
    expect(validarPeriodo({ de: '2026-10-01', ate: '2026-10-05' })).toBeNull();
    expect(validarPeriodo({ de: '2026-10-05', ate: '2026-10-01' })).toMatch(/antes/);
    expect(validarPeriodo({ de: '2026-01-01', ate: '2026-10-05' })).toMatch(/92/);
    expect(validarPeriodo({ de: '', ate: '2026-10-05' })).toMatch(/datas/);
  });
});
