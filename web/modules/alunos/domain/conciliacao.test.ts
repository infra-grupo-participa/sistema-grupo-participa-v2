import { describe, expect, it } from 'vitest';
import {
  abaDoItem, aplicarDecisao, bigintNum, contar, contarAbertosAlta, decisoesDoTipo, indexarPorAluno, normalizarItens, ordenarItens,
  resumoDetalhe, rotuloTipo, umaLinhaPorItem, type ItemConciliacao,
} from './conciliacao';

const it0 = (x: Partial<ItemConciliacao> = {}): ItemConciliacao => ({
  item: 'i', aluno_id: 'a', ref_aluno_id: null, ref_externa: null, grupo: 'cadastro', tipo: 'email_vazio',
  severidade: 'media', acao: 'preencher_email', detalhe: {}, conferido: false, decisao_id: null, ...x,
});

describe('conciliacao', () => {
  it('normaliza: descarta linha sem item/tipo; vazio vira null; detalhe não-objeto vira {}', () => {
    const r = normalizarItens([
      { item: 'x', tipo: 'email_vazio', aluno_id: '', grupo: 'cadastro', severidade: 'baixa', acao: 'a', detalhe: [1], conferido: 'sim' },
      { tipo: 'sem_item' }, null, 3,
    ]);
    expect(r).toEqual([{ item: 'x', aluno_id: null, ref_aluno_id: null, ref_externa: null, grupo: 'cadastro', tipo: 'email_vazio', severidade: 'baixa', acao: 'a', detalhe: {}, conferido: false, decisao_id: null }]);
  });

  it('aba de destino', () => {
    expect(abaDoItem({ grupo: 'fora_base', tipo: 'placa_sem_aluno' })).toBe('jornada');
    expect(abaDoItem({ grupo: 'identidade', tipo: 'possivel_duplicado' })).toBe('resumo');
    expect(abaDoItem({ grupo: 'fora_base', tipo: 'comprou_fora_da_base' })).toBe('resumo');
    expect(abaDoItem({ grupo: 'vinculo', tipo: 'socio_cadeia' })).toBe('programa');
  });

  it('ordena severidade → grupo → tipo', () => {
    const r = ordenarItens([
      it0({ item: '1', severidade: 'baixa', grupo: 'vinculo' }),
      it0({ item: '2', severidade: 'alta', grupo: 'cadastro' }),
      it0({ item: '3', severidade: 'alta', grupo: 'vinculo' }),
    ]).map((i) => i.item);
    expect(r).toEqual(['3', '2', '1']);
  });

  it('par de sócios (2 linhas, mesmo item): lista 1×, conta 1 item e 2 alunos', () => {
    const par = [it0({ item: 'p', aluno_id: 'a', grupo: 'vinculo', tipo: 'socio_par_mutuo' }), it0({ item: 'p', aluno_id: 'b', grupo: 'vinculo', tipo: 'socio_par_mutuo' })];
    expect(umaLinhaPorItem(par)).toHaveLength(1);
    const c = contar([...par, it0({ item: 'e', aluno_id: 'a' })]);
    expect(c.total).toEqual({ itens: 2, alunos: 2, conferidos: 0 });
    expect(c.grupo.vinculo).toEqual({ itens: 1, alunos: 2, conferidos: 0 });
    expect(c.tipo.email_vazio).toEqual({ itens: 1, alunos: 1, conferidos: 0 });
  });

  it('resumo no cliente: aberto e conferido separados, por grupo/tipo/severidade', () => {
    const c = contar([
      it0({ item: 'a1', severidade: 'alta' }),
      it0({ item: 'c1', severidade: 'alta', conferido: true, decisao_id: 7 }),
      it0({ item: 'c1', aluno_id: 'b', severidade: 'alta', conferido: true, decisao_id: 7 }),
      it0({ item: 'm1', aluno_id: 'b', severidade: 'media' }),
    ]);
    expect(c.total).toEqual({ itens: 2, alunos: 2, conferidos: 1 });
    expect(c.severidade.alta).toEqual({ itens: 1, alunos: 1, conferidos: 1 });
    expect(c.severidade.media).toEqual({ itens: 1, alunos: 1, conferidos: 0 });
    expect(c.grupo.cadastro.conferidos).toBe(1);
  });

  it('aplicarDecisao muda as 2 linhas do par e só elas; ida e volta restaura', () => {
    const base = [it0({ item: 'p', aluno_id: 'a' }), it0({ item: 'p', aluno_id: 'b' }), it0({ item: 'x' })];
    const m = aplicarDecisao(base, 'p', true, 42);
    expect(m.map((i) => [i.conferido, i.decisao_id])).toEqual([[true, 42], [true, 42], [false, null]]);
    expect(m[2]).toBe(base[2]);
    expect(aplicarDecisao(m, 'p', false, null)).toEqual(base);
    expect(indexarPorAluno(m).get('b')).toBeUndefined();
    expect(contarAbertosAlta(aplicarDecisao([it0({ item: 'h', severidade: 'alta' })], 'h', true, 1))).toBe(0);
  });

  it('bigint do PostgREST vira number; lixo vira null', () => {
    expect(bigintNum(12)).toBe(12);
    expect(bigintNum('34')).toBe(34);
    expect(bigintNum(null)).toBeNull();
    expect(bigintNum('x')).toBeNull();
    expect(bigintNum(1.5)).toBeNull();
    expect(normalizarItens([{ item: 'i', tipo: 't', conferido: true, decisao_id: 9 }])[0].decisao_id).toBe(9);
  });

  it('índice por aluno ignora conferido e sem aluno; contador de alta conta itens distintos em aberto', () => {
    const itens = [
      it0({ item: 'p', aluno_id: 'a', severidade: 'alta' }), it0({ item: 'p', aluno_id: 'b', severidade: 'alta' }),
      it0({ item: 'c', aluno_id: 'a', severidade: 'alta', conferido: true }),
      it0({ item: 'x', aluno_id: null, severidade: 'alta' }),
      it0({ item: 'm', aluno_id: 'a' }),
    ];
    const m = indexarPorAluno(itens);
    expect(m.get('a')?.map((i) => i.item)).toEqual(['p', 'm']);
    expect(m.has('b')).toBe(true);
    expect(contarAbertosAlta(itens)).toBe(2);
  });

  it('resumo do detalhe só com o que sabe traduzir', () => {
    expect(resumoDetalhe(it0({ detalhe: { campos: ['plano', 'turma'], desconhecido: 1 } }))).toBe('plano, turma');
    expect(resumoDetalhe(it0({ detalhe: { motivo: 'm_x' } }), (m) => `<${m}>`)).toBe('<m_x>');
    expect(resumoDetalhe(it0({ detalhe: { tem_nome_titular: true } }))).toBe('tem o nome do titular no cadastro');
    expect(resumoDetalhe(it0({ detalhe: {} }))).toBe('');
    // situacao_desatualizada manda objeto {situacao, status}; revogado manda string + motivo de acesso
    expect(resumoDetalhe(it0({ detalhe: { gravado: { situacao: 'vencido', status: 's' }, calculado: { situacao: 'em_dia' } } })))
      .toBe('gravado Vencido, calculado Em dia');
    expect(resumoDetalhe(it0({ detalhe: { motivo: 'acessos_revogados', calculado: 'a_vencer', gravado: 'a_vencer' } }), (m) => `<${m}>`))
      .toBe('status acessos revogados · gravado A vencer, calculado A vencer');
    expect(resumoDetalhe(it0({ detalhe: { ultima_paga_em: '2026-09-12' } }))).toBe('última compra paga em 12/09/2026');
  });

  it('decisões por tipo e rótulo de tipo desconhecido', () => {
    expect(decisoesDoTipo('possivel_duplicado')).toEqual(['conferido', 'pessoas_diferentes']);
    // o banco recusa pessoas_diferentes fora de possivel_duplicado (22023)
    expect(decisoesDoTipo('conflito_identidade')).toEqual(['conferido']);
    expect(decisoesDoTipo('revogado_com_vigencia')).toEqual(['conferido', 'manter_sem_acesso']);
    expect(decisoesDoTipo('email_vazio')).toEqual(['conferido']);
    expect(rotuloTipo('tipo_novo')).toBe('tipo novo');
    expect(rotuloTipo('comprou_em_ativacao')).not.toBe('comprou em ativacao');
    expect(rotuloTipo('revogado_com_vigencia')).not.toMatch(/manual/i);
    expect(rotuloTipo('comprou_fora_da_base')).toMatch(/aluno ativo/);
  });
});
