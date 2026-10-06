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
  it('fora do padrão e sem projeto aparecem; fase fora da lista recusada', () => {
    expect(demoCampanhas(null, false, true).length).toBeGreaterThan(0);
    expect(demoCampanhas(null, true, false).map((c) => c.id)).toEqual([7, 8]);
    expect(demoAjustarCampanha({ id: 4, fase: 'xyz' }).ok).toBe(false);
    expect(demoSalvarFase({ projeto_id: 1, fase: 'captacao', verba: '1' }).ok).toBe(false);
    expect(demoProjeto(1)!.fases.map((f) => f.fase)).toEqual(['aquecimento', 'captacao', 'lembrete']);
  });
  it('fase pelo objetivo, DISTRIBUIÇÃO em "sem fase", correção à mão prevalece', () => {
    const fase = (id: number) => demoCampanhas(null, false, false).find((c) => c.id === id)!.fase;
    expect([fase(1), fase(2), fase(4), fase(5), fase(9)]).toEqual(['captacao', 'aquecimento', 'captacao', 'remarketing', null]);
    expect(demoProjeto(1)!.campanhas_sem_fase).toBe(1);
    expect(demoAjustarCampanha({ id: 9, fase: 'aquecimento' }).ok).toBe(true);
    expect(fase(9)).toBe('aquecimento');
    expect(demoProjeto(1)!.campanhas_sem_fase).toBe(0);
    demoAjustarCampanha({ id: 9, fase: null });
    expect(fase(9)).toBeNull();
  });
  it('vários gestores por projeto; KPIs com cliques no link e page views', () => {
    const pb = demoResumo().find((l) => l.sigla === 'PB26')!;
    expect(pb.gestores).toEqual(['RS', 'CF']);
    expect(pb.cpc).not.toBeNull();
    expect(pb.connect_rate).not.toBeNull();
    expect(demoResumo().find((l) => l.sigla === 'HT33')!.connect_rate).toBeNull();
  });
});
