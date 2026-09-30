import { describe, expect, it } from 'vitest';
import { contarPorAba, pendenciasAluno, type ContextoPendencias } from './pendencias-aluno';

const aluno = (x: Partial<Parameters<typeof pendenciasAluno>[0]> = {}) => ({
  turma_codigo: null,
  tratamento_manual: null,
  instrucao: null,
  espaco_instrucao: null,
  eh_socio: null,
  ...x,
});
const semNada: ContextoPendencias = { socio: { titularNome: null, titular: null }, placa: null };

describe('pendenciasAluno', () => {
  it('sem sinal pintado → lista vazia', () => {
    expect(pendenciasAluno(aluno(), semNada)).toEqual([]);
  });

  it('renovação NÃO é pendência (pinta 93% da base): turma T17R ou T31 sozinha → lista vazia', () => {
    expect(pendenciasAluno(aluno({ turma_codigo: 'T17R' }), semNada)).toEqual([]);
    expect(pendenciasAluno(aluno({ turma_codigo: 'T31' }), semNada)).toEqual([]);
  });

  it('tratamento_manual preenchido vira pendência; só espaço não', () => {
    expect(pendenciasAluno(aluno({ tratamento_manual: 'Liberar à mão' }), semNada)).toEqual([
      { aba: 'programa', texto: 'Tratamento manual: Liberar à mão', tom: 'amarelo' },
    ]);
    expect(pendenciasAluno(aluno({ tratamento_manual: '   ' }), semNada)).toEqual([]);
  });

  it('sócio sem titular: pela instrução, pelo eh_socio; com nome do titular não conta', () => {
    const txt = (a: ReturnType<typeof aluno>, ctx = semNada) => pendenciasAluno(a, ctx).map((p) => p.texto);
    expect(txt(aluno({ instrucao: 'AURUM - SÓCIO' }))).toEqual(['Sócio sem titular informado']);
    expect(txt(aluno({ eh_socio: true }))).toEqual(['Sócio sem titular informado']);
    expect(txt(aluno({ eh_socio: true }), { ...semNada, socio: { titularNome: 'Ana', titular: null } })).toEqual([]);
    // Titular achado pela FK mas sem nome no registro: a ficha pinta "Titular não informado".
    expect(txt(aluno(), { ...semNada, socio: { titularNome: null, titular: { nome: null } } })).toEqual(['Sócio sem titular informado']);
    expect(txt(aluno({ instrucao: 'AURUM' }))).toEqual([]);
  });

  it('placa: correção amarelo, rejeitada vermelho; reenvio e andamento não', () => {
    const p = (placa: ContextoPendencias['placa']) => pendenciasAluno(aluno(), { ...semNada, placa });
    expect(p({ status: 'em_analise', regularizacao_pendente: true })).toEqual([
      { aba: 'jornada', texto: 'Placa: Aluno reprovado · aguardando nova documentação', tom: 'amarelo' },
    ]);
    expect(p({ status: 'rejeitado' })).toEqual([{ aba: 'jornada', texto: 'Placa: Rejeitado', tom: 'vermelho' }]);
    expect(p({ status: 'em_analise', regularizacao_pendente: true, proof_url: 'x', declaracao_url: 'y' })).toEqual([]);
    expect(p({ status: 'concluido' })).toEqual([]);
  });

  it('contarPorAba soma por destino', () => {
    const ps = pendenciasAluno(aluno({ turma_codigo: 'T5', tratamento_manual: 'x' }), { ...semNada, placa: { status: 'rejeitado' } });
    expect(contarPorAba(ps)).toEqual({ programa: 1, jornada: 1 });
  });
});
