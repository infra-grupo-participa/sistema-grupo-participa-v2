import { describe, expect, it } from 'vitest';
import { agruparPorDia, alertasDoDia, fracaoDoDia, mapearPlano, pctDaMeta, resumoAjusteDoDia, segmentoDe, segmentosDoPeriodo, toleranciaRitmo, VIGIA_BLACK } from './plano-diario';

const bruto = [
  { dia: '2026-10-17', plataforma: 'meta', camada: 'c3', verba_meta: 10000, verba_real: 4000, leads_meta: 300, leads_real: 100 },
  { dia: '2026-10-17', plataforma: 'meta', camada: 'c2', verba_meta: 2000, verba_real: 0, leads_meta: 50, leads_real: 0 },
  { dia: '2026-10-17', plataforma: 'google', camada: 'c3', verba_meta: 1000, verba_real: null, leads_meta: 20, leads_real: null },
  { dia: '2026-10-17', plataforma: 'meta', camada: null, verba_meta: 0, verba_real: 300, leads_meta: 0, leads_real: 5 },
  { dia: '2026-10-18', plataforma: 'meta', camada: 'c3', verba_meta: 12000, verba_real: null, leads_meta: 320, leads_real: null },
];
// 17/10/2026 às 12h00 em São Paulo (UTC-3)
const meioDia = new Date('2026-10-17T15:00:00Z');

describe('plano diário da Black', () => {
  it('agrupa por dia, soma o total e ordena Meta antes de Google', () => {
    const dias = agruparPorDia(mapearPlano(bruto));
    expect(dias.map((d) => d.dia)).toEqual(['2026-10-17', '2026-10-18']);
    expect(dias[0].total).toEqual({ verbaMeta: 13000, verbaReal: 4300, leadsMeta: 370, leadsReal: 105 });
    expect(dias[0].segmentos.map((s) => s.segmento.rotulo)).toEqual(['Meta C3', 'Meta C2', 'Google C3', 'Meta sem segmento']);
    expect(dias[1].total.verbaReal).toBeNull();
  });
  it('mantém sem dado como null e calcula % da meta', () => {
    expect(pctDaMeta(null, 100)).toBeNull();
    expect(pctDaMeta(50, 0)).toBeNull();
    expect(pctDaMeta(50, 200)).toBe(25);
  });
  it('mede a fração do dia em São Paulo', () => {
    expect(fracaoDoDia('2026-10-16', meioDia)).toBe(1);
    expect(fracaoDoDia('2026-10-18', meioDia)).toBe(0);
    expect(fracaoDoDia('2026-10-17', meioDia)).toBeCloseTo(0.5, 2);
  });
  it('usa os limites da vigia: 25% de tolerância depois das 12h, 40% antes, e parado a partir das 9h', () => {
    const [hoje] = agruparPorDia(mapearPlano(bruto));
    const a = alertasDoDia(hoje, meioDia);
    expect(a.map((x) => [x.segmento.rotulo, x.verbaAtras, x.leadsAtras, x.parado])).toEqual([['Meta C3', false, true, false], ['Meta C2', true, true, true]]);
    expect(a[0].cpl).toBe(40);
    expect(toleranciaRitmo(new Date('2026-10-17T13:00:00Z'))).toBe(VIGIA_BLACK.toleranciaAte12h);
    expect(toleranciaRitmo(meioDia)).toBe(VIGIA_BLACK.toleranciaDepois12h);
    // 8h30: ainda não marca parado
    expect(alertasDoDia(hoje, new Date('2026-10-17T11:30:00Z')).some((x) => x.parado)).toBe(false);
  });
  it('só recomenda acelerar verba com CPL dentro do teto', () => {
    const dentro = agruparPorDia(mapearPlano([{ dia: '2026-10-17', plataforma: 'meta', camada: 'c3', verba_meta: 10000, verba_real: 2000, leads_meta: 300, leads_real: 100 }]))[0];
    const t = resumoAjusteDoDia(dentro, meioDia, null)!;
    expect(t).toContain('dá para acelerar');
    expect(t).toContain('faltam R$');
    expect(t).not.toContain('subir a verba em');
  });
  it('escreve o parágrafo com falta do dia, segmentos, parados, página e Google', () => {
    const [hoje] = agruparPorDia(mapearPlano(bruto));
    const t = resumoAjusteDoDia(hoje, meioDia, 32)!;
    expect(t).toContain('Hoje, às 12:00');
    expect(t).toContain('Meta C2');
    expect(t).toContain('não subir verba enquanto o CPL estiver acima do teto');
    expect(t).toContain('sem imposto do Meta');
    expect(t).toContain('abaixo de 40%');
    expect(t).toContain('Google sem coleta');
    expect(resumoAjusteDoDia(undefined, meioDia, null)).toBeNull();
  });
  it('rotula o teaser histórico e o põe no fim', () => {
    const dias = agruparPorDia(mapearPlano([...bruto, { dia: '2026-10-17', plataforma: 'meta', camada: 'historico', verba_meta: 0, verba_real: 50, leads_meta: 0, leads_real: 0 }]));
    const rotulos = dias[0].segmentos.map((s) => s.segmento.rotulo);
    expect(rotulos).toContain('Meta Teaser (histórico)');
    expect(rotulos.indexOf('Meta Teaser (histórico)')).toBeGreaterThan(rotulos.indexOf('Google C3'));
  });
  it('lista os segmentos do período com cor fixa por camada', () => {
    const segs = segmentosDoPeriodo(agruparPorDia(mapearPlano(bruto)));
    expect(segs[0].chave).toBe('meta:c3');
    expect(segmentoDe('google', 'c3').cor).toBe(segmentoDe('meta', 'c3').cor);
    expect(segmentoDe('google', 'c3').opaco).toBe(true);
  });
});
