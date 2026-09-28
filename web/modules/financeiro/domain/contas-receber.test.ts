import { describe, expect, it } from 'vitest';
import {
  agregarReceber, cobrancasRecorrentes, composicaoDaCelula, DIAS_MINIMOS_SEMANA, fimDoMes, GRUPOS_BLOCO_5, normalizarLinhaReceber, pagasPorContrato,
  periodoReceber, recebimentoDesligado, semanas,
  type LinhaReceber,
} from './contas-receber';

const L = (p: Partial<LinhaReceber>): LinhaReceber => ({
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29', valor: 0,
  situacao: 'a_receber', origem_dia: null, ref: null, rotulo: null, produto: null, k: null, detalhe: [], projecao: [], pagas: [], fator: 1, certeza: 'certo', centro_custo: null, tratamento: null, cenario: 'base', ...p, valor_bruto: p.valor_bruto ?? p.valor ?? 0,
});

describe('semanas — seg a dom, cortada no mês; pedaço < 4 dias unido à vizinha do mesmo mês', () => {
  const lim = (xs: { inicio: string; fim: string }[]) => xs.map((x) => `${x.inicio.slice(5)}..${x.fim.slice(5)}`);
  // Período da planilha do financeiro (aba Fluxo Semanal): 24/09 (quinta) → 31/12/2026 (quinta).
  const s = semanas('2026-09-24', '2026-12-31');
  it('reproduz exatamente os 15 limites da planilha (S1 24–30/09 … S15 28–31/12)', () => {
    expect(DIAS_MINIMOS_SEMANA).toBe(4);
    expect(lim(s)).toEqual([
      '09-24..09-30',
      '10-01..10-04', '10-05..10-11', '10-12..10-18', '10-19..10-25', '10-26..10-31',
      '11-01..11-08', '11-09..11-15', '11-16..11-22', '11-23..11-30',
      '12-01..12-06', '12-07..12-13', '12-14..12-20', '12-21..12-27', '12-28..12-31',
    ]);
    expect(s.map((x) => x.n)).toEqual(Array.from({ length: 15 }, (_, i) => i + 1));
  });
  it('nenhuma semana cruza mês; cobrem o período dia a dia, sem buraco nem sobreposição', () => {
    for (const x of s) expect(x.inicio.slice(0, 7)).toBe(x.fim.slice(0, 7));
    for (const x of s) expect(x.mes).toBe(x.inicio.slice(0, 7));
    let dias = 0;
    for (const x of s) dias += (Date.parse(x.fim) - Date.parse(x.inicio)) / 86_400_000 + 1;
    expect(dias).toBe(99); // 7 (set) + 31 + 30 + 31
    for (let i = 1; i < s.length; i++) expect((Date.parse(s[i].inicio) - Date.parse(s[i - 1].fim)) / 86_400_000).toBe(1);
  });
  it('pedaço de 4 dias fica (01–04/10, quinta a domingo)', () => {
    expect(lim(semanas('2026-10-01', '2026-10-11'))).toEqual(['10-01..10-04', '10-05..10-11']);
  });
  it('mês que começa no domingo: o dia 1º entra na semana seguinte (nov/2026 e fev/2026)', () => {
    expect(lim(semanas('2026-11-01', '2026-11-15'))).toEqual(['11-01..11-08', '11-09..11-15']);
    expect(lim(semanas('2026-02-01', '2026-02-08'))).toEqual(['02-01..02-08']);
  });
  it('fim de mês curto vai para a semana anterior (30/11, segunda)', () => {
    expect(lim(semanas('2026-11-16', '2026-11-30'))).toEqual(['11-16..11-22', '11-23..11-30']);
  });
  it('início do período no meio da semana: 4 dias ficam, 3 dias unem à seguinte', () => {
    expect(lim(semanas('2026-10-08', '2026-10-18'))).toEqual(['10-08..10-11', '10-12..10-18']);
    expect(lim(semanas('2026-10-09', '2026-10-25'))).toEqual(['10-09..10-18', '10-19..10-25']);
  });
  it('mês com um pedaço só fica como está, mesmo curto', () => {
    expect(lim(semanas('2026-09-28', '2026-09-30'))).toEqual(['09-28..09-30']);
    expect(lim(semanas('2026-10-01', '2026-10-01'))).toEqual(['10-01..10-01']);
  });
  it('período invertido devolve vazio', () => {
    expect(semanas('2026-10-02', '2026-10-01')).toEqual([]);
  });
  it('fimDoMes', () => {
    expect(fimDoMes('2026-02-10')).toBe('2026-02-28');
    expect(fimDoMes('2026-12-01')).toBe('2026-12-31');
  });
});

describe('normalizarLinhaReceber — numeric pode chegar como texto', () => {
  it('converte valor, bloco, k e o líquido das vendas do detalhe', () => {
    const l = normalizarLinhaReceber({
      bloco: '1', grupo: 'Vendas já realizadas', componente: 'antecipacao', data_caixa: '2026-09-29T00:00:00',
      valor: '865.01', situacao: 'a_receber', origem_dia: '2026-09-25', ref: null, rotulo: null, produto: null, k: null,
      detalhe: [{ transacao: 'HP1', produto: 'HM', nome: 'Pessoa A', liquido: '1000.00' }],
    });
    expect(l.valor).toBe(865.01);
    expect(l.bloco).toBe(1);
    expect(l.data_caixa).toBe('2026-09-29');
    expect(l.detalhe[0].liquido).toBe(1000);
  });
  it('valor nulo/lixo vira 0; detalhe em texto JSON é lido; detalhe nulo vira []', () => {
    expect(normalizarLinhaReceber({ valor: null }).valor).toBe(0);
    expect(normalizarLinhaReceber({ valor: 'abc' }).valor).toBe(0);
    expect(normalizarLinhaReceber({ k: '3' }).k).toBe(3);
    expect(normalizarLinhaReceber({ detalhe: '[{"transacao":"HP2","liquido":"10.5"}]' }).detalhe[0].liquido).toBe(10.5);
    expect(normalizarLinhaReceber({ detalhe: null }).detalhe).toEqual([]);
  });
});

describe('agregarReceber — semana × bloco × grupo, só a_receber soma', () => {
  const linhas: LinhaReceber[] = [
    L({ data_caixa: '2026-09-25', valor: 0.1 }),
    L({ data_caixa: '2026-09-27', valor: 0.2, componente: 'garantia' }),
    L({ data_caixa: '2026-09-29', valor: 100 }),
    L({ data_caixa: '2026-09-29', valor: 999, situacao: 'realizada' }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', data_caixa: '2026-10-02', valor: 50, ref: 'r1' }),
    L({ bloco: 2, grupo: 'Assinaturas Serviço Diamante', data_caixa: '2026-10-02', valor: 30, ref: 'r2' }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', data_caixa: '2026-10-02', valor: 777, situacao: 'em_atraso_fora' }),
    L({ bloco: 2, grupo: 'Grupo novo do banco', data_caixa: '2026-10-05', valor: 5 }),
    L({ data_caixa: '2027-01-04', valor: 40 }), // fora do período
  ];
  const g = agregarReceber(linhas, '2026-09-24', '2026-10-31');

  it('realizada e em_atraso_fora não somam', () => {
    expect(g.total).toBe(185.3);
    expect(g.totalPorSemana.slice(0, 3)).toEqual([100.3, 80, 5]);
  });
  it('centavos exatos (0,1 + 0,2 = 0,3)', () => {
    expect(agregarReceber(linhas, '2026-09-24', '2026-09-27').linhas[0].porSemana[0]).toBe(0.3);
  });
  it('ordem das linhas: bloco 1, depois bloco 2 na ordem da planilha, grupo desconhecido no fim (não some)', () => {
    expect(g.linhas.map((l) => l.grupo)).toEqual([
      'Vendas já realizadas', 'Assinaturas Serviço Diamante', 'Parcelas a vencer HM', 'Grupo novo do banco',
    ]);
    expect(g.blocos).toEqual([
      { bloco: 1, porSemana: [100.3, 0, 0, 0, 0, 0], total: 100.3, brutoPorSemana: [100.3, 0, 0, 0, 0, 0], brutoTotal: 100.3 },
      { bloco: 2, porSemana: [0, 80, 5, 0, 0, 0], total: 85, brutoPorSemana: [0, 80, 5, 0, 0, 0], brutoTotal: 85 },
    ]);
  });
  it('total por mês e acumulado', () => {
    expect(g.meses.map((m) => [m.mes, m.semanas, m.total, m.acumulado])).toEqual([
      ['2026-09', [0], 100.3, 100.3],
      ['2026-10', [1, 2, 3, 4, 5], 85, 185.3],
    ]);
    expect(g.acumuladoPorSemana).toEqual([100.3, 180.3, 185.3, 185.3, 185.3, 185.3]);
  });
  it('a receber fora do período é contado à parte, não some', () => {
    expect(g.foraDoPeriodo).toEqual({ linhas: 1, valor: 40 });
  });
  it('composição da célula: só as linhas a_receber daquele grupo naquela semana', () => {
    const cel = composicaoDaCelula(linhas, g.semanas[0], 1, 'Vendas já realizadas');
    expect(cel.map((l) => l.valor)).toEqual([0.1, 0.2, 100]);
    expect(composicaoDaCelula(linhas, null, 2, 'Parcelas a vencer HM').map((l) => l.valor)).toEqual([50]);
  });
});

describe('periodoReceber', () => {
  it('de hoje (ou da 1ª data a receber anterior) ao fim do mês da última data a receber', () => {
    const ls = [L({ data_caixa: '2026-09-26' }), L({ data_caixa: '2026-12-02' }), L({ data_caixa: '2027-03-01', situacao: 'realizada' })];
    expect(periodoReceber(ls, '2026-09-28')).toEqual({ inicio: '2026-09-26', fim: '2026-12-31' });
    expect(periodoReceber([], '2026-09-28')).toEqual({ inicio: '2026-09-28', fim: '2026-09-30' });
  });
});

describe('cobrancasRecorrentes — bloco 2, todas as situações', () => {
  it('junta antecipação e garantia da mesma cobrança pela ref; sem ref cada linha é uma', () => {
    const ls = [
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'a|3', rotulo: 'Pessoa A', origem_dia: '2026-09-26', data_caixa: '2026-09-29', valor: 1238.05 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'a|3', rotulo: 'Pessoa A', origem_dia: '2026-09-26', data_caixa: '2026-10-26', valor: 143.13, componente: 'garantia' }),
      L({ bloco: 2, grupo: 'Outras assinaturas', ref: null, rotulo: 'Pessoa B', origem_dia: '2026-09-01', data_caixa: '2026-09-03', valor: 10, situacao: 'realizada' }),
      L({ bloco: 2, grupo: 'Outras assinaturas', ref: null, rotulo: 'Pessoa C', origem_dia: null, data_caixa: '2026-09-02', valor: 20, situacao: 'em_atraso_fora' }),
      L({ bloco: 1, valor: 5 }),
    ];
    const cs = cobrancasRecorrentes(ls);
    expect(cs.map((x) => [x.rotulo, x.prevista, x.valor, x.situacao, x.caixa.length])).toEqual([
      ['Pessoa B', '2026-09-01', 10, 'realizada', 1],
      ['Pessoa C', '2026-09-02', 20, 'em_atraso_fora', 1],
      ['Pessoa A', '2026-09-26', 1381.18, 'a_receber', 2],
    ]);
  });
});

describe('cálculo de recebimento desligado (data_caixa NULL)', () => {
  const b2 = (p: Partial<LinhaReceber>) => L({ bloco: 2, grupo: 'Parcelas a vencer HM', data_caixa: null, ...p });
  it('data_caixa nula continua nula (não vira data nem string vazia)', () => {
    expect(normalizarLinhaReceber({ data_caixa: null }).data_caixa).toBeNull();
  });
  it('bloco 1 vazio + bloco 2 a_receber sem data = desligado', () => {
    expect(recebimentoDesligado([b2({ valor: 100 })])).toBe(true);
    expect(recebimentoDesligado([b2({ valor: 100 }), L({ valor: 1 })])).toBe(false);
    // realizada/em_atraso_fora sem data é o contrato normal, não desligamento
    expect(recebimentoDesligado([b2({ situacao: 'realizada' }), b2({ situacao: 'em_atraso_fora' })])).toBe(false);
    expect(recebimentoDesligado([])).toBe(false);
  });
  it('a_receber sem data não soma, não conta como fora do período e não entra em célula', () => {
    const ls = [b2({ valor: 100 }), b2({ valor: 50, data_caixa: '2026-10-05' })];
    const g = agregarReceber(ls, '2026-09-28', '2026-10-31');
    expect(g.total).toBe(50);
    expect(g.semDataCaixa).toEqual({ linhas: 1, valor: 100 });
    expect(g.foraDoPeriodo).toEqual({ linhas: 0, valor: 0 });
    expect(composicaoDaCelula(ls, null, 2, 'Parcelas a vencer HM').map((l) => l.valor)).toEqual([50]);
  });
});

describe('contrato do bloco 2 (victor, 28/09): ref por contrato, origem_dia = vencimento, cheio sem data', () => {
  const ref = 'email|oferta';
  const ls = [
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref, rotulo: 'Pessoa A', origem_dia: '2026-10-10', data_caixa: '2026-10-14', valor: 900, k: 1 }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref, rotulo: 'Pessoa A', origem_dia: '2026-10-10', data_caixa: '2026-11-09', valor: 100, componente: 'garantia', k: 1 }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref, rotulo: 'Pessoa A', origem_dia: '2026-11-10', data_caixa: '2026-11-12', valor: 900, k: 2 }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref, rotulo: 'Pessoa A', origem_dia: '2026-09-10', data_caixa: null, valor: 1000, componente: 'cheio', situacao: 'realizada', k: 0 }),
    L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref, rotulo: 'Pessoa A', origem_dia: '2026-08-10', data_caixa: null, valor: 1000, componente: 'cheio', situacao: 'em_atraso_fora', k: -1 }),
  ];
  it('mesma ref com vencimentos diferentes são cobranças diferentes; partes do mesmo vencimento somam', () => {
    const cs = cobrancasRecorrentes(ls);
    expect(cs.map((x) => [x.prevista, x.valor, x.situacao, x.caixa])).toEqual([
      ['2026-08-10', 1000, 'em_atraso_fora', []],
      ['2026-09-10', 1000, 'realizada', []],
      ['2026-10-10', 1000, 'a_receber', ['2026-10-14', '2026-11-09']],
      ['2026-11-10', 900, 'a_receber', ['2026-11-12']],
    ]);
  });
  it('detalhe NULL do bloco 2 vira []', () => {
    expect(normalizarLinhaReceber({ bloco: 2, detalhe: null, componente: 'cheio', data_caixa: null }).detalhe).toEqual([]);
  });
  it('não é "desligado": bloco 2 sem data só em realizada/em_atraso_fora', () => {
    expect(recebimentoDesligado(ls.filter((l) => l.situacao !== 'a_receber'))).toBe(false);
  });
});

describe('bloco 5 — recebimentos informados (contrato 28/09)', () => {
  const B5 = (grupo: string, p: Partial<LinhaReceber> = {}) =>
    L({ bloco: 5, grupo, componente: 'cheio', data_caixa: '2026-10-05', valor: 100, ref: 'uuid-1', rotulo: 'Cliente X', ...p });
  it('grupos na ordem do contrato, depois dos blocos 1 e 2; grupo desconhecido no fim do bloco (não some)', () => {
    const g = agregarReceber([
      B5('Grupo novo do banco'),
      B5('Outros recebimentos informados'),
      B5('Serviço Diamante extras'),
      B5('Renovações Aurum'),
      B5('Renovações Diamante'),
      L({ bloco: 2, grupo: 'Outras assinaturas', data_caixa: '2026-10-05', valor: 1 }),
      L({ data_caixa: '2026-10-05', valor: 1 }),
    ], '2026-10-01', '2026-10-31');
    expect(g.linhas.map((l) => `${l.bloco}:${l.grupo}`)).toEqual([
      '1:Vendas já realizadas', '2:Outras assinaturas',
      ...GRUPOS_BLOCO_5.map((x) => `5:${x}`), '5:Grupo novo do banco',
    ]);
    expect(g.blocos.map((b) => [b.bloco, b.total])).toEqual([[1, 1], [2, 1], [5, 500]]);
  });
  it('realizada e em_atraso_fora do bloco 5 não somam; a_receber soma', () => {
    const g = agregarReceber([
      B5('Renovações Diamante', { valor: 18750 }),
      B5('Renovações Diamante', { valor: 999, situacao: 'realizada', data_caixa: null }),
      B5('Renovações Aurum', { valor: 777, situacao: 'em_atraso_fora', data_caixa: null }),
    ], '2026-10-01', '2026-10-31');
    expect(g.total).toBe(18750);
    expect(g.semDataCaixa.linhas).toBe(0);
  });
  it('bloco 5 não entra nas Recorrências (só bloco 2)', () => {
    expect(cobrancasRecorrentes([B5('Renovações Diamante')])).toEqual([]);
  });
});

describe('coberta_informado — cobrança do bloco 2 coberta por informado (conflito 6)', () => {
  const coberta = L({ bloco: 2, grupo: 'Parcelas a vencer Aurum', ref: 'a|1', origem_dia: '2026-10-10', data_caixa: '2026-10-12',
    valor: 5000, situacao: 'coberta_informado' });
  it('normalizar mantém a situação', () => {
    expect(normalizarLinhaReceber({ bloco: 2, grupo: 'x', componente: 'antecipacao', valor: '1', situacao: 'coberta_informado' }).situacao)
      .toBe('coberta_informado');
  });
  it('NÃO soma, não conta como sem data nem fora do período, não entra em célula nem no período', () => {
    const g = agregarReceber([coberta, L({ bloco: 2, grupo: 'Parcelas a vencer Aurum', data_caixa: '2026-10-12', valor: 10 })],
      '2026-10-01', '2026-10-31');
    expect(g.total).toBe(10);
    expect(g.linhas.map((l) => [l.grupo, l.total])).toEqual([['Parcelas a vencer Aurum', 10]]);
    expect(g.semDataCaixa.linhas + g.foraDoPeriodo.linhas).toBe(0);
    expect(composicaoDaCelula([coberta], null, 2, 'Parcelas a vencer Aurum')).toEqual([]);
    expect(periodoReceber([{ ...coberta, data_caixa: '2027-03-01' }], '2026-10-01').fim).toBe('2026-10-31');
  });
  it('aparece nas Recorrências com a própria situação (auditoria), grupo inalterado', () => {
    const r = cobrancasRecorrentes([coberta]);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ situacao: 'coberta_informado', grupo: 'Parcelas a vencer Aurum', valor: 5000 });
  });
});

describe('contrato v2 (z66) — tolerante à versão do banco', () => {
  it('banco antigo (sem as 6 colunas): valor_bruto = valor, fator 1, cenário base', () => {
    const l = normalizarLinhaReceber({ bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', data_caixa: '2026-10-05', valor: '1238.05', situacao: 'a_receber', detalhe: null });
    expect(l).toMatchObject({ valor: 1238.05, valor_bruto: 1238.05, fator: 1, certeza: null, tratamento: null, cenario: 'base', pagas: null });
  });
  it('bloco 2: detalhe NULL = a linha não trouxe (null); [] = contrato sem transação paga ([])', () => {
    const base = { bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', data_caixa: '2026-10-05', valor: 1, situacao: 'a_receber' };
    expect(normalizarLinhaReceber({ ...base, detalhe: null }).pagas).toBeNull();
    expect(normalizarLinhaReceber({ ...base, detalhe: [] }).pagas).toEqual([]);
  });
  it('banco novo: lê as 6 colunas; bloco 2 detalhe vira `pagas` (e não vendas do dia)', () => {
    const l = normalizarLinhaReceber({
      bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'antecipacao', data_caixa: '2026-11-05', valor: '950.00', situacao: 'a_receber',
      valor_bruto: '1000', fator: '0.95', certeza: 'certo', centro_custo: '1. Receita de vendas (Hotmart)',
      tratamento: 'Antecipação D+2 útil (90% − 3,89%) · Perda 5%/mês × 1 mês', cenario: 'conservador',
      detalhe: [{ transacao: 'HP1', n: 1, dia: '2026-08-05', liquido: '1000' }, { transacao: 'HP2', n: 2, dia: '2026-09-05', liquido: 1000 }],
    });
    expect(l).toMatchObject({ valor: 950, valor_bruto: 1000, fator: 0.95, cenario: 'conservador', detalhe: [] });
    expect(l.pagas).toEqual([{ transacao: 'HP1', n: 1, dia: '2026-08-05', liquido: 1000 }, { transacao: 'HP2', n: 2, dia: '2026-09-05', liquido: 1000 }]);
    expect(Object.keys(l.pagas![0])).not.toContain('email');
  });
  it('agregação soma o ESPERADO; o bruto anda junto e não entra no total', () => {
    const g = agregarReceber([
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', data_caixa: '2026-10-05', valor: 950, valor_bruto: 1000, fator: 0.95 }),
      L({ bloco: 1, data_caixa: '2026-10-05', valor: 100 }),
    ], '2026-10-01', '2026-10-31');
    expect(g.total).toBe(1050);
    expect(g.brutoTotal).toBe(1100);
    const b2 = g.blocos.find((b) => b.bloco === 2)!;
    expect(b2.total).toBe(950);
    expect(b2.brutoTotal).toBe(1000);
    expect(g.meses[0]).toMatchObject({ total: 1050, brutoTotal: 1100 });
  });
  it('Recorrências: valor = bruto da cobrança; esperado = o que soma', () => {
    const [c] = cobrancasRecorrentes([
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'r', origem_dia: '2026-11-01', data_caixa: '2026-11-04', valor: 855, valor_bruto: 900, fator: 0.95 }),
      L({ bloco: 2, grupo: 'Parcelas a vencer HM', ref: 'r', origem_dia: '2026-11-01', data_caixa: '2026-12-01', componente: 'garantia', valor: 95, valor_bruto: 100, fator: 0.95 }),
    ]);
    expect(c.valor).toBe(1000);
    expect(c.esperado).toBe(950);
  });
});

describe('pagasPorContrato — lista por ref, de qualquer linha que a traga', () => {
  const P1 = [{ transacao: 'HP1', n: 1, dia: '2026-08-05', liquido: 1000 }];
  it('banco novo: só a 1ª linha a_receber traz; a 2ª (null) não apaga', () => {
    const m = pagasPorContrato([
      L({ bloco: 2, ref: 'c|1', situacao: 'a_receber', pagas: P1 }),
      L({ bloco: 2, ref: 'c|1', situacao: 'a_receber', pagas: null }),
    ]);
    expect(m.get('c|1')).toEqual(P1);
  });
  it('a lista pode vir numa linha depois de outra sem lista (ordem da RPC não importa)', () => {
    const m = pagasPorContrato([L({ bloco: 2, ref: 'c|1', pagas: null }), L({ bloco: 2, ref: 'c|1', pagas: P1 })]);
    expect(m.get('c|1')).toEqual(P1);
  });
  it('z66 (todas trazem): a 1ª vence; [] é "sem transação paga" e fica no mapa; outros blocos e ref nula ficam fora', () => {
    const m = pagasPorContrato([
      L({ bloco: 2, ref: 'c|1', pagas: P1 }), L({ bloco: 2, ref: 'c|1', pagas: P1 }),
      L({ bloco: 2, ref: 'c|2', pagas: [] }),
      L({ bloco: 2, ref: null, pagas: P1 }),
      L({ bloco: 5, ref: 'c|3', pagas: [] }),
    ]);
    expect([...m.keys()]).toEqual(['c|1', 'c|2']);
    expect(m.get('c|2')).toEqual([]);
  });
});
