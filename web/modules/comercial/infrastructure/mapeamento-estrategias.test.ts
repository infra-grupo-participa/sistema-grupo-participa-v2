import { describe, expect, it } from 'vitest';
import { argsSalvar, mapAcesso, mapEstrategia, mapFiltros, mapModelos, mapOpcoes, mapPrevia } from './mapeamento-estrategias';

const pedidoBanco = {
  id: 'e1', titulo: 'Própria holding', objetivo: 'Vender SV', publico: 'Alunos', modelo: 'alunos_querem_propria_holding',
  filtros: { base: 'alunos', alunos: { tiposTurma: ['thb'] }, naoComprou: { produtos: ['1663254'] }, desconhecido: 1,
    respondi: { regras: [{ perguntas: ['O seu interesse hoje é:'], contem: ['fazer a minha holding'] }, { perguntas: [], contem: ['x'] }] } },
  linha: 'sv', oferta: null, prazo: '2026-10-21', prioridade: 'alta', observacoes: '', solicitanteId: 's', solicitanteNome: 'Elaine Montenegro',
  situacao: 'em_execucao', motivoRecusa: null, responsavelId: 'j', responsavelNome: 'Jonathan Mendes', acaoTipo: 'fila', filaId: 'f1',
  funilId: null, acaoCriadaEm: '2026-10-07T15:00:00Z', acaoPessoas: 137, criadoEm: '2026-10-07T14:00:00Z', atualizadoEm: '2026-10-07T15:00:00Z',
  placar: { naLista: 137, abordadas: 0, emConversa: 0, vendas: 0, receita: 0 },
  historico: [{ de: null, para: 'solicitada', porNome: 'Elaine Montenegro', nota: null, em: '2026-10-07T14:00:00Z' },
    { de: 'em_analise', para: 'em_execucao', porNome: 'Jonathan Mendes', nota: 'Virou fila com 137 pessoa(s).', em: '2026-10-07T15:00:00Z' }],
};

describe('mapeamento das Estratégias', () => {
  it('pedido: camelCase do banco → domínio; regra incompleta e chave desconhecida saem', () => {
    const e = mapEstrategia(pedidoBanco, 'crm_estrategia_detalhe');
    expect(e.situacao).toBe('em_execucao');
    expect(e.acaoTipo).toBe('fila');
    expect(e.placar?.naLista).toBe(137);
    expect(e.filtros).toEqual({ base: 'alunos', alunos: { tiposTurma: ['thb'] }, naoComprou: { produtos: ['1663254'] },
      respondi: { regras: [{ perguntas: ['O seu interesse hoje é:'], contem: ['fazer a minha holding'] }] } });
    expect(e.historico?.map((h) => h.para)).toEqual(['solicitada', 'em_execucao']);
  });
  it('sem ação: placar null; situação desconhecida é erro (nunca some calada)', () => {
    expect(mapEstrategia({ ...pedidoBanco, acaoTipo: null, placar: null, historico: undefined }).placar).toBeNull();
    expect(() => mapEstrategia({ ...pedidoBanco, situacao: 'aprovada' })).toThrow(/situação desconhecida/);
    expect(() => mapEstrategia('x')).toThrow();
  });
  it('acesso, modelos e opções', () => {
    expect(mapAcesso({ solicitar: true, gestor: false })).toEqual({ solicitar: true, gestor: false, leitor: false });
    expect(mapAcesso({ solicitar: false, gestor: false, leitor: true })).toEqual({ solicitar: false, gestor: false, leitor: true });
    expect(mapModelos([{ chave: 'm', nome: 'M', descricao: 'd', filtros: { base: 'alunos' } }])[0].filtros).toEqual({ base: 'alunos' });
    const o = mapOpcoes({ niveis: ['ouro'], turmas: [{ codigo: 'T33', tipo: 'thb' }], planos: [], statusAcesso: [], linhas: [{ chave: 'sv', nome: 'SV', escada: 'A' }],
      produtos: [{ id: '1', nome: 'P' }], projetos: [], canais: ['hotmart'], perguntas: [{ pergunta: 'P?', formularios: 3 }] });
    expect(o.turmas[0]).toEqual({ codigo: 'T33', tipo: 'thb' });
    expect(o.perguntas[0].formularios).toBe(3);
  });
  it('prévia: ok com números; recusa vira mensagem', () => {
    const r = mapPrevia({ ok: true, total: 137, excluidos: { optOut: 0, jaComprou: 5, emNegociacao: 23, outraAcao: 0 },
      amostra: [{ nome: 'Ana S.', email: 'an***@x.com', nivel: null, turma: 'T33' }] });
    expect(r.previa?.total).toBe(137);
    expect(r.previa?.excluidos.jaComprou).toBe(5);
    expect(r.previa?.amostra[0].email).toBe('an***@x.com');
    expect(mapPrevia({ ok: false, msg: 'Sem acesso às Estratégias.' })).toEqual({ ok: false, msg: 'Sem acesso às Estratégias.' });
  });
  it('salvar manda os filtros limpos e o texto aparado', () => {
    const a = argsSalvar({ titulo: ' T ', objetivo: ' O ', publico: '', filtros: { alunos: { niveis: [] } }, modelo: null, linha: 'sv',
      oferta: ' ', prazo: '', prioridade: 'alta', observacoes: '' });
    expect(a.p).toMatchObject({ titulo: 'T', objetivo: 'O', filtros: {}, prazo: null, oferta: '', linha: 'sv' });
    expect(a.p.id).toBeUndefined();
  });
  it('mapFiltros tolera lixo', () => {
    expect(mapFiltros(null)).toEqual({});
    expect(mapFiltros({ base: 'outra', excluir: { outraAcao: false } })).toEqual({ excluir: { emNegociacao: true, outraAcao: false } });
  });
});
