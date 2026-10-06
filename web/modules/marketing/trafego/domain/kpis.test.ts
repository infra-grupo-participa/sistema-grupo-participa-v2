import { describe, expect, it } from 'vitest';
import {
  FILTROS_INICIAIS, arredondar, comKpis, connectRate, conversaoPagina, cpc, cpl, cpm, ctr, esperadoAte, filtrar, pctMql, pctVerba, ritmo, situacaoRitmo,
  tipoDaSubarea, totais,
} from './kpis';
import type { LinhaResumo } from './tipos';

// Os números do caso PB26 são os mesmos do ensaio da migration (20261005p_ensaio.sql, passo 6): o banco e o
// TypeScript têm de chegar ao mesmo resultado.
describe('KPIs da Central do Tráfego (mesmas fórmulas de mkt_trafego.resumo)', () => {
  it('% da verba: investido ÷ verba máxima, 1 casa', () => {
    expect(pctVerba(250, 1000)).toBe(25);
    expect(pctVerba(1, 3)).toBe(33.3);
    expect(pctVerba(1500, 1000)).toBe(150);
  });
  it('CPL: investido ÷ leads da base, 2 casas', () => {
    expect(cpl(250, 2)).toBe(125);
    expect(cpl(100, 3)).toBe(33.33);
  });
  it('CPC: investido ÷ cliques no link, 2 casas', () => {
    expect(cpc(250, 350)).toBe(0.71);
    expect(cpc(250, 0)).toBeNull();
  });
  it('connect rate: page views ÷ cliques no link × 100, 1 casa', () => {
    expect(connectRate(175, 350)).toBe(50);
    expect(connectRate(null, 350)).toBeNull();
    expect(connectRate(175, 0)).toBeNull();
  });
  it('conversão da página: leads ÷ page views × 100, 1 casa', () => {
    expect(conversaoPagina(2, 175)).toBe(1.1);
    expect(conversaoPagina(null, 175)).toBeNull();
    expect(conversaoPagina(2, 0)).toBeNull();
  });
  it('CTR: cliques no link ÷ impressões × 100, 2 casas', () => {
    expect(ctr(350, 25000)).toBe(1.4);
    expect(ctr(1, 3)).toBe(33.33);
  });
  it('CPM: investido ÷ impressões × 1000, 2 casas', () => {
    expect(cpm(250, 25000)).toBe(10);
    expect(cpm(30, 7)).toBe(4285.71);
  });
  it('% MQL: MQL ÷ leads × 100, 1 casa', () => {
    expect(pctMql(1, 2)).toBe(50);
    expect(pctMql(2, 3)).toBe(66.7);
  });
  it('ritmo: gasto do dia ÷ verba diária × 100, e "acima" só passando de 100%', () => {
    expect(ritmo(150.5, 100)).toBe(150.5);
    expect(situacaoRitmo(150.5)).toBe('acima');
    expect(situacaoRitmo(100)).toBe('dentro');
    expect(situacaoRitmo(40)).toBe('dentro');
    expect(situacaoRitmo(null)).toBeNull();
  });
  it('sem base para a conta = null (nunca zero inventado)', () => {
    expect(pctVerba(null, 1000)).toBeNull();
    expect(pctVerba(250, null)).toBeNull();
    expect(pctVerba(250, 0)).toBeNull();
    expect(cpl(250, 0)).toBeNull();
    expect(cpl(250, null)).toBeNull();
    expect(ctr(0, 0)).toBeNull();
    expect(cpm(30, 0)).toBeNull();
    expect(pctMql(0, 0)).toBeNull();
    expect(ritmo(10, null)).toBeNull();
  });
  it('arredonda como o Postgres (meio para longe do zero)', () => {
    expect(arredondar(0.125, 2)).toBe(0.13);
    expect(arredondar(2.5, 0)).toBe(3);
    expect(arredondar(1.005, 2)).toBe(1.01);
  });
});

describe('esperado até (ritmo pelas fases)', () => {
  const fases = [
    { verba: 1000, inicio: '2026-10-01', fim: '2026-10-10' }, // 100 por dia
    { verba: 300, inicio: '2026-10-11', fim: '2026-10-13' },  // 100 por dia
  ];
  it('antes de começar = 0; no meio = proporcional aos dias passados (inclusive); depois = tudo', () => {
    expect(esperadoAte(fases, '2026-09-30').valor).toBe(0);
    expect(esperadoAte(fases, '2026-10-01').valor).toBe(100);
    expect(esperadoAte(fases, '2026-10-05').valor).toBe(500);
    expect(esperadoAte(fases, '2026-10-12').valor).toBe(1200);
    expect(esperadoAte(fases, '2026-12-31').valor).toBe(1300);
  });
  it('fase sem período fica fora e é contada; sem fase utilizável = null', () => {
    expect(esperadoAte([...fases, { verba: 50, inicio: null, fim: null }], '2026-12-31')).toEqual({ valor: 1300, semPeriodo: 1 });
    expect(esperadoAte([{ verba: null, inicio: '2026-10-01', fim: '2026-10-02' }], '2026-10-02')).toEqual({ valor: null, semPeriodo: 0 });
    expect(esperadoAte([], '2026-10-02').valor).toBeNull();
  });
  it('fase de um dia só', () => {
    expect(esperadoAte([{ verba: 70, inicio: '2026-10-05', fim: '2026-10-05' }], '2026-10-05').valor).toBe(70);
  });
});

function linha(p: Partial<LinhaResumo>): LinhaResumo {
  return {
    projeto_id: 1, sigla: 'XX26', nome: 'X', subarea: 'interno', tipo: 'interno', projeto_ativo: true, etiqueta_clickup: null,
    inicio: null, fim: null, status: null, status_nome: null, gestores: [], gestores_campanhas: [], receita: null,
    investido: null, por_plataforma: null, moedas: [], verba_maxima: null, verba_diaria: null, verba_fases: 0, fases: 0,
    pct_verba: null, impressoes: null, cliques_link: null, cliques_total: null, leads_plataforma: null, page_views: null,
    leads: null, mql: null, cpl: null, ctr: null, cpc: null, cpm: null, pct_mql: null, connect_rate: null, conversao_pagina: null, gasto_ontem: null, dia_ontem: '2026-10-04',
    ritmo_ontem: null, ultimo_dia: null, meta_leads: null, meta_receita: null, meta_cpl: null, meta_pct_mql: null, obs: null,
    campanhas: 0, campanhas_fora_padrao: 0, ...p,
  };
}

describe('comKpis: a linha inteira, como o banco devolve', () => {
  it('caso PB26 do ensaio', () => {
    const l = comKpis(linha({ investido: 250, verba_maxima: 1000, verba_diaria: 100, impressoes: 25000, cliques_link: 350, cliques_total: 400, page_views: 175, leads: 2, mql: 1, gasto_ontem: 150.5 }));
    expect([l.pct_verba, l.cpl, l.ctr, l.cpc, l.cpm, l.pct_mql, l.connect_rate, l.conversao_pagina, l.ritmo_ontem])
      .toEqual([25, 125, 1.4, 0.71, 10, 50, 50, 1.1, 150.5]);
  });
  it('projeto sem coleta: tudo null, mesmo com verba', () => {
    const l = comKpis(linha({ verba_maxima: 1000, verba_diaria: 100, gasto_ontem: 0 }));
    expect([l.pct_verba, l.cpl, l.ctr, l.cpc, l.cpm, l.pct_mql, l.connect_rate, l.conversao_pagina, l.ritmo_ontem])
      .toEqual([null, null, null, null, null, null, null, null, null]);
  });
});

describe('filtros e totais', () => {
  const ls = [
    linha({ projeto_id: 1, sigla: 'PB26', subarea: 'interno', tipo: 'interno', gestores: ['RS', 'CF'], status: 'ativo', investido: 100, verba_maxima: 1000, ritmo_ontem: 150, campanhas_fora_padrao: 1 }),
    linha({ projeto_id: 2, sigla: 'DIA26', subarea: 'diamante', tipo: 'externo', gestores_campanhas: ['EF'], status: 'pausado', investido: 50 }),
    linha({ projeto_id: 3, sigla: 'AUR26', subarea: 'aurum', tipo: 'externo', gestores: ['CF'], status: null }),
    linha({ projeto_id: 4, sigla: 'OLD25', projeto_ativo: false, status: 'encerrado' }),
  ];
  const siglas = (xs: LinhaResumo[]) => xs.map((x) => x.sigla);
  it('padrão esconde projeto desativado', () => {
    expect(siglas(filtrar(ls, FILTROS_INICIAIS))).toEqual(['PB26', 'DIA26', 'AUR26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, inativos: true }))).toHaveLength(4);
  });
  it('interno/externo, subárea, gestor (um dos vários do projeto, ou de campanha), status e "sem status"', () => {
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, tipo: 'externo' }))).toEqual(['DIA26', 'AUR26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, subarea: 'aurum' }))).toEqual(['AUR26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, gestor: 'EF' }))).toEqual(['DIA26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, gestor: 'RS' }))).toEqual(['PB26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, gestor: 'CF' }))).toEqual(['PB26', 'AUR26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, status: 'pausado' }))).toEqual(['DIA26']);
    expect(siglas(filtrar(ls, { ...FILTROS_INICIAIS, status: 'sem' }))).toEqual(['AUR26']);
  });
  it('totais só somam o que tem dado', () => {
    expect(totais(ls)).toEqual({ investido: 150, verba: 1000, foraPadrao: 1, acimaRitmo: 1 });
    expect(totais([linha({})])).toEqual({ investido: null, verba: null, foraPadrao: 0, acimaRitmo: 0 });
  });
  it('tipo sai da subárea', () => {
    expect(tipoDaSubarea('interno')).toBe('interno');
    expect(tipoDaSubarea('aurum')).toBe('externo');
    expect(tipoDaSubarea('diamante')).toBe('externo');
    expect(tipoDaSubarea(null)).toBeNull();
  });
});
