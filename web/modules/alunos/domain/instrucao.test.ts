import { describe, expect, it } from 'vitest';
import { INSTRUCOES, instrucaoCanonica, parseInstrucao } from './aluno-360';

type Entrada = Parameters<typeof parseInstrucao>[0];
const a = (p: Partial<Entrada>): Entrada => ({ instrucao: null, espaco_instrucao: null, eh_socio: null, ...p });

describe('parseInstrucao', () => {
  it('cobre as 10 instruções da Central', () => {
    expect(INSTRUCOES).toEqual([
      'THB', 'THB - SÓCIO',
      'PLATINA', 'PLATINA - SÓCIO',
      'AURUM', 'AURUM - SÓCIO',
      'DIAMANTE', 'DIAMANTE - SÓCIO',
      'DIAMANTE VERMELHO', 'DIAMANTE VERMELHO - SÓCIO',
    ]);
    for (const i of INSTRUCOES) expect(parseInstrucao(a({ instrucao: i }))).not.toBeNull();
  });

  it('separa nível e papel', () => {
    expect(parseInstrucao(a({ instrucao: 'AURUM' }))).toMatchObject({ nivel: 'AURUM', ehSocio: false, label: 'Aurum' });
    expect(parseInstrucao(a({ instrucao: 'AURUM - SÓCIO' }))).toMatchObject({ nivel: 'AURUM', ehSocio: true, label: 'Aurum · sócio' });
  });

  it('não confunde DIAMANTE com DIAMANTE VERMELHO', () => {
    expect(parseInstrucao(a({ instrucao: 'DIAMANTE VERMELHO - SÓCIO' }))).toMatchObject({
      nivel: 'DIAMANTE VERMELHO', ehSocio: true, nivelLabel: 'Diamante Vermelho',
    });
  });

  it('aceita variações de escrita do sufixo de sócio', () => {
    for (const v of ['AURUM - SÓCIO', 'aurum - socio', 'AURUM — SÓCIO', 'AURUM -SOCIOS']) {
      expect(parseInstrucao(a({ instrucao: v }))).toMatchObject({ nivel: 'AURUM', ehSocio: true });
    }
  });

  it('infere do espaço quando a instrução está vazia, e marca como inferido', () => {
    const r = parseInstrucao(a({ instrucao: '', espaco_instrucao: 'mastermind_diamante', eh_socio: true }));
    expect(r).toMatchObject({ nivel: 'DIAMANTE', ehSocio: true, inferido: true });
  });

  it('eh_socio manda mesmo quando o texto não tem o sufixo', () => {
    // Cadastro manual grava "AURUM" e marca o booleano — a etiqueta não pode dizer titular.
    expect(parseInstrucao(a({ instrucao: 'AURUM', eh_socio: true }))).toMatchObject({ ehSocio: true });
  });

  it('devolve null quando não há instrução nem espaço', () => {
    expect(parseInstrucao(a({}))).toBeNull();
    expect(instrucaoCanonica(a({}))).toBeNull();
  });

  it('instrucaoCanonica volta ao valor do banco', () => {
    expect(instrucaoCanonica(a({ instrucao: 'PLATINA - SÓCIO' }))).toBe('PLATINA - SÓCIO');
    expect(instrucaoCanonica(a({ espaco_instrucao: 'holding_masters', eh_socio: true }))).toBe('THB - SÓCIO');
  });
});
