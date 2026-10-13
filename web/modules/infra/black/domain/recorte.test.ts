import { describe, expect, it } from 'vitest';
import { diaDe, diasDoPeriodo, escreverRecorte, lerRecorte, periodoDe, RECORTE_PADRAO, segundaDaSemana } from './recorte';

const CONFIG = {
  inicio: '2026-10-04',
  semanas: [
    { rotulo: 'S1', de: '2026-10-26', ate: '2026-11-01' },
    { rotulo: 'S2', de: '2026-11-02', ate: '2026-11-03' },
  ],
};
const AGORA = new Date('2026-11-03T18:00:00-03:00');

describe('lerRecorte', () => {
  it('sem parâmetro = padrão', () => {
    expect(lerRecorte(new URLSearchParams())).toEqual(RECORTE_PADRAO);
  });
  it('valor inválido cai no padrão; id com caractere estranho é descartado', () => {
    const r = lerRecorte({ funil: 'x', periodo: '99d', canal: 'tiktok', aba: 'nada', cp: 'a b', cr: 'ad_01' });
    expect(r.funil).toBe('todos'); expect(r.periodo).toBe('desde-inicio'); expect(r.canal).toBe('todos'); expect(r.aba).toBe('visao');
    expect(r.criativos).toEqual({ anuncio: 'ad_01' });
  });
  it('ida e volta pela URL', () => {
    const r = lerRecorte({ funil: 'iscas', periodo: '7d', canal: 'meta', aba: 'criativos', cp: 'cp_1', cj: 'cj_2', cr: 'ad_3', pg: 'pg_4' });
    expect(lerRecorte(new URLSearchParams(escreverRecorte(r)))).toEqual(r);
  });
  it('preserva o período personalizado na URL e rejeita datas inválidas', () => {
    const r = lerRecorte(new URLSearchParams('periodo=personalizado&de=2026-10-05&ate=2026-10-10'));
    expect(r.periodo).toBe('personalizado');
    expect(r.periodoPersonalizado).toEqual({ de: '2026-10-05', ate: '2026-10-10' });
    expect(lerRecorte(new URLSearchParams(escreverRecorte(r)))).toEqual(r);
    expect(lerRecorte({ periodo: 'personalizado', de: '2026-02-30', ate: '2026-10-10' }).periodo).toBe('desde-inicio');
    expect(lerRecorte({ periodo: 'personalizado', de: '2026-10-10', ate: '2026-10-05' }).periodo).toBe('desde-inicio');
  });
  it('preserva parâmetro alheio (relogio) e array do Next', () => {
    const q = escreverRecorte(RECORTE_PADRAO, new URLSearchParams('relogio=2026-10-20&funil=c1'));
    expect(q).toBe('funil=todos&periodo=desde-inicio&canal=todos&aba=visao&relogio=2026-10-20');
    expect(lerRecorte({ funil: ['c3', 'c1'] }).funil).toBe('c3');
  });
});

describe('periodoDe', () => {
  it('hoje, 7 dias, desde o início', () => {
    expect(periodoDe('hoje', AGORA, CONFIG)).toEqual({ de: '2026-11-03', ate: '2026-11-03' });
    expect(periodoDe('7d', AGORA, CONFIG)).toEqual({ de: '2026-10-28', ate: '2026-11-03' });
    expect(periodoDe('desde-inicio', AGORA, CONFIG)).toEqual({ de: '2026-10-04', ate: '2026-11-03' });
  });
  it('aplica período personalizado inclusive e limita ao projeto e a hoje', () => {
    expect(periodoDe('personalizado', AGORA, CONFIG, { de: '2026-10-05', ate: '2026-10-10' }))
      .toEqual({ de: '2026-10-05', ate: '2026-10-10' });
    expect(periodoDe('personalizado', AGORA, CONFIG, { de: '2026-10-01', ate: '2026-11-10' }))
      .toEqual({ de: '2026-10-04', ate: '2026-11-03' });
  });
  it('semana do ciclo pela config', () => {
    expect(periodoDe('semana', new Date('2026-10-29T12:00:00-03:00'), CONFIG)).toEqual({ de: '2026-10-26', ate: '2026-10-29' });
  });
  it('7 dias não passa do início; relógio depois do fim prende no fim', () => {
    expect(periodoDe('7d', new Date('2026-10-06T12:00:00-03:00'), CONFIG)).toEqual({ de: '2026-10-04', ate: '2026-10-06' });
    expect(periodoDe('hoje', new Date('2026-12-01T12:00:00-03:00'), CONFIG)).toEqual({ de: '2026-11-03', ate: '2026-11-03' });
  });
  it('fuso de São Paulo: 01h UTC ainda é o dia anterior', () => {
    expect(periodoDe('hoje', new Date('2026-10-21T01:00:00Z'), CONFIG)).toEqual({ de: '2026-10-20', ate: '2026-10-20' });
  });
  it('diaDe bate com o fuso de São Paulo', () => {
    expect(diaDe('2026-10-21T01:00:00Z')).toBe('2026-10-20');
    expect(diaDe('2026-10-21T03:00:00Z')).toBe('2026-10-21');
    expect(diaDe('2026-10-20T23:59:59-03:00')).toBe('2026-10-20');
  });
  it('segunda da semana e lista de dias', () => {
    expect(segundaDaSemana('2026-11-01')).toBe('2026-10-26');
    expect(segundaDaSemana('2026-10-26')).toBe('2026-10-26');
    expect(diasDoPeriodo({ de: '2026-10-30', ate: '2026-11-02' })).toEqual(['2026-10-30', '2026-10-31', '2026-11-01', '2026-11-02']);
  });
});
