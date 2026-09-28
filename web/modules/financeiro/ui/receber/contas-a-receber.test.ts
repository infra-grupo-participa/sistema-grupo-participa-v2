// Grade de Contas a Receber em HTML estático (renderToStaticMarkup, sem navegador). Prova conteúdo, não geometria:
// sticky da 1ª coluna e rolagem horizontal só se provam em navegador que pinta.
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { ComposicaoCelula, ContasAReceber, GradeContasReceber } from './ContasAReceber';
import { Recorrencias } from './Recorrencias';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import type { LinhaReceber } from '../../domain/contas-receber';

const L = (p: Partial<LinhaReceber>): LinhaReceber => ({
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: 0,
  situacao: 'a_receber', origem_dia: null, ref: null, rotulo: null, produto: null, k: null, detalhe: [], pagas: [], fator: 1, certeza: 'certo', centro_custo: null, tratamento: null, cenario: 'base', ...p, valor_bruto: p.valor_bruto ?? p.valor ?? 0,
});

const linhas: LinhaReceber[] = [
  L({ data_caixa: '2026-09-29', valor: 865.01, origem_dia: '2026-09-25',
    detalhe: [{ transacao: 'HP123', produto: 'Holding Masters', nome: 'Pessoa A', liquido: 1000 }] }),
  L({ data_caixa: '2026-10-26', valor: 100, componente: 'garantia', origem_dia: '2026-09-25',
    detalhe: [{ transacao: 'HP123', produto: 'Holding Masters', nome: 'Pessoa A', liquido: 1000 }] }),
  L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'x|3', rotulo: 'Pessoa B', produto: 'Holding Masters',
    origem_dia: '2026-10-01', data_caixa: '2026-10-05', valor: 1238.05 }),
  L({ bloco: 2, grupo: 'Assinaturas Serviço Diamante', ref: 'y|2', rotulo: 'Pessoa C', produto: 'Serviço Diamante',
    origem_dia: '2026-09-20', data_caixa: '2026-09-22', valor: 500, situacao: 'realizada' }),
  L({ bloco: 2, grupo: 'Outras assinaturas', ref: 'z|1', rotulo: 'Pessoa D', origem_dia: '2026-09-10',
    data_caixa: '2026-09-29', valor: 300, situacao: 'em_atraso_fora' }),
];
const dados = montarContasReceber(linhas, '2026-09-28');

describe('grade Contas a Receber (HTML estático)', () => {
  const html = renderToStaticMarkup(createElement(GradeContasReceber, { grade: dados.grade, selecionada: null, onSelecionar: () => {} }));

  it('colunas: meses e semanas cortadas na virada do mês', () => {
    expect(html).toContain('set/2026');
    expect(html).toContain('out/2026');
    expect(html).toContain('S1</span>28–30/09');
    expect(html).toContain('S2</span>01–04/10');
  });
  it('linhas: bloco 1 numa linha só; bloco 2 com subtotal e grupos; totais', () => {
    expect(html).toContain('1. Vendas já realizadas');
    expect(html).toContain('2. Assinaturas e parcelas futuras');
    expect(html).toContain('Parcelas a vencer HM');
    expect(html).toContain('Total da semana');
    expect(html).toContain('Total do mês');
    expect(html).toContain('Acumulado');
  });
  it('R$ pt-BR com centavos; realizada e fora da projeção NÃO entram na grade', () => {
    expect(html).toContain('R$ 865,01');
    expect(html).toContain('R$ 2.203,06'); // total = 865,01 + 100 + 1.238,05
    expect(html).not.toContain('500,00');
    expect(html).not.toContain('300,00');
    expect(html).not.toContain('Assinaturas Serviço Diamante');
  });
  it('sem cor hex no HTML (só tokens)', () => {
    expect(html).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
  });

  it('a tela inteira: legenda de escopo, grade e Recorrências (nunca "Carteira" nem "devendo")', () => {
    const tela = renderToStaticMarkup(createElement(ContasAReceber, { dados }));
    expect(tela).toContain('Só dinheiro já vendido, contratado ou informado pelo financeiro');
    expect(tela).toContain('Recorrências');
    expect(tela).not.toMatch(/carteira|devendo/i);
  });
});

describe('composição da célula (sem consulta nova)', () => {
  it('bloco 1: as vendas do dia do detalhe', () => {
    const html = renderToStaticMarkup(createElement(ComposicaoCelula, {
      linhas, celula: { bloco: 1, grupo: 'Vendas já realizadas', semana: 0 }, semana: dados.grade.semanas[0], onFechar: () => {},
    }));
    expect(html).toContain('HP123');
    expect(html).toContain('Pessoa A');
    expect(html).toContain('Antecipação (D+2)');
    expect(html).toContain('R$ 1.000,00'); // líquido da venda
    expect(html).toContain('R$ 865,01'); // o que cai
    expect(html).not.toContain('Retido 10% (volta em D+30)'); // o retido cai em outra semana
  });
  it('bloco 2: as cobranças, com nome, produto, data prevista e valor', () => {
    const html = renderToStaticMarkup(createElement(ComposicaoCelula, {
      linhas, celula: { bloco: 2, grupo: 'Parcelas a vencer HM', semana: null }, semana: null, onFechar: () => {},
    }));
    expect(html).toContain('Pessoa B');
    expect(html).toContain('Holding Masters');
    expect(html).toContain('01/10/2026');
    expect(html).toContain('R$ 1.238,05');
  });
});

describe('Recorrências', () => {
  it('todas as situações, com rótulo próprio', () => {
    const html = renderToStaticMarkup(createElement(Recorrencias, { cobrancas: dados.recorrencias }));
    expect(html).toContain('Pessoa B');
    expect(html).toContain('Pessoa C');
    expect(html).toContain('Pessoa D');
    expect(html).toContain('A receber');
    expect(html).toContain('Realizada');
    expect(html).toContain('Fora da projeção');
  });
});

describe('cálculo de recebimento desligado', () => {
  it('bloco 1 vazio e bloco 2 sem data de caixa: aviso no lugar da grade zerada', () => {
    const d = montarContasReceber([
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'e|o', rotulo: 'Pessoa B', origem_dia: '2026-10-01', data_caixa: null, valor: 1500, k: 2, componente: 'cheio' }),
    ], '2026-09-28');
    expect(d.desligado).toBe(true);
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados: d }));
    expect(html).toContain('Cálculo de recebimento desligado');
    expect(html).not.toContain('Total da semana');
    expect(html).not.toContain('R$ 0,00');
    // Recorrências continuam (têm vencimento) — agora numa sub-aba própria.
    const recHtml = renderToStaticMarkup(createElement(ContasAReceber, { dados: d, sub: 'recorrencias' }));
    expect(recHtml).toContain('Pessoa B');
  });
});

describe('Recorrências — contrato do bloco 2', () => {
  it('coluna Vencimento (origem_dia) e "—" em Cai no caixa para realizada/fora (cheio, data NULL)', () => {
    const d = montarContasReceber([
      L({ bloco: 2, grupo: 'Outras assinaturas', ref: 'e|o', rotulo: 'Pessoa E', origem_dia: '2026-09-10', data_caixa: null, valor: 70, componente: 'cheio', situacao: 'realizada' }),
    ], '2026-09-28');
    const html = renderToStaticMarkup(createElement(Recorrencias, { cobrancas: d.recorrencias }));
    expect(html).toContain('Vencimento');
    expect(html).toContain('10/09/2026');
    expect(html).toContain('>—</td>');
  });
});

describe('F2 — bruto × esperado, tratamento, pagas do contrato e cenário', () => {
  const lp = [
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'x|3', rotulo: 'Pessoa B', produto: 'Holding Masters', origem_dia: '2026-10-01',
      data_caixa: '2026-10-05', valor: 950, valor_bruto: 1000, fator: 0.95, tratamento: 'Antecipação D+2 útil · Perda 5%/mês × 1 mês',
      pagas: [{ transacao: 'HP777', n: 2, dia: '2026-09-01', liquido: 1000 }] }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'x|3', rotulo: 'Pessoa B', produto: 'Holding Masters', origem_dia: '2026-10-01',
      data_caixa: '2026-10-06', componente: 'garantia', valor: 95, valor_bruto: 100, fator: 0.95, tratamento: 'Retido 10% volta em D+30' }),
  ];
  const d = montarContasReceber(lp, '2026-09-28');
  it('grade: célula mostra o esperado e, com perda, o bruto em texto', () => {
    const html = renderToStaticMarkup(createElement(GradeContasReceber, { grade: d.grade, selecionada: null, onSelecionar: () => {} }));
    expect(html).toMatch(/R\$\s1\.045,00/);
    expect(html).toMatch(/bruto R\$\s1\.100,00/);
  });
  it('composição do bloco 2: bruto, fator, esperado, tratamento e as transações pagas (sem e-mail)', () => {
    const html = renderToStaticMarkup(createElement(ComposicaoCelula, {
      linhas: d.linhas, celula: { bloco: 2, grupo: 'Parcelas a vencer HM', semana: null }, semana: null, onFechar: () => {},
    }));
    expect(html).toMatch(/Bruto R\$\s1\.100,00 · esperado R\$\s1\.045,00/);
    expect(html).toContain('× 0,9500');
    expect(html).toContain('Perda 5%/mês × 1 mês');
    expect(html).toContain('HP777');
    expect(html).toContain('1 transação paga do contrato');
    expect(html.match(/HP777/g)).toHaveLength(1); // a garantia é a mesma cobrança: não repete a lista
    expect(html).not.toContain('@');
  });
  it('seletor de cenário só com o pai; dados null = "carregando o cenário" sem derrubar a aba', () => {
    expect(renderToStaticMarkup(createElement(ContasAReceber, { dados: d }))).not.toContain('Cenário');
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados: null, cenario: 'conservador', onCenario: () => {} }));
    expect(html).toContain('Cenário');
    expect(html).toMatch(/aria-pressed="true"[^>]*>Conservador/);
    expect(html).toContain('Carregando o cenário');
    expect(html).toContain('conservador e otimista usam o da base');
  });
  it('Recorrências: coluna Esperado só quando há perda', () => {
    expect(renderToStaticMarkup(createElement(Recorrencias, { cobrancas: d.recorrencias }))).toContain('Esperado');
    expect(renderToStaticMarkup(createElement(Recorrencias, { cobrancas: dados.recorrencias }))).not.toContain('Esperado');
  });
  it('sub-aba Premissas existe no tablist e abre com ?ver=premissas', () => {
    const html = renderToStaticMarkup(createElement(ContasAReceber, { dados: d, sub: 'premissas' }));
    expect(html).toContain('id="receber-tab-premissas"');
    expect(html).toContain('id="receber-painel-premissas"');
    expect(html).toContain('Carregando premissas');
  });
});
