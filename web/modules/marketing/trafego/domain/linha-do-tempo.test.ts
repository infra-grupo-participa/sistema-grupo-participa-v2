import { describe, expect, it } from 'vitest';
import { marcoDaTarefa, montarLinhaDoTempo } from './linha-do-tempo';
import type { TarefaClickup } from './tipos';

const t = (id: string, x: Partial<TarefaClickup>): TarefaClickup =>
  ({ id, nome: `Tarefa ${id} (exemplo)`, status: null, criada_em: null, atualizada_em: null, inicio: null, prazo: null, concluida_em: null, responsaveis: [], url: null, ...x });

describe('linha do tempo: gasto diário + ClickUp', () => {
  it('marco da tarefa: conclusão > prazo > início > criação, no dia de São Paulo', () => {
    expect(marcoDaTarefa(t('a', { criada_em: '2026-10-01T10:00:00Z', prazo: '2026-10-03T12:00:00Z', concluida_em: '2026-10-04T01:30:00Z' })))
      .toEqual({ dia: '2026-10-03', tipo: 'concluida' }); // 01:30 UTC = 22:30 do dia anterior em SP
    expect(marcoDaTarefa(t('b', { criada_em: '2026-10-01T10:00:00Z' }))).toEqual({ dia: '2026-10-01', tipo: 'criada' });
    expect(marcoDaTarefa(t('c', {}))).toBeNull();
  });

  it('dias seguidos, gasto nulo onde não houve coleta, tarefa no dia dela, prazo futuro estende até 14 dias', () => {
    const serie = [{ dia: '2026-10-01', gasto: 100, impressoes: 0, cliques_link: 0, leads_plataforma: null }, { dia: '2026-10-03', gasto: 250, impressoes: 0, cliques_link: 0, leads_plataforma: null }];
    const r = montarLinhaDoTempo(serie, [
      t('a', { concluida_em: '2026-10-02T15:00:00Z' }),
      t('b', { prazo: '2026-10-06T15:00:00Z' }),
      t('c', { prazo: '2026-12-30T15:00:00Z' }),
      t('d', {}),
    ], '2026-10-04');
    expect(r.dias.map((d) => [d.dia, d.gasto, d.tarefas.map((x) => x.id).join('')])).toEqual([
      ['2026-10-01', 100, ''], ['2026-10-02', null, 'a'], ['2026-10-03', 250, ''], ['2026-10-04', null, ''], ['2026-10-05', null, ''], ['2026-10-06', null, 'b'],
    ]);
    expect([r.maxGasto, r.fora]).toEqual([250, 2]);
  });

  it('janela de no máximo N dias; sem nada = vazio', () => {
    const serie = Array.from({ length: 90 }, (_, i) => ({ dia: new Date(Date.UTC(2026, 6, 1 + i)).toISOString().slice(0, 10), gasto: i, impressoes: 0, cliques_link: 0, leads_plataforma: null }));
    const r = montarLinhaDoTempo(serie, [t('velha', { concluida_em: '2026-07-02T15:00:00Z' })], '2026-09-28', 60);
    expect([r.dias.length, r.dias[0].dia, r.dias.at(-1)!.dia, r.fora]).toEqual([60, '2026-07-31', '2026-09-28', 1]);
    expect(montarLinhaDoTempo([], [], '2026-10-04')).toEqual({ dias: [], maxGasto: 0, fora: 0 });
  });
});
