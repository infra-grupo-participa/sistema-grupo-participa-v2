import { describe, expect, it } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import * as demo from '../infrastructure/demo';
import { PainelAchados, PainelFluxo, PainelTestesAB, SecaoConnect, SecaoLab, SecaoLeads } from './paineis-fase2';
import { PainelCalor } from './MapaCalor';
import { VereditoComparar } from './Comparar';
import { SEM_DADOS } from './paineis';
import type { Melhorias } from '../domain/tipos';

const DE = '2026-09-29';
const ATE = '2026-10-05';
const html = (el: ReturnType<typeof createElement>) => renderToStaticMarkup(el);

describe('telas da fase 2 com os dados de demonstração', () => {
  it('fluxo: entradas/saídas, de onde para onde, caminhos', () => {
    const h = html(createElement(PainelFluxo, { f: demo.demoFluxo(DE, ATE) }));
    expect(h).toContain('De onde para onde');
    expect(h).toContain('Saiu do site');
    expect(h).toContain('AK1 › Obrigado');
  });
  it('melhorias: achados com selo e testes A/B do ak1 x ak1-b', () => {
    const m = demo.demoMelhorias(DE, ATE);
    const a = html(createElement(PainelAchados, { m }));
    expect(a).toContain('Achados automáticos');
    expect(a).toContain('primeira dobra');
    const t = html(createElement(PainelTestesAB, { m, hoje: ATE }));
    expect(t).toContain('Teste AK1');
    expect(t).toContain('ak1-b');
  });
  it('comparar, mapa de calor, laboratório, leads, connect rate', () => {
    expect(html(createElement(VereditoComparar, { r: demo.demoComparar('AK1', DE, ATE, 'AK1 B', DE, ATE) }))).toContain('Taxa de lead por aparelho');
    const c = html(createElement(PainelCalor, { c: demo.demoCalor('mobile'), camada: 'cliques' }));
    expect(c).toContain('Mais clicados');
    expect(c).toContain('Sem fundo');
    expect(html(createElement(SecaoLab, { lab: demo.demoLab() }))).toContain('falhou (HTTP 429)');
    const l = html(createElement(SecaoLeads, { l: demo.demoLeads() }));
    expect(l).toContain('/comercial?pessoa=');
    expect(l).not.toContain('@');
    expect(html(createElement(SecaoConnect, { c: demo.demoConnect(DE, ATE) }))).toContain('Connect rate');
  });
});

describe('estado vazio e sem as migrations vizinhas', () => {
  const vazio = (): Melhorias => ({ de: DE, ate: ATE, antes_de: DE, antes_ate: ATE,
    atual: { sessoes: 0, leads: 0, dias: 0, paginas: [], leituras: [] }, antes: { sessoes: 0, leads: 0, dias: 0, paginas: [] } });
  it('fluxo, melhorias e mapa de calor dizem "sem dados ainda"', () => {
    for (const t of [
      html(createElement(PainelFluxo, { f: { sessoes: 0, uma_pagina: 0, passos_medio: 0, nomes: {}, paginas: [], passagens: [], caminhos: [] } })),
      html(createElement(PainelAchados, { m: vazio() })),
      html(createElement(PainelTestesAB, { m: vazio() })),
      html(createElement(PainelCalor, { c: { ...demo.demoCalor('mobile'), visitas: 0 }, camada: 'cliques' })),
    ]) expect(t).toContain(SEM_DADOS);
  });
  it('sem a base de pessoas (20261005o) e sem o Tráfego (20261005p) a tela explica e não quebra', () => {
    const l = html(createElement(SecaoLeads, { l: { base: false, pode_abrir: false, leads_web: 3, navegadores_lead: 3, com_ref: 0, pessoas: null, mql: null, nao_mql: null, lista: [] } }));
    expect(l).toContain('20261005o');
    expect(l).not.toContain('/comercial?pessoa=');
    expect(html(createElement(SecaoConnect, { c: { trafego: false, cliques_link: false, campanhas: [], sem_campanha: null, anuncios: [] } }))).toContain('20261005p');
  });
});
