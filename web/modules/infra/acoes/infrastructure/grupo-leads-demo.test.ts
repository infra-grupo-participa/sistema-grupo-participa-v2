import { describe, expect, it } from 'vitest';
import { ENTRADAS_GRUPO_ACAO_DEMO } from './grupo-leads-demo';

describe('massa sintética do modal de ingresso', () => {
  it('representa as três origens do contrato sem incluir contatos reais', () => {
    expect(ENTRADAS_GRUPO_ACAO_DEMO).toHaveLength(13);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'lista_disparo')).toHaveLength(10);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'base_leads')).toHaveLength(1);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'nao_encontrado')).toHaveLength(2);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'nao_encontrado').every((x) =>
      x.nome === null && x.email === null && x.telefone === x.foneGrupo && x.turma === null && x.instrucao === null,
    )).toBe(true);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.every((x) => x.email === null || x.email.endsWith('@example.invalid'))).toBe(true);
  });
});
