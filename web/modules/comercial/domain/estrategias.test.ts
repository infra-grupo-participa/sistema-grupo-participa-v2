import { describe, expect, it } from 'vitest';
import {
  filtrosVazios, limparFiltros, ordenarPedidos, podeEditarPedido, podeTransformar, proximasSituacoes, resumoFiltros, taxasPlacar,
  validarFiltros, validarSolicitacao, type Estrategia, type NovaSolicitacao,
} from './estrategias';

const base: NovaSolicitacao = {
  titulo: 'Própria holding', objetivo: 'Vender SV', publico: '', filtros: {}, modelo: null, linha: 'sv', oferta: '', prazo: null,
  prioridade: 'media', observacoes: '',
};
const pedido = (p: Partial<Estrategia>): Estrategia => ({
  id: 'e', titulo: 't', objetivo: 'o', publico: '', filtros: {}, modelo: null, linha: null, oferta: null, prazo: null, prioridade: 'media',
  observacoes: '', solicitanteId: 's', solicitanteNome: 'S', situacao: 'solicitada', motivoRecusa: null, responsavelId: null,
  responsavelNome: null, acaoTipo: null, filaId: null, funilId: null, acaoCriadaEm: null, acaoPessoas: null,
  criadoEm: '2026-10-07T10:00:00Z', atualizadoEm: '2026-10-07T10:00:00Z', placar: null, ...p,
});

describe('estratégias: situação (mesma tabela da RPC crm_estrategia_situacao)', () => {
  it('caminho solicitada → em análise → em execução → concluída; recusa só antes da execução', () => {
    expect(proximasSituacoes('solicitada')).toEqual(['em_analise', 'recusada']);
    expect(proximasSituacoes('em_analise')).toEqual(['em_execucao', 'recusada']);
    expect(proximasSituacoes('em_execucao')).toEqual(['concluida']);
    expect(proximasSituacoes('concluida')).toEqual([]);
    expect(proximasSituacoes('recusada')).toEqual([]);
  });
  it('vira ação uma vez, só aberto; solicitante edita só enquanto "solicitada"', () => {
    expect(podeTransformar(pedido({}))).toBe(true);
    expect(podeTransformar(pedido({ situacao: 'em_analise' }))).toBe(true);
    expect(podeTransformar(pedido({ situacao: 'em_analise', acaoTipo: 'fila' }))).toBe(false);
    expect(podeTransformar(pedido({ situacao: 'recusada' }))).toBe(false);
    expect(podeEditarPedido(pedido({}))).toBe(true);
    expect(podeEditarPedido(pedido({ situacao: 'em_analise' }))).toBe(false);
  });
});

describe('estratégias: validação (mesmas mensagens da RPC)', () => {
  const hoje = new Date(2026, 9, 7);
  it('título e objetivo obrigatórios; prazo no passado recusado; hoje vale', () => {
    expect(validarSolicitacao({ ...base, titulo: 'ab' }, hoje)).toBe('Dê um título ao pedido.');
    expect(validarSolicitacao({ ...base, objetivo: ' ' }, hoje)).toBe('Descreva o objetivo.');
    expect(validarSolicitacao({ ...base, prazo: '2026-10-06' }, hoje)).toBe('Prazo no passado.');
    expect(validarSolicitacao({ ...base, prazo: '2026-10-07' }, hoje)).toBeNull();
  });
  it('filtros: compradores exige "comprou"; regra de pesquisa precisa de pergunta e trecho com 3+ letras', () => {
    expect(validarFiltros({ base: 'compradores' })).toBe('Base de compradores precisa do filtro "comprou".');
    expect(validarFiltros({ base: 'compradores', comprou: { linhas: ['hm'] } })).toBeNull();
    expect(validarFiltros({ respondi: { regras: [{ perguntas: ['P'], contem: [] }] } })).toBe('Cada regra de pesquisa precisa de pergunta e resposta.');
    expect(validarFiltros({ respondi: { regras: [{ perguntas: ['P'], contem: ['ab'] }] } })).toBe('Resposta da regra de pesquisa com menos de 3 letras.');
    expect(validarSolicitacao({ ...base, filtros: { base: 'compradores' } }, hoje)).toBe('Base de compradores precisa do filtro "comprou".');
  });
});

describe('estratégias: filtros', () => {
  it('limpar tira lista vazia, regra incompleta e o "excluir" padrão', () => {
    expect(limparFiltros({ alunos: { niveis: [], turmas: [' T33 '] }, comprou: { produtos: [] }, excluir: { emNegociacao: true, outraAcao: true } }))
      .toEqual({ base: 'alunos', alunos: { turmas: ['T33'] } });
    expect(limparFiltros({ respondi: { regras: [{ perguntas: [''], contem: ['abc'] }] } })).toEqual({});
    expect(limparFiltros({ alunos: { tiposTurma: ['thb'] }, excluir: { outraAcao: false } }))
      .toEqual({ base: 'alunos', alunos: { tiposTurma: ['thb'] }, excluir: { emNegociacao: true, outraAcao: false } });
    expect(filtrosVazios({ alunos: { niveis: [] } })).toBe(true);
    expect(filtrosVazios({ base: 'contatos' })).toBe(false);
  });
  it('resumo em frases curtas, sem dado pessoal, com nome de produto', () => {
    const r = resumoFiltros({
      alunos: { tiposTurma: ['thb'] }, naoComprou: { produtos: ['1663254'] },
      respondi: { regras: [{ perguntas: ['P'], contem: ['fazer a minha'] }, { perguntas: ['Q'], contem: ['própria'] }] },
    }, (id) => (id === '1663254' ? 'Sessão de Viabilidade' : id));
    expect(r).toEqual(['Base: Alunos', 'Turma: THB', 'Não comprou: Sessão de Viabilidade', 'Pesquisas: 2 regras de resposta',
      'Saem: opt-out, em negociação, em outra ação']);
    expect(resumoFiltros({})).toEqual([]);
  });
});

describe('estratégias: placar e ordem', () => {
  it('taxas sem NaN com lista vazia; uma casa decimal', () => {
    expect(taxasPlacar(null)).toEqual({ abordagem: 0, conversa: 0, conversao: 0 });
    expect(taxasPlacar({ naLista: 0, abordadas: 0, emConversa: 0, vendas: 0, receita: 0 })).toEqual({ abordagem: 0, conversa: 0, conversao: 0 });
    expect(taxasPlacar({ naLista: 137, abordadas: 50, emConversa: 12, vendas: 3, receita: 3600 })).toEqual({ abordagem: 36.5, conversa: 8.8, conversao: 2.2 });
  });
  it('abertos primeiro (urgente antes, prazo mais perto antes); encerrados depois, mais recente primeiro', () => {
    const ls = [
      pedido({ id: 'velho-fechado', situacao: 'concluida', criadoEm: '2026-10-01T00:00:00Z' }),
      pedido({ id: 'media', prioridade: 'media' }),
      pedido({ id: 'urgente', prioridade: 'urgente' }),
      pedido({ id: 'alta-tarde', prioridade: 'alta', prazo: '2026-10-30' }),
      pedido({ id: 'alta-cedo', prioridade: 'alta', prazo: '2026-10-10' }),
      pedido({ id: 'novo-recusado', situacao: 'recusada', criadoEm: '2026-10-06T00:00:00Z' }),
    ];
    expect(ordenarPedidos(ls).map((e) => e.id)).toEqual(['urgente', 'alta-cedo', 'alta-tarde', 'media', 'novo-recusado', 'velho-fechado']);
  });
});
