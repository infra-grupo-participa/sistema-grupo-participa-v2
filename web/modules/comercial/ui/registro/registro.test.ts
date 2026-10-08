import { describe, expect, it } from 'vitest';
import type { LogCrm } from '../../domain/types';
import {
  agruparPorDia, avisoLimite, chipsAtivos, FILTRO_INICIAL, filtrarLog, gerarCsv, inicioDoPeriodo, juntarPaginas, nomeAutor,
  numerosRegistro, tituloDia,
} from './registro';

// 05/10/2026 15:00 em Brasília (UTC−3).
const AGORA = new Date('2026-10-05T18:00:00Z');

const log = (id: string, em: string, extra: Partial<LogCrm> = {}): LogCrm => ({
  id, em, autorId: 'v-ana', acao: 'editou', entidade: 'negocio', entidadeId: 'n-1', contatoId: 'c-1',
  resumo: `Resumo ${id}`, mudancas: [], ...extra,
});

const nomeDe = (id: string | null) => ({ 'v-ana': 'Ana', 'v-bia': 'Bia' } as Record<string, string>)[id ?? ''] ?? '—';

describe('páginas do servidor', () => {
  it('junta a página recente com as antigas sem repetir linha', () => {
    const r = juntarPaginas([log('3', ''), log('2', '')], [log('2', ''), log('1', '')]);
    expect(r.map((l) => l.id)).toEqual(['3', '2', '1']);
  });

  it('avisa o corte só quando a última página veio cheia', () => {
    expect(avisoLimite(500, true)).toContain('Mostrando as 500 alterações mais recentes');
    expect(avisoLimite(1500, true)).toContain('1.500');
    expect(avisoLimite(320, false)).toBeNull();
  });
});

describe('filtros', () => {
  const logs = [
    log('hoje', '2026-10-05T12:00:00Z', { acao: 'moveu_etapa', resumo: 'Moveu Ána Barros' }),
    log('ontem', '2026-10-04T12:00:00Z', { autorId: null, acao: 'marcou_ganho' }),
    log('velho', '2026-08-01T12:00:00Z', { autorId: 'v-bia', entidade: 'funil' }),
  ];

  it('início do período em Brasília', () => {
    expect(inicioDoPeriodo('hoje', AGORA)).toBe('2026-10-05T03:00:00.000Z');
    expect(inicioDoPeriodo('7d', AGORA)).toBe('2026-09-29T03:00:00.000Z');
    expect(inicioDoPeriodo('tudo', AGORA)).toBeUndefined();
    // 01h em Brasília do dia 5 ainda é dia 5.
    expect(inicioDoPeriodo('hoje', new Date('2026-10-05T04:00:00Z'))).toBe('2026-10-05T03:00:00.000Z');
  });

  it('período, pessoa, sistema, ação, entidade e busca sem acento', () => {
    const ids = (f: Partial<typeof FILTRO_INICIAL>) => filtrarLog(logs, { ...FILTRO_INICIAL, ...f }, AGORA).map((l) => l.id);
    expect(ids({})).toEqual(['hoje', 'ontem']);
    expect(ids({ periodo: 'tudo' })).toEqual(['hoje', 'ontem', 'velho']);
    expect(ids({ periodo: 'hoje' })).toEqual(['hoje']);
    expect(ids({ periodo: 'tudo', autor: 'sistema' })).toEqual(['ontem']);
    expect(ids({ periodo: 'tudo', autor: 'v-bia' })).toEqual(['velho']);
    expect(ids({ acao: 'moveu_etapa' })).toEqual(['hoje']);
    expect(ids({ periodo: 'tudo', entidade: 'funil' })).toEqual(['velho']);
    expect(ids({ busca: 'ana barros' })).toEqual(['hoje']);
  });

  it('chips mostram os filtros aplicados', () => {
    expect(chipsAtivos(FILTRO_INICIAL, nomeDe)).toEqual([]);
    const c = chipsAtivos({ ...FILTRO_INICIAL, autor: 'sistema', acao: 'moveu_etapa', entidade: 'negocio', busca: ' x ' }, nomeDe);
    expect(c.map((x) => x.chave)).toEqual(['autor', 'acao', 'entidade', 'busca']);
    expect(c[0].rotulo).toBe('Pessoa: Sistema');
    expect(chipsAtivos({ ...FILTRO_INICIAL, autor: 'v-ana' }, nomeDe)[0].rotulo).toBe('Pessoa: Ana');
  });
});

describe('linha do tempo', () => {
  it('agrupa por dia em Brasília, mais recente primeiro', () => {
    const g = agruparPorDia([
      log('a', '2026-10-04T12:00:00Z'),
      log('b', '2026-10-05T02:30:00Z'), // 23h30 do dia 4 em Brasília
      log('c', '2026-10-05T15:00:00Z'),
    ], AGORA);
    expect(g.map((x) => x.titulo)).toEqual(['Hoje', 'Ontem']);
    expect(g[1].itens.map((l) => l.id)).toEqual(['b', 'a']);
  });

  it('título com data quando não é hoje nem ontem', () => {
    expect(tituloDia('2026-10-01', '2026-10-05')).toMatch(/1 de outubro/);
    expect(tituloDia('2025-10-01', '2026-10-05')).toMatch(/2025/);
  });
});

describe('números', () => {
  it('conta alterações, pessoas, negócios movidos (distintos) e perdas', () => {
    const n = numerosRegistro([
      log('1', '', { acao: 'moveu_etapa', entidadeId: 'n-1' }),
      log('2', '', { acao: 'moveu_etapa', entidadeId: 'n-1', autorId: 'v-bia' }),
      log('3', '', { acao: 'marcou_perdido', autorId: null }),
    ]);
    expect(n).toEqual({ alteracoes: 3, pessoas: 2, negociosMovidos: 1, perdas: 1 });
  });
});

describe('CSV', () => {
  it('cabeçalho, ";" e aspas escapadas', () => {
    const csv = gerarCsv([log('1', '2026-10-05T12:00:00Z', {
      autorId: null, resumo: 'Disse "oi"; tchau', mudancas: [{ campo: 'etapa', antes: 'A', depois: 'B' }],
    })], nomeDe);
    expect(csv.startsWith('﻿data_hora;autor;')).toBe(true);
    const linha = csv.split('\r\n')[1];
    expect(linha).toContain(';Sistema;Editou;Negócio;n-1;c-1;');
    expect(linha).toContain('"Disse ""oi""; tchau"');
    expect(linha).toContain('etapa: A → B');
  });

  it('nome do autor', () => {
    expect(nomeAutor(null, nomeDe)).toBe('Sistema');
    expect(nomeAutor('v-ana', nomeDe)).toBe('Ana');
  });
});
