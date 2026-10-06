import { describe, expect, it } from 'vitest';
import { alturaDoFundo, cor, ehMorto, ehRaiva, forcaPonto, fracaoAlcance, posicao } from './calor';
import { destinosPorOrigem, rotuloCaminho, textoCaminho } from './fluxo';
import { resumirGoogle, urlGoogle } from '../../../../../infra/supabase/functions/mkt-web-pagespeed/resumo';

describe('mapa de calor (calor.ts do Radar)', () => {
  it('escala do frio ao quente e posição do ponto', () => {
    expect(cor(0)).toEqual([37, 84, 232]);
    expect(cor(1)).toEqual([210, 59, 59]);
    expect(posicao(50, 0.25, 400, 8000)).toEqual({ x: 200, y: 2000 });
    expect(posicao(10, 2, 100, 100).y).toBe(100);
    expect(ehRaiva(3) && ehMorto(3) && !ehRaiva(2)).toBe(true);
    expect(forcaPonto(1000, false)).toBe(0.14);
    expect(fracaoAlcance([200, 150, 50], 1)).toBe(0.75);
  });
  it('altura do fundo: proporção da captura; sem ela, a da página', () => {
    expect(alturaDoFundo(400, { largura: 412, altura: 8240 }, 390, 9000)).toBe(8000);
    expect(alturaDoFundo(390, null, 390, 9000)).toBe(9000);
  });
});

describe('fluxo', () => {
  it('rótulos e destinos por origem', () => {
    const nomes = { '/ak1/': 'AK1' };
    expect(rotuloCaminho('/ak1/', nomes)).toBe('AK1 (/ak1/)');
    expect(rotuloCaminho('(saiu)', nomes)).toBe('Saiu do site');
    expect(textoCaminho(['/ak1/', '/x/'], true, nomes)).toBe('AK1 › /x/ › …');
    const d = destinosPorOrigem({ sessoes: 10, uma_pagina: 5, passos_medio: 1, nomes, paginas: [], caminhos: [],
      passagens: [{ de: '/ak1/', para: '(saiu)', n: 6, leads: 0 }, { de: '/ak1/', para: '/obrigado/', n: 2, leads: 2 }, { de: '/obrigado/', para: '(saiu)', n: 2, leads: 2 }] });
    expect(d[0].de).toBe('/ak1/');
    expect(d[0].destinos[0]).toMatchObject({ para: '(saiu)', fatia: 0.75 });
  });
});

describe('resumo do Google (Edge mkt-web-pagespeed)', () => {
  it('notas, métricas, até 5 oportunidades e a captura', () => {
    const audits: Record<string, unknown> = {
      'largest-contentful-paint': { numericValue: 4123.6 }, 'first-contentful-paint': { numericValue: 1800 },
      'total-blocking-time': { numericValue: 250 }, 'speed-index': { numericValue: 3000 }, 'cumulative-layout-shift': { numericValue: 0.0456 },
    };
    for (let i = 0; i < 7; i++) audits['op' + i] = { title: 'Op ' + i, details: { type: 'opportunity', overallSavingsMs: i * 100 } };
    audits['nao'] = { title: 'Diagnóstico', details: { type: 'table' } };
    const r = resumirGoogle({ lighthouseResult: {
      categories: { performance: { score: 0.54 }, accessibility: { score: 0.9 }, 'best-practices': { score: null }, seo: { score: 1 } },
      audits, fullPageScreenshot: { screenshot: { data: 'data:image/jpeg;base64,AAA', width: 412, height: 8000 } } } });
    expect(r.nota).toBe(54);
    expect(r.notas).toEqual({ desempenho: 54, acessibilidade: 90, seo: 100 });
    expect(r.lcp_ms).toBe(4124);
    expect(r.cls).toBe(0.046);
    expect(r.oportunidades.map((o) => o.id)).toEqual(['op6', 'op5', 'op4', 'op3', 'op2']);
    expect(r.captura).toEqual({ img: 'data:image/jpeg;base64,AAA', largura: 412, altura: 8000 });
    expect(resumirGoogle({}).nota).toBeNull();
  });
  it('URL com as 4 categorias; a chave só quando existe', () => {
    expect(urlGoogle('https://exemplo.invalid/a/', 'mobile')).not.toContain('key=');
    expect(urlGoogle('https://exemplo.invalid/a/', 'desktop', 'k')).toContain('&key=k');
    expect(urlGoogle('https://exemplo.invalid/a/', 'mobile').match(/category=/g)).toHaveLength(4);
  });
});
