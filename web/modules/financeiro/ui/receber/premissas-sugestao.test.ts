// F3 (z67) — Premissas em R$, sugestão medida ao lado com a diferença, "Usar sugestão" e o liga/desliga da projeção.
// HTML estático (sem navegador): conteúdo, rótulos e nomes acessíveis. O clique que grava não se prova aqui.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { Premissas } from './Premissas';
import {
  diferencaDaSugestao, formatarFaixa, formatarPremissa, lerNumeroDigitado, normalizarSugestao, normalizarVigencia, validarPremissa,
  valorDaSugestao,
} from '../../domain/premissas-receber';

const V = (p: Record<string, unknown>) => normalizarVigencia({
  chave: 'venda_semanal:hm_avulso', chave_base: 'venda_semanal:hm_avulso', cenario: 'base',
  rotulo: 'Venda nova por semana — HM avulso', unidade: 'reais', minimo: 0, maximo: 5000000,
  grupo_tela: 'Vendas novas (estimado)', ajuda: 'Sem vigência gravada, vale a sugestão medida.', aceita_cenario: true,
  vigente_de: '2026-09-01', valor: 30000, fonte: null, criado_em: '2026-09-01T12:00:00Z', criado_por_nome: 'Fernanda', situacao: 'vigente', ...p,
});
const projecao = (valor: number) => V({
  chave: 'projecao_no_receber', chave_base: 'projecao_no_receber', rotulo: 'Projeção na previsão', unidade: 'liga_desliga',
  minimo: 0, maximo: 1, aceita_cenario: false, vigente_de: '2000-01-01', valor, criado_por_nome: null,
});
const reserva = V({
  chave: 'reserva_reembolso', chave_base: 'reserva_reembolso', rotulo: 'Reserva de reembolso e chargeback', unidade: 'percentual',
  minimo: 0, maximo: 0.2, aceita_cenario: true, situacao: 'vigente', vigente_de: '2026-09-01', valor: 0.05,
});
const sugestoes = [
  normalizarSugestao({ chave: 'venda_semanal:hm_avulso', rotulo: 'x', unidade: 'reais', sugestao: '28500.4', valor_efetivo: 30000,
    base_medida: 'Mediana de 12 semanas completas sem dia de evento (01/06/2026 a 20/09/2026)',
    medida: [{ semana: '2026-09-14', valor: 28000 }], origem: 'definido por Fernanda em 01/09/2026', vigente_de: '2026-09-01', cenario: 'base' }),
  normalizarSugestao({ chave: 'reserva_reembolso', rotulo: 'x', unidade: 'percentual', sugestao: '0.0389', valor_efetivo: 0.05,
    base_medida: 'Estornado ÷ vendido de 28/12/2025 a 27/09/2026', medida: { vendido: 1000, estornado: 38.9, de: '2025-12-28', ate: '2026-09-27' },
    origem: 'definido por Fernanda', vigente_de: '2026-09-01', cenario: 'base' }),
];
const repo = { salvarPremissaReceber: vi.fn(), salvarFeriado: vi.fn() };
const base = { feriados: [], erroPremissas: null, erroFeriados: null, hojeISO: '2026-09-28', repo };

describe('domínio — reais e sugestão', () => {
  it('reais: R$ na tela e na faixa; "30.000" é trinta mil (não 30)', () => {
    expect(formatarPremissa(30000, 'reais')).toMatch(/R\$\s30\.000,00/);
    expect(formatarFaixa({ minimo: 0, maximo: 5000000, unidade: 'reais' })).toMatch(/R\$\s0,00 a R\$\s5\.000\.000,00/);
    expect(lerNumeroDigitado('30.000', true)).toBe(30000);
    expect(lerNumeroDigitado('R$ 30.000,50', true)).toBe(30000.5);
    expect(lerNumeroDigitado('5.5')).toBe(5.5); // percentual continua com ponto decimal
    const v = validarPremissa({ minimo: 0, maximo: 5000000, unidade: 'reais', rotulo: 'x' }, '30.000', '2026-09-28', '2026-09-28');
    expect(v).toEqual({ ok: true, valor: 30000 });
  });
  it('medida: semanas (venda) e vendido/estornado (reserva)', () => {
    expect(sugestoes[0].semanas).toEqual([{ semana: '2026-09-14', valor: 28000 }]);
    expect(sugestoes[1].reserva).toEqual({ vendido: 1000, estornado: 38.9, de: '2025-12-28', ate: '2026-09-27' });
    expect(normalizarSugestao({ chave: 'venda_semanal:outros', sugestao: null, origem: 'sem base medida' }).sugestao).toBeNull();
  });
  it('valor gravado = o que a tela mostra; diferença em R$ e em p.p.', () => {
    expect(valorDaSugestao(28500.4049, 'reais')).toBe(28500.4);
    expect(valorDaSugestao(0.038949, 'percentual')).toBe(0.0389);
    expect(diferencaDaSugestao(30000, 28500.4, 'reais')).toMatch(/R\$\s1\.499,60 acima da sugestão/);
    expect(diferencaDaSugestao(0.05, 0.0389, 'percentual')).toBe('1,11 p.p. acima da sugestão');
    expect(diferencaDaSugestao(0.0389, 0.0389, 'percentual')).toBe('igual à sugestão');
    expect(diferencaDaSugestao(null, 1, 'reais')).toBeNull();
  });
});

describe('Premissas — sugestão medida e projeção', () => {
  const premissas = [projecao(0), V({}), reserva];
  const html = renderToStaticMarkup(createElement(Premissas, { ...base, premissas, canEdit: true, sugestoes }));
  it('ao lado da premissa: "Sugestão medida: X (base: …)" e a diferença', () => {
    expect(html).toMatch(/Sugestão medida: R\$\s28\.500,40 \(base: Mediana de 12 semanas/);
    expect(html).toMatch(/R\$\s1\.499,60 acima da sugestão/);
    expect(html).toContain('Sugestão medida: 3,89% (base: Estornado ÷ vendido');
    expect(html).toContain('1,11 p.p. acima da sugestão');
  });
  it('"Usar sugestão" por cenário, com nome acessível que diz o valor e "a partir de hoje"', () => {
    expect(html).toMatch(/aria-label="Usar sugestão: Venda nova por semana — HM avulso \(Base\) = R\$\s28\.500,40, a partir de hoje"/);
    expect(html).toContain('aria-label="Usar sugestão: Reserva de reembolso e chargeback (Conservador) = 3,89%, a partir de hoje"');
  });
  it('projeção desligada: diz o que a Semana a semana mostra e oferece ligar', () => {
    expect(html).toContain('Projeção na previsão');
    expect(html).toContain('Desligada: a Semana a semana mostra o certo');
    expect(html).toContain('Ligar a projeção a partir de hoje');
    expect(html).toContain('aria-pressed="false"');
  });
  it('projeção ligada: texto e botão de desligar', () => {
    const h = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: [projecao(1), V({})], canEdit: true, sugestoes }));
    expect(h).toContain('Ligada: vendas novas, eventos planejados');
    expect(h).toContain('Desligar a projeção a partir de hoje');
  });
  it('sem vigência gravada: "vale a sugestão medida", não "sem vigência hoje"; sem base medida dito como tal', () => {
    const semVig = [V({ situacao: 'futura', vigente_de: '2026-11-01' })];
    const h = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: semVig, canEdit: true, sugestoes }));
    expect(h).toMatch(/vale a sugestão medida \(R\$\s28\.500,40\)/);
    const sb = [normalizarSugestao({ chave: 'venda_semanal:hm_avulso', sugestao: null, base_medida: 'Nenhuma semana completa sem dia de evento nas últimas 52', origem: 'sem base medida' })];
    const h2 = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: semVig, canEdit: true, sugestoes: sb }));
    expect(h2).toContain('Sugestão medida: sem base medida (Nenhuma semana completa');
    expect(h2).toContain('sem vigência gravada e sem base medida');
    expect(h2).not.toContain('Usar sugestão');
  });
  it('vigência gravada hoje: sem "Usar sugestão" naquela linha (o banco recusaria a mesma data)', () => {
    const h = renderToStaticMarkup(createElement(Premissas, { ...base, premissas: [V({ vigente_de: '2026-09-28' })], canEdit: true,
      sugestoes: [sugestoes[0]] }));
    expect(h).not.toContain('Usar sugestão: Venda nova por semana — HM avulso (Base)');
  });
  it('somente leitura: sugestão visível, sem botões de escrita', () => {
    const h = renderToStaticMarkup(createElement(Premissas, { ...base, premissas, canEdit: false, sugestoes }));
    expect(h).toContain('Sugestão medida');
    expect(h).not.toContain('Usar sugestão');
    expect(h).not.toContain('Ligar a projeção');
  });
  it('sugestões carregando e erro separados; sem o pai pedir, nada aparece', () => {
    expect(renderToStaticMarkup(createElement(Premissas, { ...base, premissas, canEdit: true, sugestoes: null })))
      .toContain('Carregando sugestões medidas');
    const e = renderToStaticMarkup(createElement(Premissas, { ...base, premissas, canEdit: true, sugestoes: null,
      erroSugestoes: 'recurso ainda não disponível no banco.', onTentarDeNovo: () => {} }));
    expect(e).toContain('Sugestões medidas indisponíveis agora.');
    expect(e).toContain('Tentar de novo');
    expect(renderToStaticMarkup(createElement(Premissas, { ...base, premissas, canEdit: true }))).not.toContain('Sugestão medida');
  });
});
