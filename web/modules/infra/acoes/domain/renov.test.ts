import { describe, expect, it } from 'vitest';
import { filtrarAplicacoesRenov, LINK_OFERTA_RENOV, mapearPainelRenov, mesmoFiltroRenov, rotuloOpcaoRenov } from './renov';

const bruto = {
  aplicacoes_total: 3, por_opcao: { 'renovar-holding-masters': 2, 'nao-renovar': 1 }, aplicaram_e_pagaram: 1,
  acessos: 40, visitantes: 20, visitantes_que_aplicaram: 3,
  vendas: [{ oferta: 'nv5f10zq', vendas: 1, valor: 6000 }, { oferta: 'wftji6dl', vendas: 0, valor: 0 }],
  aplicacoes: [
    { id: 'a', criado_em: '2026-10-16T16:40:03Z', opcao: 'renovar-holding-masters', origem: '', pagou: true, teste: false, teste_fixo: false, acessos_antes: 3, nome: 'Ana', email: 'ana@x.com', telefone: '+5511999998888' },
    { id: 'b', criado_em: '2026-10-16T16:41:03Z', opcao: 'renovar-holding-masters', origem: 'meta', pagou: false, teste: false, teste_fixo: false, acessos_antes: null },
    { id: 'c', criado_em: '2026-10-16T16:42:03Z', opcao: 'nao-renovar', origem: '', pagou: true, teste: true, teste_fixo: true, acessos_antes: 1 },
  ],
  ultimas_vendas: [], ve_contato: true, eh_master: true,
};

describe('painel do /renov', () => {
  it('mapeia totais, acessos, taxa e campos da linha', () => {
    const p = mapearPainelRenov(bruto);
    expect(p.total).toBe(3);
    expect(p.porOpcao.map((o) => o.n)).toEqual([1, 2, 0]);
    expect(p.taxaAplicacao).toBe(15);
    expect(p.aplicacoes[0]).toMatchObject({ id: 'a', acessosAntes: 3, nome: 'Ana', teste: false });
    expect(p.aplicacoes[1].acessosAntes).toBeNull();
    expect(p.aplicacoes[2]).toMatchObject({ teste: true, testeFixo: true });
    expect(p.veContato).toBe(true);
    expect(p.ehMaster).toBe(true);
  });
  it('aguenta resposta vazia, sem taxa', () => {
    const p = mapearPainelRenov(null);
    expect(p.total).toBe(0);
    expect(p.porOpcao).toHaveLength(3);
    expect(p.taxaAplicacao).toBeNull();
  });
  it('filtra a tabela pelo card', () => {
    const { aplicacoes } = mapearPainelRenov(bruto);
    expect(filtrarAplicacoesRenov(aplicacoes, null)).toHaveLength(3);
    expect(filtrarAplicacoesRenov(aplicacoes, { tipo: 'opcao', opcao: 'nao-renovar' }).map((a) => a.id)).toEqual(['c']);
    expect(filtrarAplicacoesRenov(aplicacoes, { tipo: 'pagou' }).map((a) => a.id)).toEqual(['a']);
    expect(filtrarAplicacoesRenov(aplicacoes, { tipo: 'oferta', oferta: 'nv5f10zq' }).map((a) => a.id)).toEqual(['a']);
    expect(mesmoFiltroRenov({ tipo: 'pagou' }, { tipo: 'pagou' })).toBe(true);
  });
  it('rotula a opção e monta o link da oferta', () => {
    expect(rotuloOpcaoRenov('upgrade-implementacao-assistida')).toBe('Upgrade Implementação Assistida');
    expect(LINK_OFERTA_RENOV('wftji6dl')).toBe('https://pay.hotmart.com/L97981750T?off=wftji6dl');
  });
});
