import { describe, expect, it } from 'vitest';
import { custoCaptacaoBlack } from './custo-captacao';
import type { Campanha, TrafegoBlack } from './tipos';

const campanhas: Campanha[] = [
  { id: 'c2-lead', nome: 'CF | BF26 | C2 | ISCA | LEADS', canal: 'meta', funil: 'iscas', etapa: 'C2', subtipo: 'ISCA', fase: 'captacao' },
  { id: 'c3-lead', nome: 'CF | BF26 | C3 | META | LEAD', canal: 'meta', funil: 'c3', etapa: 'C3', fase: 'captacao' },
  { id: 'c2-sem-lead', nome: 'CF | BF26 | C2 | CONSULTORIA | META', canal: 'meta', funil: 'consultoria', etapa: 'C2', subtipo: 'CONSULTORIA', fase: 'captacao' },
  { id: 'c3-rmk', nome: 'CF | BF26 | C3 | LEAD | REMARKETING', canal: 'meta', funil: 'c3', etapa: 'C3', fase: 'remarketing' },
  { id: 'c1-lead', nome: 'CF | BF26 | C1 | LEAD', canal: 'meta', funil: 'c1', etapa: 'C1', fase: 'captacao' },
  { id: 'sem-etapa', nome: 'CF | BF26 | LEAD', canal: 'meta', funil: null, etapa: null, fase: 'captacao' },
];

const trafego = (rows: NonNullable<TrafegoBlack['gastoCampanhasPorDia']>): TrafegoBlack => ({
  campanhas, conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null, gastoCampanhasPorDia: rows,
});

describe('custo de captação no funil macro', () => {
  it('inclui nomes com LEAD em C2/C3, exclui remarketing, C1 e Sem etapa, e aplica o período', () => {
    const r = custoCaptacaoBlack(trafego([
      { campanhaId: 'c2-lead', dia: '2026-10-10', gasto: 100 },
      { campanhaId: 'c2-lead', dia: '2026-10-05', gasto: 70 },
      { campanhaId: 'c3-lead', dia: '2026-10-11', gasto: 250 },
      { campanhaId: 'c2-sem-lead', dia: '2026-10-11', gasto: 9000 },
      { campanhaId: 'c3-rmk', dia: '2026-10-11', gasto: 8000 },
      { campanhaId: 'c1-lead', dia: '2026-10-11', gasto: 7000 },
      { campanhaId: 'sem-etapa', dia: '2026-10-11', gasto: 6000 },
    ]), { de: '2026-10-10', ate: '2026-10-13' });

    expect(r).toEqual({
      c2: 100, c3: 250, total: 350,
      campanhasC2: ['CF | BF26 | C2 | ISCA | LEADS'],
      campanhasC3: ['CF | BF26 | C3 | META | LEAD'],
      campanhasSemLead: ['CF | BF26 | C2 | CONSULTORIA | META'],
      campanhasRemarketing: ['CF | BF26 | C3 | LEAD | REMARKETING'],
    });
  });

  it('sem gasto positivo conhecido no período retorna sem dado, nunca zero', () => {
    const r = custoCaptacaoBlack(trafego([
      { campanhaId: 'c2-lead', dia: '2026-10-05', gasto: 100 },
      { campanhaId: 'c3-lead', dia: '2026-10-12', gasto: 0 },
    ]), { de: '2026-10-10', ate: '2026-10-13' });
    expect([r.c2, r.c3, r.total]).toEqual([null, null, null]);
  });
});
