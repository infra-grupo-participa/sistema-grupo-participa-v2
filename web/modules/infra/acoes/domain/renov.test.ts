import { describe, expect, it } from 'vitest';
import { mapearPainelRenov, rotuloOpcaoRenov } from './renov';

describe('painel do /renov', () => {
  it('mapeia totais, opções na ordem fixa e vendas por oferta', () => {
    const p = mapearPainelRenov({
      aplicacoes_total: 3, por_opcao: { 'renovar-holding-masters': 2, 'nao-renovar': 1 }, aplicaram_e_pagaram: 1,
      vendas: [{ oferta: 'nv5f10zq', vendas: 1, valor: 6000 }, { oferta: 'wftji6dl', vendas: 0, valor: 0 }],
      aplicacoes: [{ criado_em: '2026-10-16T16:40:03Z', opcao: 'nao-renovar', origem: '', pagou: false, nome: null }],
      ultimas_vendas: [], ve_contato: false,
    });
    expect(p.total).toBe(3);
    expect(p.porOpcao.map((o) => o.n)).toEqual([1, 2, 0]);
    expect(p.vendas[0]).toMatchObject({ vendas: 1, valor: 6000, rotulo: 'Renovação Holding Masters (R$ 6.000)' });
    expect(p.aplicacoes[0].nome).toBeNull();
    expect(p.veContato).toBe(false);
  });
  it('mapeia contato quando ve_contato é true', () => {
    const p = mapearPainelRenov({
      aplicacoes_total: 1, por_opcao: { 'renovar-holding-masters': 1 }, aplicaram_e_pagaram: 1, vendas: [],
      aplicacoes: [{ criado_em: '2026-10-16T16:40:03Z', opcao: 'renovar-holding-masters', origem: 'email', pagou: true,
        nome: 'Zz Teste', email: 'zz@exemplo.invalid', telefone: '+550000000000' }],
      ultimas_vendas: [{ em: '2026-10-16T17:00:00Z', oferta: 'nv5f10zq', valor: 6000, aplicou: true, nome: 'Zz Teste', email: 'zz@exemplo.invalid' }],
      ve_contato: true,
    });
    expect(p.veContato).toBe(true);
    expect(p.aplicacoes[0]).toMatchObject({ nome: 'Zz Teste', email: 'zz@exemplo.invalid', telefone: '+550000000000', pagou: true, origem: 'email' });
    expect(p.ultimasVendas[0]).toMatchObject({ nome: 'Zz Teste', email: 'zz@exemplo.invalid', aplicou: true, valor: 6000 });
  });
  it('aguenta resposta vazia', () => {
    const p = mapearPainelRenov(null);
    expect(p.total).toBe(0);
    expect(p.porOpcao).toHaveLength(3);
    expect(p.vendas).toEqual([]);
  });
  it('rotula a opção', () => {
    expect(rotuloOpcaoRenov('upgrade-implementacao-assistida')).toBe('Upgrade Implementação Assistida');
  });
});
