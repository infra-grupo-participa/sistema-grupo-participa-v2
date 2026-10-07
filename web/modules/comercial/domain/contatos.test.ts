import { describe, expect, it } from 'vitest';
import { idsUnicos, linhasContatos, paginarContatos, passaFiltro, resumirContatos, type ContatoLinha } from './contatos';
import type { Contato } from './types';

const contato = (id: string, x: Partial<Contato> = {}): Contato => ({
  id, nome: `Pessoa ${id}`, email: null, telefone: null, cidade: null, uf: null, perfil: null, atuaComHolding: null,
  donoId: null, tags: [], utm: {}, score: null, ehAluno: false, optOut: false, criadoEm: '2026-10-01T00:00:00Z', ...x,
});
const linha = (id: string, x: Partial<ContatoLinha> = {}): ContatoLinha => ({
  ...contato(id), lancamentos: 0, ultimaInteracaoEm: null, abertos: [], ...x,
});

describe('linhasContatos', () => {
  it('abertos do mais novo para o mais antigo; última = negócio ou ponto da jornada, o mais recente', () => {
    const [l] = linhasContatos([contato('a')], [
      { id: 'n1', contatoId: 'a', status: 'aberto', produto: 'ht', etapaNome: 'Novo', criadoEm: '2026-10-01', ultimaInteracaoEm: '2026-10-02' },
      { id: 'n2', contatoId: 'a', status: 'aberto', produto: 'hm', etapaNome: 'Negociar', criadoEm: '2026-10-03', ultimaInteracaoEm: null },
      { id: 'n3', contatoId: 'a', status: 'perdido', produto: 'hm', etapaNome: 'Perdido', criadoEm: '2026-09-01', ultimaInteracaoEm: '2026-09-05' },
    ], [{ contatoId: 'a', em: '2026-10-04', lancamento: 'ht33' }, { contatoId: 'a', em: '2026-09-01', lancamento: 'ht33' },
        { contatoId: 'a', em: '2026-08-01', lancamento: 'hm9' }]);
    expect(l.abertos.map((n) => n.id)).toEqual(['n2', 'n1']);
    expect(l.ultimaInteracaoEm).toBe('2026-10-04');
    expect(l.lancamentos).toBe(2);
  });

  it('sem negócio nem jornada: zero e vazio (nunca inventa data)', () => {
    expect(linhasContatos([contato('a')], [])[0]).toMatchObject({ abertos: [], lancamentos: 0, ultimaInteracaoEm: null });
  });
});

describe('passaFiltro', () => {
  it('dono, perfil, UF, tags (qualquer uma), opt-out, aluno e busca', () => {
    const c = contato('a', { donoId: 'v1', perfil: 'advogado', uf: 'SP', tags: ['x', 'y'], optOut: true, ehAluno: true, nome: 'Maria Silva' });
    expect(passaFiltro(c, { dono: 'v1', perfil: 'advogado', uf: 'SP', tags: ['z', 'y'], optOut: true, soAlunos: true, busca: 'silva' })).toBe(true);
    expect(passaFiltro(c, { dono: 'sem_dono' })).toBe(false);
    expect(passaFiltro(c, { dono: 'v2' })).toBe(false);
    expect(passaFiltro(c, { perfil: 'sem' })).toBe(false);
    expect(passaFiltro(c, { uf: 'RJ' })).toBe(false);
    expect(passaFiltro(c, { uf: 'todas', dono: 'todos', perfil: 'todos' })).toBe(true);
    expect(passaFiltro(c, { tags: ['z'] })).toBe(false);
    expect(passaFiltro(contato('b'), { optOut: true })).toBe(false);
    expect(passaFiltro(contato('b'), { soAlunos: true })).toBe(false);
  });
});

describe('paginarContatos', () => {
  const base = [
    linha('a', { nome: 'Ana', criadoEm: '2026-10-03', ultimaInteracaoEm: null, lancamentos: 1 }),
    linha('b', { nome: 'Bruno', criadoEm: '2026-10-01', ultimaInteracaoEm: '2026-10-05', abertos: [{ id: 'n', produto: 'ht', etapaNome: 'Novo' }] }),
    linha('c', { nome: 'Álvaro', criadoEm: '2026-10-02', ultimaInteracaoEm: '2026-10-04', donoId: 'v1', lancamentos: 3 }),
  ];
  const ids = (p: { itens: ContatoLinha[] }) => p.itens.map((x) => x.id);

  it('padrão: mais novo primeiro (criação), total = todos que passam', () => {
    const p = paginarContatos(base, {});
    expect(ids(p)).toEqual(['a', 'c', 'b']);
    expect(p.total).toBe(3);
  });

  it('nome com acento em ordem do português', () => {
    expect(ids(paginarContatos(base, { ordem: 'nome', dir: 'asc' }))).toEqual(['c', 'a', 'b']);
  });

  it('última interação: vazia vai para o fim nas duas direções', () => {
    expect(ids(paginarContatos(base, { ordem: 'ultima', dir: 'desc' }))).toEqual(['b', 'c', 'a']);
    expect(ids(paginarContatos(base, { ordem: 'ultima', dir: 'asc' }))).toEqual(['c', 'b', 'a']);
  });

  it('negócios, lançamentos e dono (pelo nome do vendedor)', () => {
    expect(ids(paginarContatos(base, { ordem: 'negocios', dir: 'desc' }))[0]).toBe('b');
    expect(ids(paginarContatos(base, { ordem: 'lancamentos', dir: 'desc' }))).toEqual(['c', 'a', 'b']);
    expect(ids(paginarContatos(base, { ordem: 'dono', dir: 'desc' }, () => 'Zé'))[0]).toBe('c');
  });

  it('página: offset e limite; total não muda com a página', () => {
    const p = paginarContatos(base, { limite: 2, offset: 2 });
    expect(ids(p)).toEqual(['b']);
    expect(p.total).toBe(3);
  });

  it('limite fica entre 1 e 200', () => {
    const muitos = Array.from({ length: 250 }, (_, i) => linha(String(i).padStart(3, '0')));
    expect(paginarContatos(muitos, { limite: 1000 }).itens).toHaveLength(200);
    expect(paginarContatos(muitos, { limite: 0 }).itens).toHaveLength(1);
  });
});

describe('resumirContatos', () => {
  it('conta sem dono, opt-out e alunos; UFs e tags únicas e ordenadas', () => {
    const r = resumirContatos([
      contato('a', { uf: 'SP', tags: ['b', 'a'], ehAluno: true }),
      contato('b', { donoId: 'v1', uf: 'MG', optOut: true, tags: ['a'] }),
      contato('c', { uf: null }),
    ]);
    expect(r).toEqual({
      total: 3, semDono: 2, optOut: 1, alunos: 1, ufs: ['MG', 'SP'], tags: ['a', 'b'],
      canais: [{ canal: 'sistema', total: 3 }], projetos: [], semProjeto: 3,
    });
  });
});

describe('idsUnicos', () => {
  it('tira vazios e repetidos, mantém a ordem', () => {
    expect(idsUnicos(['a', null, 'b', 'a', undefined, ''])).toEqual(['a', 'b']);
  });
});
