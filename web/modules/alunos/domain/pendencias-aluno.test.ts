import { describe, expect, it } from 'vitest';
import { contarPorAba, pendenciasAluno, type ContextoPendencias } from './pendencias-aluno';
import type { ItemConciliacao } from './conciliacao';

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
    expect(contarPorAba(ps)).toEqual({ resumo: 0, programa: 1, jornada: 1 });
  });

  it('conciliação: item em aberto vira pendência na aba de destino; info e conferido não; par conta 1', () => {
    const item = (x: Partial<ItemConciliacao>): ItemConciliacao => ({
      item: 'i1', aluno_id: 'a', ref_aluno_id: null, ref_externa: null, grupo: 'cadastro', tipo: 'email_vazio',
      severidade: 'media', acao: 'preencher_email', detalhe: {}, conferido: false, decisao_id: null, ...x,
    });
    const ps = pendenciasAluno(aluno(), { ...semNada, conciliacao: [
      item({ item: 'i1', grupo: 'identidade', tipo: 'possivel_duplicado', severidade: 'alta' }),
      item({ item: 'i1', grupo: 'identidade', tipo: 'possivel_duplicado', severidade: 'alta' }),
      item({ item: 'i2' }),
      item({ item: 'i3', severidade: 'info' }),
      item({ item: 'i4', conferido: true }),
    ] });
    expect(ps).toEqual([
      { aba: 'resumo', texto: 'Possível cadastro duplicado', tom: 'vermelho' },
      { aba: 'programa', texto: 'Sem e-mail', tom: 'amarelo' },
    ]);
    expect(contarPorAba(ps)).toEqual({ resumo: 1, programa: 1, jornada: 0 });
  });

  it('conciliação com item de vínculo suprime "Sócio sem titular informado" (não conta 2×)', () => {
    const vinc: ItemConciliacao = {
      item: 'v', aluno_id: 'a', ref_aluno_id: null, ref_externa: null, grupo: 'vinculo', tipo: 'socio_sem_vinculo',
      severidade: 'media', acao: 'definir_titular', detalhe: {}, conferido: false, decisao_id: null,
    };
    const txt = pendenciasAluno(aluno({ eh_socio: true }), { ...semNada, conciliacao: [vinc] }).map((p) => p.texto);
    expect(txt).toEqual(['Marcado como sócio, sem titular ligado']);
    // vinculo_sem_marcacao não cobre: as duas ficam.
    const txt2 = pendenciasAluno(aluno({ eh_socio: true }), { ...semNada, conciliacao: [{ ...vinc, tipo: 'vinculo_sem_marcacao' }] }).map((p) => p.texto);
    expect(txt2).toEqual(['Sócio sem titular informado', 'Ligado a um titular, mas não marcado como sócio']);
  });
});
