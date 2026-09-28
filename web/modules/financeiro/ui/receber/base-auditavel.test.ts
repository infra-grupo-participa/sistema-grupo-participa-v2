// F5 — Base auditável (#receber?ver=base): filtro, soma só do a_receber, contagem do que não soma, resumo centro de
// custo × mês e o CSV nos 2 níveis de dado pessoal. HTML estático (sem navegador): prova conteúdo e soma, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ContasAReceber } from './ContasAReceber';
import { BaseAuditavel, LINHAS_POR_PAGINA } from './BaseAuditavel';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import { normalizarLinhaReceber } from '../../domain/contas-receber';
import {
  csvBaseAuditavel, dataCsv, FILTRO_BASE_PADRAO, fatorCsv, filtrarBase, moedaCsv, nomeArquivoCsvBase, opcoesBase,
  resumoCentroMes, SEM_VALOR, somarBase, TODOS,
} from './base-auditavel';

const HOT = '1. Receita de vendas (Hotmart)';
const DIR = '4. Receita de vendas (Direta de clientes)';
const DEV = '3. (Devoluções)';

// Linhas como o banco devolve (normalizadas pelo mesmo caminho do repositório).
const bruto: Record<string, unknown>[] = [
  { bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: '1000', situacao: 'a_receber',
    certeza: 'certo', centro_custo: HOT, tratamento: 'Antecipação D+2 útil (90% − 3,89%)', detalhe: [{ transacao: 'HP1', nome: 'Comprador Um', liquido: 1100 }] },
  { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', data_caixa: '2026-10-05', valor: '85.74', valor_bruto: '100',
    fator: '0.857375', situacao: 'a_receber', origem_dia: '2026-10-03', ref: 'opaca-A', rotulo: 'Ana Silva', produto: 'Holding Masters',
    certeza: 'certo', centro_custo: HOT, tratamento: 'Antecipação D+2 útil · Perda 5%/mês' },
  { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'garantia', data_caixa: '2026-11-03', valor: '10', situacao: 'a_receber',
    origem_dia: '2026-10-03', ref: 'opaca-A', rotulo: 'Ana Silva', produto: 'Holding Masters', certeza: 'certo', centro_custo: HOT },
  { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', data_caixa: null, valor: '300', situacao: 'realizada',
    origem_dia: '2026-09-01', ref: 'opaca-B', rotulo: '=Bruno HYPERLINK', produto: 'Holding Masters', certeza: 'certo', centro_custo: HOT,
    tratamento: 'Paga: sai da previsão' },
  { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', data_caixa: null, valor: '200', situacao: 'em_atraso_fora',
    origem_dia: '2026-07-01', ref: 'opaca-C', rotulo: 'Carla; Souza', certeza: 'certo', centro_custo: HOT },
  { bloco: 5, grupo: 'Renovações Diamante', componente: 'cheio', data_caixa: '2026-10-10', valor: '5000', situacao: 'a_receber',
    ref: '11', rotulo: 'Cliente Direto', certeza: 'certo', centro_custo: DIR, tratamento: 'Fora da Hotmart: entra cheio na data' },
  { bloco: 3, grupo: 'Outros produtos', componente: 'cheio', data_caixa: null, valor: null, valor_bruto: null, situacao: 'sem_base',
    ref: 'vn:outros', rotulo: 'sem base', certeza: 'estimado', centro_custo: HOT, tratamento: 'Sem sugestão medida' },
  { bloco: 3, grupo: 'HM avulso', componente: 'antecipacao', data_caixa: '2026-10-01', valor: '500.50', situacao: 'a_receber',
    ref: 'vn:hm_avulso', rotulo: 'mediana 12 sem', certeza: 'estimado', centro_custo: HOT, tratamento: 'Venda nova (mediana 12 sem)' },
  { bloco: 6, grupo: 'Reserva de reembolso e chargeback', componente: 'reserva', data_caixa: '2026-10-01', valor: '-19.47',
    situacao: 'a_receber', ref: 'reserva', rotulo: 'taxa medida em 9 meses', certeza: 'estimado', centro_custo: DEV },
  { bloco: 8, grupo: 'Informativo: acordos no board', componente: 'cheio', data_caixa: '2026-10-01', valor: '7000',
    situacao: 'informativo', ref: '11', rotulo: 'Pessoa Board', produto: 'Aurum', certeza: 'informativo', centro_custo: null },
];
const linhas = bruto.map(normalizarLinhaReceber);
const dados = montarContasReceber(linhas, '2026-09-28');

describe('filtrarBase', () => {
  it('padrão = a_receber: 6 linhas, ordenadas por data de caixa', () => {
    const f = filtrarBase(linhas, FILTRO_BASE_PADRAO);
    expect(f.map((l) => l.data_caixa)).toEqual(['2026-09-29', '2026-10-01', '2026-10-01', '2026-10-05', '2026-10-10', '2026-11-03']);
    expect(f.every((l) => l.situacao === 'a_receber')).toBe(true);
  });
  it('todas: as 10 linhas, sem data de caixa no fim', () => {
    const f = filtrarBase(linhas, { ...FILTRO_BASE_PADRAO, situacao: TODOS });
    expect(f).toHaveLength(10);
    expect(f.slice(-3).every((l) => l.data_caixa == null)).toBe(true);
  });
  it('bloco, centro (inclusive "sem centro"), certeza, busca sem acento e período', () => {
    const t = { ...FILTRO_BASE_PADRAO, situacao: TODOS } as const;
    expect(filtrarBase(linhas, { ...t, bloco: '2' })).toHaveLength(4);
    expect(filtrarBase(linhas, { ...t, centro: DIR }).map((l) => l.rotulo)).toEqual(['Cliente Direto']);
    expect(filtrarBase(linhas, { ...t, centro: SEM_VALOR }).map((l) => l.bloco)).toEqual([8]);
    expect(filtrarBase(linhas, { ...t, certeza: 'estimado' })).toHaveLength(3);
    expect(filtrarBase(linhas, { ...t, busca: 'ANA silva' })).toHaveLength(2);
    expect(filtrarBase(linhas, { ...t, busca: 'devolucoes' }).map((l) => l.bloco)).toEqual([6]);
    // Período: linha sem data de caixa sai; limites inclusivos.
    expect(filtrarBase(linhas, { ...t, de: '2026-10-01', ate: '2026-10-05' }).map((l) => l.data_caixa))
      .toEqual(['2026-10-01', '2026-10-01', '2026-10-01', '2026-10-05']);
  });
  it('opções saem das linhas (nada some por lista fixa)', () => {
    const o = opcoesBase(linhas);
    expect(o.blocos).toEqual([1, 2, 3, 5, 6, 8]);
    expect(o.centros).toEqual([HOT, DIR, DEV]);
    expect(o.temSemCentro).toBe(true);
  });
});

describe('somarBase — só a_receber soma; o resto é contado', () => {
  it('todas as situações: soma = a_receber; realizada, atraso, sem base e informativo só contam', () => {
    const s = somarBase(filtrarBase(linhas, { ...FILTRO_BASE_PADRAO, situacao: TODOS }));
    // 1000 + 85,74 + 10 + 5000 + 500,50 − 19,47
    expect(s.aReceber).toEqual({ linhas: 6, valor: 6576.77, bruto: 6591.03 });
    expect(s.foraDaSoma).toEqual([
      { situacao: 'realizada', linhas: 1 }, { situacao: 'em_atraso_fora', linhas: 1 },
      { situacao: 'sem_base', linhas: 1 }, { situacao: 'informativo', linhas: 1 },
    ]);
  });
  it('filtro só com linhas que não somam: soma zero linhas', () => {
    const s = somarBase(filtrarBase(linhas, { ...FILTRO_BASE_PADRAO, situacao: 'informativo' }));
    expect(s.aReceber.linhas).toBe(0);
    expect(s.aReceber.valor).toBe(0);
  });
});

describe('resumoCentroMes', () => {
  it('3 centros de entrada na ordem 1, 4, 3; mês da data de caixa; devolução negativa; total = soma', () => {
    const r = resumoCentroMes(filtrarBase(linhas, { ...FILTRO_BASE_PADRAO, situacao: TODOS }));
    expect(r.meses).toEqual(['2026-09', '2026-10', '2026-11']);
    expect(r.linhas.map((l) => l.centro)).toEqual([HOT, DIR, DEV]);
    expect(r.linhas[0].porMes).toEqual([1000, 586.24, 10]);
    expect(r.linhas[1].porMes).toEqual([0, 5000, 0]);
    expect(r.linhas[2].porMes).toEqual([0, -19.47, 0]);
    expect(r.total).toBe(6576.77);
    expect(r.totalPorMes).toEqual([1000, 5566.77, 10]);
    expect(r.semData.linhas).toBe(0); // realizada/atraso/sem_base sem data não entram: não somam
  });
  it('centro desconhecido e NULL em a_receber entram depois dos 3, nunca somem', () => {
    const extra = [
      ...linhas,
      normalizarLinhaReceber({ bloco: 9, grupo: 'X', componente: 'cheio', data_caixa: '2026-10-02', valor: '1', situacao: 'a_receber', centro_custo: '9. Outro' }),
      normalizarLinhaReceber({ bloco: 9, grupo: 'Y', componente: 'cheio', data_caixa: '2026-10-02', valor: '2', situacao: 'a_receber' }),
    ];
    const r = resumoCentroMes(extra.filter((l) => l.situacao === 'a_receber'));
    expect(r.linhas.map((l) => l.centro)).toEqual([HOT, DIR, DEV, '9. Outro', null]);
    expect(r.total).toBe(6579.77);
  });
});

describe('CSV', () => {
  const todas = filtrarBase(linhas, { ...FILTRO_BASE_PADRAO, situacao: TODOS });
  const semanas = dados.grade.semanas;
  const linhasCsv = (s: string) => s.replace(/^﻿/, '').split('\r\n');

  it('BOM, separador ;, decimal vírgula, datas dd/mm/aaaa, cabeçalho com as colunas', () => {
    const csv = csvBaseAuditavel(todas, semanas, 'completo', 'Base');
    expect(csv.startsWith('﻿')).toBe(true);
    const [cab, l1] = linhasCsv(csv);
    expect(cab).toBe('Data de caixa;Semana;Bloco;Grupo;Componente;Descrição;Produto;Valor esperado;Valor bruto;Fator;Centro de custo;Certeza;Situação;Tratamento;Cenário');
    expect(l1.split(';').slice(0, 2)).toEqual(['29/09/2026', 'S1']);
    expect(l1).toContain(';1000,00;1000,00;1;');
  });
  it('perda: esperado, bruto e fator com vírgula; reserva negativa sem apóstrofo', () => {
    const csv = csvBaseAuditavel(todas, semanas, 'completo', 'Base');
    expect(csv).toContain(';85,74;100,00;0,857375;');
    expect(csv).toContain(';-19,47;-19,47;1;');
    expect(csv).not.toContain("'-19");
  });
  it('sem base: valores VAZIOS, não zero', () => {
    const l = linhasCsv(csvBaseAuditavel(todas, semanas, 'completo', 'Base')).find((x) => x.includes('Sem base medida'))!;
    expect(l.split(';').slice(7, 9)).toEqual(['', '']);
  });
  it('completo: nome como veio, texto de terceiro neutralizado (fórmula e ;)', () => {
    const csv = csvBaseAuditavel(todas, semanas, 'completo', 'Base');
    expect(csv).toContain('Ana Silva');
    expect(csv).toContain("'=Bruno HYPERLINK");
    expect(csv).toContain('"Carla; Souza"');
  });
  it('sem dado pessoal: nenhum nome dos blocos 2, 5 e 8; Pessoa N estável por ref; base do cálculo mantida', () => {
    const csv = csvBaseAuditavel(todas, semanas, 'sem_dado_pessoal', 'Base');
    for (const nome of ['Ana Silva', 'Bruno', 'Carla', 'Cliente Direto', 'Pessoa Board']) expect(csv).not.toContain(nome);
    for (const ref of ['opaca-A', 'opaca-B', 'opaca-C']) expect(csv).not.toContain(ref);
    const ls = linhasCsv(csv).slice(1).map((x) => x.split(';'));
    const desc = (pred: (c: string[]) => boolean) => ls.filter(pred).map((c) => c[5]);
    // Ana tem 2 linhas (antecipação e retido): o mesmo número nas duas.
    const ana = desc((c) => c[3] === 'Parcelas a vencer HM' && c[12] === 'A receber');
    expect(ana).toHaveLength(2);
    expect(new Set(ana).size).toBe(1);
    expect(ana[0]).toMatch(/^Pessoa \d+$/);
    // Bloco 5 e bloco 8 com a mesma ref '11' são cadastros diferentes: números diferentes.
    const b5 = desc((c) => c[2].startsWith('5.'))[0];
    const b8 = desc((c) => c[2].startsWith('8.'))[0];
    expect(b5).not.toBe(b8);
    expect(csv).toContain('mediana 12 sem');
    expect(csv).toContain('taxa medida em 9 meses');
    // O detalhe do bloco 1 (nome do comprador) nunca vai ao CSV, em nenhum nível.
    expect(csvBaseAuditavel(todas, semanas, 'completo', 'Base')).not.toContain('Comprador Um');
  });
  it('formatadores e nome do arquivo', () => {
    expect(dataCsv('2026-12-31')).toBe('31/12/2026');
    expect(dataCsv(null)).toBe('');
    expect(moedaCsv(1234.5)).toBe('1234,50');
    expect(fatorCsv(1)).toBe('1');
    expect(nomeArquivoCsvBase('2026-09-28', 'conservador', 'sem_dado_pessoal')).toBe('previsao-caixa-base-auditavel-2026-09-28-conservador-sem-dado-pessoal.csv');
    expect(nomeArquivoCsvBase('2026-09-28', 'base', 'completo')).toBe('previsao-caixa-base-auditavel-2026-09-28-base-completo.csv');
  });
});

describe('tela', () => {
  it('sub-aba base: tabpanel, caption, th scope, filtros com label, soma e contagem fora da soma', () => {
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados, sub: 'base' }));
    expect(html).toContain('id="receber-painel-base"');
    expect(html).toContain('Base auditável');
    expect(html).toContain('<caption');
    expect(html).toContain('scope="col"');
    expect(html).toContain('scope="row"');
    for (const r of ['Situação', 'Bloco', 'Centro de custo', 'Certeza', 'Buscar', 'Caixa de', 'Caixa até', 'Dado pessoal']) {
      expect(html).toMatch(new RegExp(`<label[^>]*>${r}<`));
    }
    expect(html).toContain('Soma a receber (6 linhas)');
    expect(html).toContain('R$ 6.576,77');
    expect(html).toContain('Entradas por centro de custo × mês');
    expect(html).toContain('Exportar CSV (6)');
  });
  it('carregando o cenário: não quebra, avisa', () => {
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados: null, sub: 'base' }));
    expect(html).toContain('Carregando o cenário');
  });
  it(`paginada acima de ${LINHAS_POR_PAGINA} linhas: só a 1ª página no DOM`, () => {
    const muitas = Array.from({ length: 450 }, (_, i) => normalizarLinhaReceber({
      bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-10-01', valor: '1',
      situacao: 'a_receber', centro_custo: HOT, tratamento: `t${i}`,
    }));
    const html = renderToStaticMarkup(createElement(BaseAuditavel, { dados: montarContasReceber(muitas, '2026-09-28'), rotuloCenario: 'Base' }));
    expect(html).toContain('Página 1 de 3');
    expect((html.match(/<tr class="border-t border-\[var\(--border-faint\)\] text-/g) ?? []).length).toBe(LINHAS_POR_PAGINA + 3); // + 3 centros no resumo
    expect(html).toContain('Soma a receber (450 linhas)');
  });
});
