// F3 (z67) — certo × estimado na grade, sem base visível, reserva negativa, informativo fora da soma e a composição
// "de onde veio". HTML estático (sem navegador): prova conteúdo e soma, não geometria.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ComposicaoCelula, ContasAReceber, GradeContasReceber } from './ContasAReceber';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import { composicaoDaCelula, normalizarLinhaReceber, type LinhaReceber } from '../../domain/contas-receber';

const L = (p: Partial<LinhaReceber>): LinhaReceber => ({
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: 0,
  situacao: 'a_receber', origem_dia: null, ref: null, rotulo: null, produto: null, k: null, detalhe: [], projecao: [], pagas: [],
  fator: 1, certeza: 'certo', centro_custo: null, tratamento: null, cenario: 'base', ...p, valor_bruto: p.valor_bruto ?? p.valor ?? 0,
});

// Linhas como o banco devolve (normalizadas pelo mesmo caminho do repositório).
const bruto: Record<string, unknown>[] = [
  { bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: '1000', situacao: 'a_receber', certeza: 'certo' },
  { bloco: 3, grupo: 'HM avulso', componente: 'antecipacao', data_caixa: '2026-09-30', valor: '500.50', situacao: 'a_receber',
    origem_dia: '2026-09-28', ref: 'vn:hm_avulso', rotulo: 'mediana 12 sem', certeza: 'estimado',
    tratamento: 'Antecipação D+2 útil · Venda nova por dia = valor semanal ÷ 7 (mediana 12 sem)',
    detalhe: [{ dia: '2026-09-28', valor_venda: 555.55, base: 'mediana 12 sem' }] },
  { bloco: 3, grupo: 'HM avulso', componente: 'garantia', data_caixa: '2026-10-28', valor: '55.56', situacao: 'a_receber',
    origem_dia: '2026-09-28', ref: 'vn:hm_avulso', rotulo: 'mediana 12 sem', certeza: 'estimado', detalhe: null },
  { bloco: 3, grupo: 'Outros produtos', componente: 'cheio', data_caixa: null, valor: null, valor_bruto: null, situacao: 'sem_base',
    ref: 'vn:outros', rotulo: 'sem base', certeza: 'estimado',
    tratamento: 'Sem sugestão medida (nenhuma semana completa sem evento em 52) e sem premissa: grupo fora da projeção' },
  { bloco: 4, grupo: 'Black Friday', componente: 'antecipacao', data_caixa: '2026-10-02', valor: '2000', situacao: 'a_receber',
    origem_dia: '2026-09-30', ref: 'ep:7', rotulo: 'Referência: Acelera 2025', certeza: 'estimado',
    detalhe: [{ dia: '2026-09-30', valor_venda: 2222.22, base: 'curva Acelera 2025' }] },
  { bloco: 6, grupo: 'Reserva de reembolso e chargeback', componente: 'reserva', data_caixa: '2026-09-30', valor: '-19.47',
    situacao: 'a_receber', ref: 'reserva', rotulo: 'taxa medida em 9 meses', certeza: 'estimado', centro_custo: '3. (Devoluções)',
    tratamento: 'Reserva 3,89% sobre as vendas novas estimadas do dia (blocos 3 e 4; base R$ 500,50) · taxa medida em 9 meses' },
  { bloco: 8, grupo: 'Informativo: acordos no board', componente: 'cheio', data_caixa: '2026-10-01', origem_dia: '2026-10-01',
    valor: '7000', situacao: 'informativo', ref: '123', rotulo: 'Pessoa Board', produto: 'Holding Masters', certeza: 'informativo',
    tratamento: 'Saldo combinado no board: informativo, fora da soma' },
];
const linhas = bruto.map(normalizarLinhaReceber);
const dados = montarContasReceber(linhas, '2026-09-28');
const g = dados.grade;

describe('domínio — certo × estimado × informativo', () => {
  it('normaliza o detalhe dos blocos 3/4 em `projecao`, NULL da garantia vira []', () => {
    expect(linhas[1].projecao).toEqual([{ dia: '2026-09-28', valor_venda: 555.55, base: 'mediana 12 sem' }]);
    expect(linhas[1].detalhe).toEqual([]);
    expect(linhas[2].projecao).toEqual([]);
    expect(linhas[0].projecao).toEqual([]);
  });
  it('subtotais: certo 1.000; estimado 500,50 + 55,56 + 2.000 − 19,47; total = soma dos dois; informativo fora', () => {
    expect(g.certoTotal).toBe(1000);
    expect(g.estimadoTotal).toBe(2536.59);
    expect(g.total).toBe(3536.59);
    expect(g.certoPorSemana.map((v, i) => Math.round((v + g.estimadoPorSemana[i]) * 100))).toEqual(g.totalPorSemana.map((v) => Math.round(v * 100)));
    expect(g.informativo?.total).toBe(7000);
    expect(g.informativo?.linhas).toBe(1);
  });
  it('sem base: listado por grupo, fora da soma e fora de "sem data de caixa"', () => {
    expect(g.semBase).toEqual([{ bloco: 3, grupo: 'Outros produtos', secao: 'estimado', tratamento: expect.stringContaining('Sem sugestão medida') }]);
    expect(g.semDataCaixa.linhas).toBe(0);
    expect(g.linhas.some((l) => l.grupo === 'Outros produtos')).toBe(false);
  });
  it('composição do informativo lê as linhas informativo (e só elas)', () => {
    expect(composicaoDaCelula(linhas, null, 8, 'Informativo: acordos no board').map((l) => l.rotulo)).toEqual(['Pessoa Board']);
    expect(composicaoDaCelula(linhas, null, 3, 'Outros produtos')).toEqual([]);
  });
  it('sem nenhuma linha estimada: estimado 0, informativo null, semBase vazio', () => {
    const d = montarContasReceber([L({ valor: 10 })], '2026-09-28');
    expect(d.grade.estimadoTotal).toBe(0);
    expect(d.grade.informativo).toBeNull();
    expect(d.grade.semBase).toEqual([]);
  });
});

describe('grade — seções, subtotais, reserva negativa, sem base e informativo', () => {
  const html = renderToStaticMarkup(createElement(GradeContasReceber, { grade: g, selecionada: null, onSelecionar: () => {} }));
  it('seções Certo e Estimado com subtotais e total geral nesta ordem', () => {
    const ordem = ['Certo', '1. Vendas já realizadas', 'Subtotal certo', 'Estimado', '3. Vendas novas', '4. Eventos planejados',
      '6. Reserva de reembolso e chargeback', 'Subtotal estimado', 'Total da semana (certo + estimado)', 'Informativo — fora da soma'];
    const pos = ordem.map((t) => html.indexOf(t));
    expect(pos.every((p) => p >= 0)).toBe(true);
    expect([...pos].sort((a, b) => a - b)).toEqual(pos);
  });
  it('reserva aparece negativa; total geral soma certo + estimado; informativo NÃO entra no total', () => {
    expect(html).toMatch(/-R\$\s19,47/);
    expect(html).toMatch(/R\$\s3\.536,59/);
    expect(html).toMatch(/R\$\s7\.000,00/); // na faixa informativa
    expect(html).not.toMatch(/R\$\s10\.536,59/);
  });
  it('grupo sem base: "sem base medida" com o porquê, nunca R$ 0,00', () => {
    expect(html).toContain('Outros produtos');
    expect(html).toContain('sem base medida');
    expect(html).toContain('nenhuma semana completa sem evento');
    expect(html).not.toMatch(/R\$\s0,00/);
  });
  it('bloco 6 com um grupo só vira uma linha (sem repetir o nome do grupo)', () => {
    expect(html.match(/Reserva de reembolso e chargeback/g)).toHaveLength(1);
  });
  it('sem estimado: a seção diz que não há valor estimado e onde ligar; sem subtotais', () => {
    const d = montarContasReceber([L({ valor: 10 })], '2026-09-28');
    const h = renderToStaticMarkup(createElement(GradeContasReceber, { grade: d.grade, selecionada: null, onSelecionar: () => {} }));
    expect(h).toContain('Nenhum valor estimado nesta previsão. A projeção liga e desliga em Premissas.');
    expect(h).not.toContain('Subtotal');
    expect(h).toContain('Total da semana');
    expect(h).not.toContain('Informativo — fora da soma');
  });
});

describe('composição — de onde veio', () => {
  const comp = (bloco: number, grupo: string) => renderToStaticMarkup(createElement(ComposicaoCelula, {
    linhas, pagasPorRef: dados.pagasPorRef, celula: { bloco, grupo, semana: null }, semana: null, onFechar: () => {},
  }));
  it('bloco 3: base do valor, venda do dia e a base de cada venda; garantia sem repetir a lista', () => {
    const h = comp(3, 'HM avulso');
    expect(h).toContain('De onde veio');
    expect(h).toContain('mediana 12 sem');
    expect(h).toMatch(/R\$\s555,55/);
    expect(h).toContain('Retido 10% (volta em D+30)');
    expect(h.match(/555,55/g)).toHaveLength(1);
  });
  it('bloco 4: referência e curva do evento', () => {
    const h = comp(4, 'Black Friday');
    expect(h).toContain('Referência: Acelera 2025');
    expect(h).toContain('curva Acelera 2025');
  });
  it('bloco 6: valor negativo, origem do percentual e a base em R$ no tratamento', () => {
    const h = comp(6, 'Reserva de reembolso e chargeback');
    expect(h).toMatch(/-R\$\s19,47/);
    expect(h).toContain('taxa medida em 9 meses');
    expect(h).toContain('base R$ 500,50');
  });
  it('bloco 8: nome, produto, vencimento e "fora da soma"', () => {
    const h = comp(8, 'Informativo: acordos no board');
    expect(h).toContain('Pessoa Board');
    expect(h).toContain('Holding Masters');
    expect(h).toContain('fora da soma');
  });
});

describe('tela — legenda e sub-aba Eventos', () => {
  it('legenda de escopo diz certo, estimado e informativo; legenda do cenário conferida contra o banco', () => {
    const t = renderToStaticMarkup(createElement(ContasAReceber, { dados, onCenario: () => {} }));
    expect(t).toContain('Estimado: vendas novas, eventos planejados e reserva de reembolso');
    expect(t).toContain('fora da soma');
    expect(t).toContain('O cenário muda o estimado');
    expect(t).toContain('No certo, muda só a perda mensal');
  });
  it('sub-aba Eventos no tablist e painel com ?ver=eventos (carregando, sem consulta própria)', () => {
    const t = renderToStaticMarkup(createElement(ContasAReceber, { dados, sub: 'eventos' }));
    expect(t).toContain('id="receber-tab-eventos"');
    expect(t).toContain('id="receber-painel-eventos"');
    expect(t).toContain('Carregando eventos planejados');
  });
});
