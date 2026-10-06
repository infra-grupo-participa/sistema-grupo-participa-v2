import { describe, expect, it } from 'vitest';
import { comKpis } from '../domain/kpis';
import { demoAjustarCampanha, demoCampanhas, demoContas, demoProjeto, demoResumo, demoSalvarFase } from './demo';

describe('modo de demonstração do Tráfego (dados fictícios)', () => {
  it('projetos: os 4 da semente real + 2 externos marcados como Exemplo', () => {
    const r = demoResumo();
    expect(r.map((l) => l.sigla)).toEqual(['PB26', 'HT33', 'SEMSET26', 'BF26', 'DEXA26', 'AEXA26']);
    expect(r.filter((l) => l.tipo === 'externo').every((l) => l.nome.includes('Exemplo'))).toBe(true);
  });
  it('contas e campanhas são fictícias (Conta Exemplo, descrição EXEMPLO)', () => {
    expect(demoContas().every((c) => c.nome.includes('Exemplo'))).toBe(true);
    expect(demoCampanhas(null, false, false).every((c) => /exemplo/i.test(c.nome))).toBe(true);
  });
  it('KPIs do demo seguem o domínio; projeto sem campanha fica sem dado', () => {
    for (const l of demoResumo()) expect(comKpis(l)).toEqual(l);
    const sem = demoResumo().find((l) => l.sigla === 'SEMSET26')!;
    expect([sem.investido, sem.pct_verba, sem.ctr]).toEqual([null, null, null]);
    expect(demoResumo().find((l) => l.sigla === 'PB26')!.investido).toBeGreaterThan(0);
  });
  it('fora do padrão e sem projeto aparecem; fase só do projeto da campanha', () => {
    expect(demoCampanhas(null, false, true).length).toBeGreaterThan(0);
    expect(demoCampanhas(null, true, false).map((c) => c.id)).toEqual([7, 8]);
    expect(demoAjustarCampanha({ id: 4, projeto_id: null, fase_id: 1 }).ok).toBe(false);
    expect(demoSalvarFase({ projeto_id: 1, fase: 'captacao', verba: '1' }).ok).toBe(false);
    expect(demoProjeto(1)!.fases.map((f) => f.fase)).toEqual(['aquecimento', 'captacao', 'lembrete']);
  });
});
