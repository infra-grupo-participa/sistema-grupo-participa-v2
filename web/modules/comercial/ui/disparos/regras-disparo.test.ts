import { describe, expect, it } from 'vitest';
import type { FichaDisparo } from '../../domain/types';
import {
  conflitosCom, diasDaAgenda, fichasEmConflito, partesTemplate, resumoDisparos, simularSupressoes, taxasResultado,
} from './regras-disparo';

const agora = new Date('2026-10-05T12:00:00');

describe('simularSupressoes', () => {
  it('conta cada contato uma vez, pelo primeiro motivo', () => {
    const contatos = [
      { id: 'c1', optOut: true },
      { id: 'c2', optOut: false },
      { id: 'c3', optOut: false },
      { id: 'c4', optOut: false },
    ];
    const negocios = [
      { contatoId: 'c1', status: 'aberto' as const, etapa: 'negociar' as const, produto: 'hm' as const },
      { contatoId: 'c2', status: 'ganho' as const, etapa: 'fechado' as const, produto: 'hm' as const },
      { contatoId: 'c3', status: 'aberto' as const, etapa: 'aguardar_pagamento' as const, produto: 'ht' as const },
    ];
    const s = simularSupressoes(contatos, negocios, 'hm', agora);
    expect(s).toMatchObject({ base: 4, suprimidos: 3, elegiveis: 1 });
    expect(s.porMotivo).toEqual({ opt_out: 1, ja_comprou: 1, em_negociacao: 1, disparo_48h: 0 });
  });
});

describe('conflito de 48 h', () => {
  const f = (id: string, produto: FichaDisparo['produto'], quando: string, status: FichaDisparo['status'] = 'aprovada') =>
    ({ id, produto, agendadoPara: quando, status });

  it('marca as duas fichas do mesmo produto a menos de 48 h', () => {
    const r = fichasEmConflito([
      f('a', 'hm', '2026-10-05T10:00:00'),
      f('b', 'hm', '2026-10-06T20:00:00'),
      f('c', 'ht', '2026-10-05T11:00:00'),
      f('d', 'hm', '2026-10-09T10:00:00'),
    ]);
    expect([...r].sort()).toEqual(['a', 'b']);
  });

  it('ignora rascunho e reprovada', () => {
    expect(fichasEmConflito([f('a', 'hm', '2026-10-05T10:00:00'), f('b', 'hm', '2026-10-05T12:00:00', 'reprovada')]).size).toBe(0);
    expect(conflitosCom([f('a', 'hm', '2026-10-05T10:00:00', 'rascunho')], 'hm', '2026-10-05T11:00:00')).toEqual([]);
    expect(conflitosCom([f('a', 'hm', '2026-10-05T10:00:00')], 'hm', '2026-10-06T11:00:00')).toEqual(['a']);
  });
});

describe('apoio', () => {
  it('agenda tem 15 dias centrados em hoje', () => {
    const d = diasDaAgenda(agora);
    expect(d).toHaveLength(15);
    expect(d[7].getDate()).toBe(5);
  });

  it('taxas sobre entregues', () => {
    expect(taxasResultado({ entregues: 100, lidas: 70, respostas: 20, falhas: 0 })).toEqual({ leitura: 70, resposta: 20, falha: 0 });
  });

  it('separa variáveis do template', () => {
    expect(partesTemplate('Oi {{nome}}, tudo bem?')).toEqual([
      { texto: 'Oi ', variavel: false }, { texto: '{{nome}}', variavel: true }, { texto: ', tudo bem?', variavel: false },
    ]);
  });
});

describe('resumoDisparos', () => {
  const f = (id: string, status: FichaDisparo['status'], agendadoPara: string, resultado: FichaDisparo['resultado'] = null) =>
    ({ id, produto: 'hm' as const, status, agendadoPara, resultado });
  it('conta aguardando, próximos 7 dias, conflitos e taxas sobre as somas', () => {
    const r = resumoDisparos([
      f('a', 'aguardando_aprovacao', '2026-10-06T10:00:00'),
      f('b', 'aprovada', '2026-10-06T20:00:00'),
      f('c', 'rascunho', '2026-10-07T10:00:00'),
      f('d', 'enviada', '2026-09-20T10:00:00', { entregues: 100, lidas: 50, respostas: 10, falhas: 2 }),
      f('e', 'enviada', '2026-09-25T10:00:00', { entregues: 100, lidas: 30, respostas: 10, falhas: 0 }),
    ], agora);
    expect(r.aguardando).toBe(1);
    expect(r.proximos7).toBe(2);
    expect(r.conflitos).toBe(2);
    expect(r.entregues).toBe(200);
    expect(r.leitura).toBe(40);
    expect(r.resposta).toBe(10);
  });
  it('sem resultado, taxas nulas', () => {
    expect(resumoDisparos([], agora)).toMatchObject({ entregues: 0, leitura: null, resposta: null });
  });
});
