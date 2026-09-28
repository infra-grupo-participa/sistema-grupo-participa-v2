// Sub-aba Premissas em HTML estático (sem navegador): conteúdo, rótulos e permissões. Clique, foco e teclado não se
// provam aqui.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { Premissas } from './Premissas';
import { normalizarFeriado, normalizarVigencia } from '../../domain/premissas-receber';

const V = (p: Record<string, unknown>) => normalizarVigencia({
  chave: 'perda_mensal:parcelas_hm', chave_base: 'perda_mensal:parcelas_hm', cenario: 'base',
  rotulo: 'Perda mensal — Parcelas a vencer HM', unidade: 'percentual', minimo: 0, maximo: 0.5,
  grupo_tela: 'Perda por inadimplência', ajuda: 'Esperado = valor × (1 − perda)^k', aceita_cenario: true,
  vigente_de: '2000-01-01', valor: 0.05, fonte: 'planilha', criado_em: null, criado_por_nome: null, situacao: 'vigente', ...p,
});
const premissas = [
  V({}),
  V({ vigente_de: '2026-11-01', valor: 0.07, situacao: 'futura', criado_por_nome: 'Fernanda' }),
  V({ chave: 'tolerancia_atraso_dias', chave_base: 'tolerancia_atraso_dias', rotulo: 'Tolerância de atraso', unidade: 'dias',
    minimo: 0, maximo: 30, grupo_tela: 'Recorrências e informados', aceita_cenario: false, valor: 5 }),
];
const feriados = [
  normalizarFeriado({ dia: '2026-12-25', nome: 'Natal', ativo: true, fonte: 'carga z60' }),
  normalizarFeriado({ dia: '2027-01-01', nome: 'Confraternização', ativo: true }),
];
const repo = { salvarPremissaReceber: vi.fn(), salvarFeriado: vi.fn() };
const base = { premissas, feriados, erroPremissas: null, erroFeriados: null, hojeISO: '2026-09-28', repo };

describe('Premissas', () => {
  const html = renderToStaticMarkup(createElement(Premissas, { ...base, canEdit: true }));
  it('agrupada por grupo_tela; percentual em %, dias em dias; ajuda e faixa', () => {
    expect(html).toContain('Perda por inadimplência');
    expect(html).toContain('Recorrências e informados');
    expect(html).toContain('>5%<');
    expect(html).toContain('5 dias');
    expect(html).toContain('0% a 50%');
    expect(html).toContain('Esperado = valor × (1 − perda)^k');
    expect(html).not.toContain('0,05');
  });
  it('cenário sem valor próprio diz que usa a base; próxima vigência visível', () => {
    expect(html).toContain('Conservador');
    expect(html).toContain('usa a base (5%)');
    expect(html).toContain('próxima: 7% a partir de 01/11/2026');
    expect(html).toContain('Histórico (2)');
  });
  it('canEdit: botão Alterar com nome acessível; feriados do ano corrente, com Desligar', () => {
    expect(html).toContain('aria-label="Alterar: Perda mensal — Parcelas a vencer HM (Conservador)"');
    expect(html).toContain('Natal');
    expect(html).not.toContain('Confraternização'); // 2027: filtro de ano começa no ano corrente
    expect(html).toContain('>Desligar<');
    expect(html).toContain('Adicionar feriado');
  });
  it('sem canEdit: somente leitura, sem botões de escrita', () => {
    const ro = renderToStaticMarkup(createElement(Premissas, { ...base, canEdit: false }));
    expect(ro).toContain('Somente leitura');
    expect(ro).not.toContain('>Alterar<');
    expect(ro).not.toContain('>Desligar<');
    expect(ro).not.toContain('Adicionar feriado');
  });
  it('carregando e erro separados (erro nunca vira lista vazia)', () => {
    const c = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: null, feriados: null, canEdit: true }));
    expect(c).toContain('Carregando premissas');
    expect(c).toContain('Carregando feriados');
    const e = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: null, erroPremissas: 'Não foi possível carregar as premissas.', canEdit: true, onTentarDeNovo: () => {} }));
    expect(e).toContain('role="alert"');
    expect(e).toContain('Tentar de novo');
    expect(e).not.toContain('Nenhuma premissa');
  });
});
