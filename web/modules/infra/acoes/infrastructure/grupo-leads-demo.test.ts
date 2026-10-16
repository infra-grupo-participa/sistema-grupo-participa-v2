import { describe, expect, it } from 'vitest';
import { ENTRADAS_GRUPO_ACAO_DEMO } from './grupo-leads-demo';

describe('massa sintética do modal de ingresso', () => {
  it('representa as quatro origens do contrato sem incluir contatos reais', () => {
    expect(ENTRADAS_GRUPO_ACAO_DEMO).toHaveLength(14);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'lista_disparo')).toHaveLength(10);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'base_leads')).toHaveLength(1);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'central_alunos')).toHaveLength(1);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'nao_encontrado')).toHaveLength(2);
    // apto só para quem está na lista do disparo (regra do Victor, 16/10/2026)
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.apto).every((x) => x.origem === 'lista_disparo')).toBe(true);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.filter((x) => x.origem === 'nao_encontrado').every((x) =>
      x.nome === null && x.email === null && x.telefone === x.foneGrupo && x.turma === null && x.instrucao === null,
    )).toBe(true);
    expect(ENTRADAS_GRUPO_ACAO_DEMO.every((x) => x.email === null || x.email.endsWith('@example.invalid'))).toBe(true);
  });
});
