import { describe, expect, it } from 'vitest';
import type { Atividade } from '../../domain/types';
import {
  agruparAgenda, amanhaAs10, contadoresAgenda, difDias, diaSP, naAba, periodoDaHora, rotuloDia, sugestaoProximoPasso, tempoDesde, toquesDoDia,
} from './agenda';

// 05/10/2026 15:00 em Brasília (UTC-3).
const AGORA = new Date('2026-10-05T18:00:00Z');

const atv = (id: string, venceEm: string, extra: Partial<Atividade> = {}): Atividade => ({
  id, negocioId: null, contatoId: 'c', donoId: 'v-marcos', tipo: 'ligacao', titulo: id, venceEm,
  concluidaEm: null, resultado: null, cadenciaDia: null, ...extra,
});

describe('agenda', () => {
  it('dia e diferença no fuso de Brasília', () => {
    expect(diaSP('2026-10-06T02:00:00Z')).toBe('2026-10-05'); // 23h do dia 5 em SP
    expect(difDias('2026-10-05', '2026-10-07')).toBe(2);
    expect(rotuloDia('2026-10-06', '2026-10-05')).toBe('Amanhã');
    expect(rotuloDia('2026-10-04', '2026-10-05')).toBe('Ontem');
  });

  it('período do dia', () => {
    expect(periodoDaHora(8)).toBe('manha');
    expect(periodoDaHora(12)).toBe('tarde');
    expect(periodoDaHora(19)).toBe('noite');
  });

  it('cada atividade cai na aba certa', () => {
    const atrasadaOntem = atv('a1', '2026-10-04T13:00:00Z');
    const atrasadaHoje = atv('a2', '2026-10-05T12:00:00Z');
    const noite = atv('a3', '2026-10-05T22:30:00Z');
    const amanha = atv('a4', '2026-10-06T13:00:00Z');
    const feita = atv('a5', '2026-10-05T12:00:00Z', { concluidaEm: '2026-10-05T12:10:00Z' });
    expect(naAba(atrasadaOntem, 'hoje', AGORA)).toBe(true);
    expect(naAba(atrasadaOntem, 'atrasadas', AGORA)).toBe(true);
    expect(naAba(noite, 'atrasadas', AGORA)).toBe(false);
    expect(naAba(amanha, 'hoje', AGORA)).toBe(false);
    expect(naAba(amanha, 'proximas', AGORA)).toBe(true);
    expect(naAba(feita, 'hoje', AGORA)).toBe(false);
    expect(naAba(feita, 'concluidas', AGORA)).toBe(true);

    const grupos = agruparAgenda([atrasadaOntem, atrasadaHoje, noite, amanha, feita], 'hoje', AGORA);
    expect(grupos.map((g) => g.key)).toEqual(['atrasadas', 'noite']);
    expect(grupos[0].itens.map((a) => a.id)).toEqual(['a1', 'a2']);
  });

  it('próximas agrupadas por dia, concluídas do mais recente', () => {
    const lista = [atv('p2', '2026-10-08T13:00:00Z'), atv('p1', '2026-10-06T13:00:00Z'), atv('p3', '2026-10-06T19:00:00Z')];
    expect(agruparAgenda(lista, 'proximas', AGORA).map((g) => [g.key, g.itens.map((a) => a.id)])).toEqual([
      ['2026-10-06', ['p1', 'p3']], ['2026-10-08', ['p2']],
    ]);
    const feitas = [atv('f1', 'x', { concluidaEm: '2026-10-03T13:00:00Z' }), atv('f2', 'x', { concluidaEm: '2026-10-05T13:00:00Z' })];
    expect(agruparAgenda(feitas, 'concluidas', AGORA)[0].titulo).toBe('Hoje');
  });

  it('contadores', () => {
    const k = contadoresAgenda([
      atv('a', '2026-10-05T12:00:00Z'), // atrasada
      atv('b', '2026-10-05T22:00:00Z', { tipo: 'whatsapp' }), // hoje no prazo
      atv('c', '2026-10-05T11:00:00Z', { concluidaEm: '2026-10-05T11:05:00Z' }), // ligação feita
    ], AGORA);
    expect(k).toEqual({ hoje: 1, atrasadas: 1, concluidasHoje: 1, ligacoesHoje: 1, ligacoesAgendadasHoje: 2 });
  });

  it('tempo desde, curto', () => {
    expect(tempoDesde('2026-10-05T17:59:40Z', AGORA)).toBe('agora');
    expect(tempoDesde('2026-10-05T17:48:00Z', AGORA)).toBe('há 12 min');
    expect(tempoDesde('2026-10-05T15:00:00Z', AGORA)).toBe('há 3 h');
    expect(tempoDesde('2026-10-04T17:00:00Z', AGORA)).toBe('há 1 dia');
    expect(tempoDesde('2026-10-02T17:00:00Z', AGORA)).toBe('há 3 dias');
  });

  it('toques do dia da cadência numa linha', () => {
    expect(toquesDoDia(2)).toBe('Dia 2: Ligação + WhatsApp');
    expect(toquesDoDia(9)).toBeNull();
  });

  it('próximo passo sugerido', () => {
    expect(sugestaoProximoPasso({ tipo: 'whatsapp', cadenciaDia: 1 }, 'Não atendeu')).toEqual({ tipo: 'ligacao', titulo: 'Ligação (dia 2 da cadência)', cadenciaDia: 2 });
    expect(sugestaoProximoPasso({ tipo: 'whatsapp', cadenciaDia: 5 }, 'Não atendeu')).toMatchObject({ tipo: 'ligacao', cadenciaDia: null });
    expect(sugestaoProximoPasso({ tipo: 'ligacao', cadenciaDia: null }, 'Caixa postal').tipo).toBe('whatsapp');
    expect(sugestaoProximoPasso({ tipo: 'whatsapp', cadenciaDia: 2 }, 'Pediu retorno')).toMatchObject({ tipo: 'whatsapp', cadenciaDia: null });
    expect(sugestaoProximoPasso({ tipo: 'whatsapp', cadenciaDia: 2 }, 'Respondeu').tipo).toBe('ligacao');
    expect(amanhaAs10(new Date(2026, 9, 5, 15))).toBe('2026-10-06T10:00');
  });
});
