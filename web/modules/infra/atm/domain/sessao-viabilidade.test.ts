import { describe, expect, it } from 'vitest';
import {
  contarVendasSessaoViabilidade,
  conversaoSessaoViabilidade,
  dataDaVendaSessaoViabilidade,
  listaAposLeituraSv,
  notaVendasTesteForaDoTotal,
  valorDaVendaSessaoViabilidade,
  vendasValidasSessaoViabilidade,
  type VendaSessaoViabilidade,
} from './sessao-viabilidade';

function venda(parcial: Partial<VendaSessaoViabilidade>): VendaSessaoViabilidade {
  return {
    id: 'HP-fixture', transacao: 'HP-fixture', aprovadoEm: null, pedidoEm: null, diaAprovado: null, nome: null, email: null,
    telefone: null, valorBruto: null, valorLiquido: null, moeda: null, status: null, ofertaCodigo: null, teste: false,
    ...parcial,
  };
}

describe('conversaoSessaoViabilidade', () => {
  it('calcula vendas divididas por pré-checkouts únicos', () => {
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, 12)).toEqual({ valor: 25, semDado: false });
  });

  it('mantém sem dado quando vendas ou pré-checkouts não foram carregados', () => {
    expect(conversaoSessaoViabilidade({ valor: 0, semDado: true }, 12)).toEqual({ valor: 0, semDado: true });
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, null)).toEqual({ valor: 0, semDado: true });
    expect(conversaoSessaoViabilidade({ valor: 3, semDado: false }, 0)).toEqual({ valor: 0, semDado: true });
  });
});

describe('vendas da Sessão de Viabilidade', () => {
  it('tira as linhas marcadas como teste da lista válida e da contagem', () => {
    const lista = [venda({ id: 'a' }), venda({ id: 'b', teste: true }), venda({ id: 'c' })];
    expect(vendasValidasSessaoViabilidade(lista).map((v) => v.id)).toEqual(['a', 'c']);
    expect(contarVendasSessaoViabilidade(lista)).toEqual({ validas: 2, teste: 1 });
    expect(contarVendasSessaoViabilidade([])).toEqual({ validas: 0, teste: 0 });
  });

  it('só gera a nota de teste fora do total quando o resumo informa mais que zero', () => {
    expect(notaVendasTesteForaDoTotal(null)).toBeNull();
    expect(notaVendasTesteForaDoTotal(undefined)).toBeNull();
    expect(notaVendasTesteForaDoTotal(0)).toBeNull();
    expect(notaVendasTesteForaDoTotal(1)).toBe('1 venda de teste fora do total');
    expect(notaVendasTesteForaDoTotal(3)).toBe('3 vendas de teste fora do total');
  });

  it('usa aprovado_em em São Paulo como data da venda e cai para dia_aprovado', () => {
    expect(dataDaVendaSessaoViabilidade({ aprovadoEm: '2026-10-14T01:30:00Z', diaAprovado: '2026-10-13' })).toBe('13/10/2026, 22:30');
    expect(dataDaVendaSessaoViabilidade({ aprovadoEm: null, diaAprovado: '2026-10-13' })).toBe('13/10/2026');
    expect(dataDaVendaSessaoViabilidade({ aprovadoEm: 'invalida', diaAprovado: null })).toBeNull();
    expect(dataDaVendaSessaoViabilidade({ aprovadoEm: null, diaAprovado: null })).toBeNull();
  });

  it('formata o valor na moeda da venda sem presumir real quando a moeda falta', () => {
    expect(valorDaVendaSessaoViabilidade(null, 'BRL')).toBeNull();
    expect(valorDaVendaSessaoViabilidade(297, 'BRL')?.replace(/\s/g, ' ')).toBe('R$ 297,00');
    expect(valorDaVendaSessaoViabilidade(0, 'BRL')?.replace(/\s/g, ' ')).toBe('R$ 0,00');
    expect(valorDaVendaSessaoViabilidade(1234.5, null)).toBe('1.234,50');
    expect(valorDaVendaSessaoViabilidade(10, 'R$')).toBe('10,00 R$');
  });
});

describe('listaAposLeituraSv', () => {
  const anterior = { data: [venda({ id: 'a' })], semDado: false, erro: null };

  it('sucesso substitui a lista', () => {
    const nova = { data: [venda({ id: 'b' })], semDado: false, erro: null };
    expect(listaAposLeituraSv(anterior, nova)).toEqual(nova);
  });

  it('permissão perdida (42501) limpa a lista e marca semPermissao', () => {
    const r = listaAposLeituraSv(anterior, { data: [], semDado: true, erro: 'Sem permissão para ler este dashboard.', semPermissao: true });
    expect(r).toEqual({ data: [], semDado: true, erro: 'Sem permissão para ler este dashboard.', semPermissao: true });
  });

  it('outra falha preserva a última lista e só troca o aviso', () => {
    const r = listaAposLeituraSv(anterior, { data: [], semDado: true, erro: 'Falha de conexão.' });
    expect(r.data).toBe(anterior.data);
    expect(r).toEqual({ data: anterior.data, semDado: false, erro: 'Falha de conexão.' });
    expect(r.semPermissao).toBeUndefined();
  });

  it('leitura bem-sucedida depois de perder a permissão tira a marca', () => {
    const r = listaAposLeituraSv({ data: [], semDado: true, erro: 'x', semPermissao: true }, { data: [], semDado: false, erro: null });
    expect(r.semPermissao).toBeUndefined();
  });
});
