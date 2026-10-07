import { describe, expect, it } from 'vitest';
import { cadastroVazio, painelAtivacaoDemo } from './mock-ativacao';
import { argsSalvarAtivacao, mapPainelAtivacao } from './mapeamento-ativacao';
import { funisDoProjeto } from '../domain/modelos';
import type { Atividade, Negocio } from '../domain/types';

describe('mapPainelAtivacao', () => {
  it('converte o jsonb da RPC', () => {
    const p = mapPainelAtivacao({
      projetos: [{ projeto: 'ht34', nome: 'HT34', funilId: 'f1', produto: 'ht', eventoInicio: '2026-10-26', eventoFim: '2026-10-28', eventoHora: '19:00',
        hotmartOferta: ['5064314'], ligado: true, encerradoEm: null, filaId: null, carrinhoFim: '2026-10-30', fimAtivacao: '2026-10-30', datasDoMarketing: true, porEtapa: { e1: 2 }, entradasHoje: '3', mqls: 1, mensageriaHoje: 0 }],
      carga: [{ vendedorId: 'v1', novasHoje: 31, toquesHoje: 40 }], totalNovasHoje: 31, semAtivacao: ['bf26'], ligada: true,
    });
    expect(p.projetos[0]).toMatchObject({ projeto: 'ht34', porEtapa: { e1: 2 }, entradasHoje: 3, hotmartOferta: ['5064314'], fimAtivacao: '2026-10-30', datasDoMarketing: true });
    expect(p).toMatchObject({ totalNovasHoje: 31, semAtivacao: ['bf26'], ligada: true });
  });
  it('formato fora do contrato é erro, nunca painel vazio', () => {
    expect(() => mapPainelAtivacao(null)).toThrow(/crm_ativacao_painel/);
    expect(() => mapPainelAtivacao({ projetos: 'x', carga: [] })).toThrow();
    expect(() => mapPainelAtivacao({ projetos: [{ nome: 'sem chave' }], carga: [] })).toThrow();
  });
  it('edição vira o payload de crm_ativacao_salvar', () => {
    expect(argsSalvarAtivacao({ projeto: 'ht34', eventoInicio: null, eventoFim: null, eventoHora: null, carrinhoFim: '2026-10-30', hotmartOferta: [], ligado: false }))
      .toEqual({ p: { projeto: 'ht34', eventoInicio: '', eventoFim: '', eventoHora: '', carrinhoFim: '2026-10-30', hotmartOferta: [], ligado: false } });
  });
});

describe('painel da demonstração (mesmas regras do banco)', () => {
  const funis = funisDoProjeto('seminario', 'Sem Nov', { id: 'ag', nome: 'SV', produto: 'sv', ordem: 1 }, 'sv')
    .map((f, i) => ({ ...f, id: `f${i}` }));
  const fa = funis[0];
  const agora = new Date('2026-10-07T13:00:00Z');
  const neg = (id: string, dono: string): Negocio => ({
    id, contatoId: `c-${id}`, produto: 'sv', origem: 'venda_ativa', funilId: fa.id, campanhaId: null, etapaId: fa.etapas[0].id,
    etapaNome: fa.etapas[0].nome, etapa: 'primeiro_contato', status: 'aberto', donoId: dono, valor: 0, campos: {}, motivoPerda: null,
    criadoEm: agora.toISOString(), etapaDesde: agora.toISOString(), fechadoEm: null, proximaAtividade: null, ultimaInteracaoEm: null,
  });
  const at = (id: string, n: string, dono: string, titulo: string): Atividade => ({
    id, negocioId: n, contatoId: `c-${n}`, donoId: dono, tipo: 'whatsapp', titulo, venceEm: agora.toISOString(), concluidaEm: null, resultado: null, cadenciaDia: null,
  });
  const base = {
    funis, negocios: [neg('n1', 'v1'), neg('n2', 'v2')], agora, cadastros: new Map([['sem-nov', cadastroVazio()]]),
    atividades: [at('a1', 'n1', 'v1', 'Toque 1: x'), at('a2', 'n2', 'v2', 'Toque 1: y'), at('a3', 'n2', 'v2', 'Toque 3 · dia 1: z')],
  };
  it('vendedor conta só os dele (D6); o total do número vai para todos', () => {
    const p = painelAtivacaoDemo({ ...base, eu: { vendedorId: 'v1', papel: 'vendedor' } });
    expect(Object.values(p.projetos[0].porEtapa).reduce((s, x) => s + x, 0)).toBe(1);
    expect(p.carga).toEqual([{ vendedorId: 'v1', novasHoje: 1, toquesHoje: 1 }]);
    expect(p.totalNovasHoje).toBe(2);
    expect(p.semAtivacao).toEqual([]);
  });
  it('gestor vê todos', () => {
    const p = painelAtivacaoDemo({ ...base, eu: { vendedorId: 'g', papel: 'gestor' } });
    expect(p.carga).toHaveLength(2);
    expect(p.projetos[0]).toMatchObject({ projeto: 'sem-nov', nome: 'Sem Nov' });
  });
});
