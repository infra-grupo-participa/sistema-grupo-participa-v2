import { describe, expect, it } from 'vitest';
import { logCsv, painel } from './painel';
import type { Experimento } from './types';

const base = (p: Partial<Experimento>): Experimento => ({
  id: Math.random().toString(36), area: 'trafego', nivel: 3, titulo: 'T', status: 'no_ar', decisao: null, hipotese: 'h', previsao: null,
  variavel: null, nao_muda: null, sorteio: null, metrica_tipo: 'taxa', metrica_decisao: 'm', metricas_diagnostico: null, taxa_base: null,
  regua: null, perguntas_regua: {}, amostra_minima: null, grupo_piloto: null, grupo_comparacao: null, medicao_antes: null, confundidores: null,
  alarme: null, decisao_combinada: {}, controle_a: null, controle_b: null, inicio: null, leitura_em: null, revisao_em: null, clickup: null,
  monta_id: null, confere_id: null, le_id: null, revisao_bateu: null, resultado: null, confianca: null, o_que_fizemos: null, aprendizado: null,
  concluido_em: null, mudancas: [], criado_por_nome: null, criado_em: '2026-10-13T12:00:00Z', pode_editar: true, ...p,
});

describe('painel do Laboratório', () => {
  const agora = new Date('2026-10-13T15:00:00Z');
  it('leituras vencendo em até 2 dias e revisões de nível 1', () => {
    const p = painel([
      base({ leitura_em: '2026-10-14' }), base({ leitura_em: '2026-10-30' }),
      base({ nivel: 1, revisao_em: '2026-10-12' }), base({ status: 'rascunho', leitura_em: '2026-10-13' }),
    ], agora);
    expect(p.leiturasVencendo).toHaveLength(1);
    expect(p.revisoesPendentes).toHaveLength(1);
    expect(p.vencida(p.revisoesPendentes[0])).toBe(true);
    expect(p.rascunhos).toHaveLength(1);
  });
  it('taxa de acerto ignora "não dá para saber"', () => {
    const p = painel([
      base({ nivel: 1, status: 'concluido', revisao_bateu: 'sim' }), base({ nivel: 1, status: 'concluido', revisao_bateu: 'nao' }),
      base({ nivel: 1, status: 'concluido', revisao_bateu: 'nao_sabe' }),
    ], agora);
    expect(p.taxaAcerto).toBe(0.5);
    expect(p.revisados).toBe(3);
  });
  it('CSV escapa ponto e vírgula e aspas', () => {
    const csv = logCsv([base({ titulo: 'A; "B"' })]);
    expect(csv.split('\n')[1]).toContain('"A; ""B"""');
  });
});
