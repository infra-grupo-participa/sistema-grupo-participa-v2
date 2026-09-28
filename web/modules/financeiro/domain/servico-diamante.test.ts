import { describe, expect, it } from 'vitest';
import { agruparPorDiamante, compraEmOutroNome, diasEntre, resumirDiamantes, ultimosMeses, type LinhaServicoDiamante } from './servico-diamante';

const linha = (x: Partial<LinhaServicoDiamante>): LinhaServicoDiamante => ({
  pessoa_chave: 'p1', nome: 'Ana', nome_compra: null, nome_empresa: false, cliente_cadastro: true, email: 'ana@x.com', emails: ['ana@x.com'], telefone: null, nivel: 'diamante',
  servico: 'trafego', ofertas: ['td9xav44'], desconhecida: false, primeira_paga: '2025-01-10', ultima_paga: '2026-09-10',
  pagamentos: 10, total_pago: 10000, liquido: 9000, mensalidade: 1000, devendo_n: 0, devendo_valor: 0,
  devendo_desde: null, antigo_n: 0, antigo_valor: 0, antigo_desde: null, coberto_n: 0, coberto_valor: 0, estornos: 0,
  tentativas: 10, ultima_tentativa: null, meses: {}, situacao: 'em_dia', ...x,
});

describe('agruparPorDiamante', () => {
  it('situação da pessoa é a mais urgente; soma dívida e mensalidade ativa', () => {
    const [c] = agruparPorDiamante([
      linha({}),
      linha({ servico: 'video', situacao: 'devendo', devendo_n: 2, devendo_valor: 3000, devendo_desde: '2026-07-01', mensalidade: 1500 }),
      linha({ servico: 'copy', situacao: 'encerrado', ultima_paga: '2025-05-01', mensalidade: 800 }),
    ]);
    expect(c.situacao).toBe('devendo');
    expect(c.devendoValor).toBe(3000);
    expect(c.mensalidadeAtiva).toBe(1000);
    expect(c.servicos[0].servico).toBe('video');
    expect(c.jaPagou).toBe(true);
  });
  it('quem só tentou fica separado (jaPagou = false) e vai para o fim', () => {
    const r = agruparPorDiamante([
      linha({ pessoa_chave: 'p2', nome: 'Bia', pagamentos: 0, total_pago: 0, situacao: 'nunca_pagou', ultima_paga: null, primeira_paga: null }),
      linha({}),
    ]);
    expect(r.map((c) => c.pessoa_chave)).toEqual(['p1', 'p2']);
    expect(r[1].jaPagou).toBe(false);
  });
});

describe('resumirDiamantes', () => {
  it('conta só quem já pagou e resume por serviço', () => {
    const r = resumirDiamantes(agruparPorDiamante([
      linha({}),
      linha({ pessoa_chave: 'p2', situacao: 'devendo', devendo_n: 1, devendo_valor: 1000, nivel: 'platina' }),
      linha({ pessoa_chave: 'p3', pagamentos: 0, total_pago: 0, situacao: 'nunca_pagou' }),
    ]));
    expect(r.jaPagaram).toBe(2);
    expect(r.nuncaPagaram).toBe(1);
    expect(r.emDia).toBe(1);
    expect(r.devendo).toBe(1);
    expect(r.devendoValor).toBe(1000);
    expect(r.foraDoDiamante).toBe(1);
    expect(r.servicos).toEqual([{ chave: 'trafego', contrataram: 2, emDia: 1, devendo: 1, devendoValor: 1000, mensalidadeAtiva: 1000 }]);
  });
});

it('diasEntre', () => {
  expect(diasEntre('2026-09-01', '2026-09-27')).toBe(26);
});

describe('acordo e meses', () => {
  it('acordo não é serviço: soma no pago, não vira mensalidade nem chip', () => {
    const [c] = agruparPorDiamante([
      linha({ servico: 'video', situacao: 'encerrado', coberto_n: 5, coberto_valor: 5000 }),
      linha({ servico: 'acordo', situacao: 'em_dia', total_pago: 29200, mensalidade: 9733.33 }),
    ]);
    expect(c.servicos.map((s) => s.servico)).toEqual(['video']);
    expect(c.acordoPago).toBe(29200);
    expect(c.mensalidadeAtiva).toBe(0);
    expect(c.cobertoValor).toBe(5000);
  });
  it('ultimosMeses atravessa o ano', () => {
    expect(ultimosMeses('2026-02-10', 3)).toEqual(['2025-12', '2026-01', '2026-02']);
  });
});

describe('situação da pessoa e nome da compra', () => {
  it('ainda ativo com dívida em outro serviço = devendo', () => {
    const [c] = agruparPorDiamante([
      linha({ servico: 'video', situacao: 'em_dia' }),
      linha({ servico: 'trafego', situacao: 'parou_devendo', antigo_n: 5, antigo_valor: 5000 }),
    ]);
    expect(c.situacao).toBe('devendo');
  });
  it('parou e ficou devendo = parou_devendo', () => {
    const [c] = agruparPorDiamante([linha({ situacao: 'parou_devendo', antigo_n: 1, antigo_valor: 800 })]);
    expect(c.situacao).toBe('parou_devendo');
  });
  it('compra em outro nome: empresa ou outra pessoa, não o nome completo da mesma', () => {
    expect(compraEmOutroNome('Claudia Kellner', 'Cláudia Marisa Kellner')).toBe(false);
    expect(compraEmOutroNome('Vitor Negrão', 'Exatus Contabilidade')).toBe(true);
    expect(compraEmOutroNome('Bruno Couto Rocha', 'Rafael Machado Lustosa Nogueira')).toBe(true);
    expect(compraEmOutroNome('Ana', null)).toBe(false);
  });
});
