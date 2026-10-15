import { describe, expect, it } from 'vitest';
import { contaNoInvestimentoCaptacao, investimentoCaptacao } from './custo-captacao';
import type { Campanha, TrafegoBlack } from './tipos';

const campanhas: Campanha[] = [
  { id: 'c2', nome: 'CF | BF26 | LEADS | C2 | CONSULTORIA', canal: 'meta', funil: 'consultoria', etapa: 'C2', fase: 'captacao' },
  { id: 'c3', nome: 'CF | BF26 | LEAD | C3 | CAPTACAO', canal: 'google', funil: 'c3', etapa: 'C3', fase: 'captacao' },
  { id: 'sem-lead', nome: 'CF | BF26 | C2 | CONSULTORIA', canal: 'meta', funil: 'consultoria', etapa: 'C2', fase: null },
  { id: 'remarketing', nome: 'CF | BF26 | LEAD | C3 | REMARKETING', canal: 'meta', funil: 'c3', etapa: 'C3', fase: 'remarketing' },
  { id: 'c1', nome: 'CF | BF26 | LEAD | C1', canal: 'meta', funil: 'c1', etapa: 'C1', fase: 'distribuicao' },
  { id: 'sem-etapa', nome: 'CF | BF26 | LEAD', canal: 'meta', funil: null, etapa: null, fase: 'captacao' },
  { id: 'entresafra', nome: 'CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD', canal: 'meta', funil: 'c3', etapa: 'C3', fase: 'captacao' },
];

const trafego = (gastoCampanhas: NonNullable<TrafegoBlack['gastoCampanhas']>, campanhaList: Campanha[] = campanhas.slice(0, 2)): TrafegoBlack => ({
  campanhas: campanhaList, conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null, gastoCampanhas,
});

describe('investimento de captação', () => {
  it('soma por etapa C2/C3 mesmo sem LEAD no nome e exclui remarketing/C1/Sem etapa/Entresafra', () => {
    const r = investimentoCaptacao(trafego([
      { campanhaId: 'c2', gasto: 125 }, { campanhaId: 'c3', gasto: 75 },
      { campanhaId: 'sem-lead', gasto: 9000 }, { campanhaId: 'remarketing', gasto: 8000 },
      { campanhaId: 'c1', gasto: 7000 }, { campanhaId: 'sem-etapa', gasto: 6000 },
      { campanhaId: 'entresafra', gasto: 50000 },
    ], campanhas), { de: '2026-10-05', ate: '2026-10-10' });

    expect(r).toEqual({
      meta: 9125, google: 75, total: 9200,
      metaMedido: 9125, googleMedido: 75,
      campanhasMetaMedidas: 2, campanhasGoogleMedidas: 1,
      campanhasMetaTotal: 2, campanhasGoogleTotal: 1,
      campanhasMeta: ['CF | BF26 | C2 | CONSULTORIA', 'CF | BF26 | LEADS | C2 | CONSULTORIA'],
      campanhasGoogle: ['CF | BF26 | LEAD | C3 | CAPTACAO'],
      zerosMeta: [], zerosGoogle: [], semDadoMeta: [], semDadoGoogle: [],
      campanhasRemarketing: ['CF | BF26 | LEAD | C3 | REMARKETING'],
    });
  });

  it('gastos medidos em zero contam como zero real', () => {
    const r = investimentoCaptacao(trafego([{ campanhaId: 'c2', gasto: 0 }, { campanhaId: 'c3', gasto: 0 }]),
      { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.google, r.total]).toEqual([0, 0, 0]);
  });

  it('canal sem campanha entra como zero e permite fechar o total', () => {
    const trafegoSoMeta = trafego([{ campanhaId: 'c2', gasto: 125 }], [campanhas[0]]);
    const r = investimentoCaptacao(trafegoSoMeta, { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.google, r.total]).toEqual([125, 0, 125]);
    expect([r.metaMedido, r.googleMedido, r.campanhasMetaMedidas, r.campanhasMetaTotal, r.campanhasGoogleTotal]).toEqual([125, 0, 1, 1, 0]);
  });

  it('gasto zero com linha medida entra na soma e não vira Sem dado', () => {
    const r = investimentoCaptacao(trafego([{ campanhaId: 'c2', gasto: 0 }, { campanhaId: 'c3', gasto: 75 }]),
      { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.google, r.total]).toEqual([0, 75, 75]);
  });

  it('mantém subtotal de Meta explícito quando falta gasto de uma campanha elegível', () => {
    const base = trafego([{ campanhaId: 'c2', gasto: 125 }]);
    const r = investimentoCaptacao({ ...base, campanhas: [...base.campanhas, { ...campanhas[0], id: 'c2-extra' }] },
      { de: '2026-10-05', ate: '2026-10-10' });
    expect(r.meta).toBeNull();
    expect(r.metaMedido).toBe(125);
    expect([r.campanhasMetaMedidas, r.campanhasMetaTotal]).toEqual([1, 2]);
    expect(r.total).toBeNull();
  });

  it('só considera zero quando a RPC confirma sem entrega para aquela campanha', () => {
    const lista: Campanha[] = [
      { ...campanhas[0], id: 'c2-zero', nome: 'C2 nova', semEntregaComprovada: true, primeiraVistaEm: '2026-10-05T09:00:00Z',
        coleta: { estado: 'atual', ultimaOkEm: '2026-10-10T13:00:00Z', ultimaFalhaEm: null, validadeMin: 75 } },
      { ...campanhas[0], id: 'c2-pendente', nome: 'C2 sem linha', semEntregaComprovada: false, primeiraVistaEm: '2026-10-10T13:00:00Z',
        coleta: { estado: 'atual', ultimaOkEm: '2026-10-10T12:00:00Z', ultimaFalhaEm: null, validadeMin: 75 } },
    ];
    const r = investimentoCaptacao(trafego([], lista.slice(0, 1)), { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.total]).toEqual([0, 0]);
    expect(r.zerosMeta).toEqual([{ nome: 'C2 nova', coletaEm: '2026-10-10T13:00:00Z' }]);
    const parcial = investimentoCaptacao(trafego([], lista), { de: '2026-10-05', ate: '2026-10-10' });
    expect([parcial.meta, parcial.total]).toEqual([null, null]);
    expect(parcial.semDadoMeta).toEqual([{ nome: 'C2 sem linha', motivo: 'coleta atual sem confirmação de ausência de entrega', coletaEm: '2026-10-10T12:00:00Z' }]);
  });

  it('não transforma campanha com falha recente em zero, mesmo se há coleta ok antiga', () => {
    const c = { ...campanhas[0], semEntregaComprovada: false, primeiraVistaEm: '2026-10-05T09:00:00Z',
      coleta: { estado: 'falha_recente' as const, ultimaOkEm: '2026-10-10T13:00:00Z', ultimaFalhaEm: '2026-10-10T14:00:00Z', validadeMin: 75 } };
    const r = investimentoCaptacao(trafego([], [c]), { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.total, r.zerosMeta.length]).toEqual([null, null, 0]);
    expect(r.semDadoMeta[0]?.motivo).toContain('última coleta da conta falhou');
  });
});

describe('regra por campanha usada no Histórico', () => {
  it('conta só C2/C3 fora de remarketing e entresafra, igual ao card da Visão geral', () => {
    const contam = campanhas.filter(contaNoInvestimentoCaptacao).map((c) => c.id);
    expect(contam).toEqual(['c2', 'c3', 'sem-lead']);
  });
});
