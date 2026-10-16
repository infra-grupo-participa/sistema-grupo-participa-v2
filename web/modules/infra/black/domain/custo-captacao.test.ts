import { describe, expect, it } from 'vitest';
import { contaNoInvestimentoCaptacao, investimentoCaptacao } from './custo-captacao';
import type { Campanha, TrafegoBlack } from './tipos';

// Nomes do guia do Caio (15/10/2026); `linha` é o que a RPC dados_black_trafego devolve. A campanha de remarketing da página
// sobe em 16/10: o nome abaixo segue o padrão do guia (CAPTAÇÃO | REMARKETING), o real é conferido no Meta. O canal do `c3`
// é google só para o teste ter as duas plataformas.
const ETQ = 'black-friday-2026-10';
const campanhas: Campanha[] = [
  { id: 'c2', nome: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'iscas', etapa: null, fase: 'captacao', linha: 'c2' },
  { id: 'c3', nome: `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'google', funil: 'c3', etapa: null, fase: 'captacao', linha: 'c3' },
  { id: 'remarketing', nome: `CF | BF26 | CAPTAÇÃO | REMARKETING | FB | PQ | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: null, etapa: null, fase: 'captacao', linha: 'remarketing_pagina' },
  { id: 'c1', nome: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`, canal: 'meta', funil: 'c1', etapa: null, fase: 'antecipacao', linha: 'c1' },
  { id: 'distribuicao', nome: `CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | ${ETQ}`, canal: 'meta', funil: 'c1', etapa: null, fase: 'antecipacao', linha: 'distribuicao' },
  { id: 'lembrete', nome: 'CF | BF26 | É HOJE | AQUECIMENTO | FB | PQ | ABO | black-friday-UN2026-10', canal: 'meta', funil: null, etapa: null, fase: 'aquecimento', linha: 'lembrete' },
  { id: 'fake-live', nome: 'CF | BF26 | AQUECIMENTO | LIVE FAKE', canal: 'meta', funil: null, etapa: null, fase: 'aquecimento', linha: 'fake_live' },
  { id: 'sem-classificacao', nome: 'Campanha antiga', canal: 'meta', funil: null, etapa: null, fase: null, linha: null },
  { id: 'entresafra', nome: `CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | ${ETQ}`, canal: 'meta', funil: 'c3', etapa: 'C3', fase: null, linha: 'pre_captacao' },
  { id: 'cpf01', nome: 'BF26 | CPF01 | META | IG | MORNO | ABO | VV ANTIGO | black-friday-2026-10', canal: 'meta', funil: 'c1', etapa: null, fase: null, linha: 'pre_captacao' },
];

const trafego = (gastoCampanhas: NonNullable<TrafegoBlack['gastoCampanhas']>, campanhaList: Campanha[] = campanhas.slice(0, 2)): TrafegoBlack => ({
  campanhas: campanhaList, conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null, gastoCampanhas,
});

describe('investimento de captação', () => {
  it('soma iscas, C3 e remarketing da página; exclui C1, distribuição, lembrete, fake live, sem classificação e pré-captação', () => {
    const r = investimentoCaptacao(trafego([
      { campanhaId: 'c2', gasto: 125 }, { campanhaId: 'c3', gasto: 75 }, { campanhaId: 'remarketing', gasto: 800 },
      { campanhaId: 'c1', gasto: 7000 }, { campanhaId: 'distribuicao', gasto: 7100 }, { campanhaId: 'lembrete', gasto: 7200 },
      { campanhaId: 'fake-live', gasto: 7300 }, { campanhaId: 'sem-classificacao', gasto: 6000 },
      { campanhaId: 'entresafra', gasto: 50000 }, { campanhaId: 'cpf01', gasto: 3238 },
    ], campanhas), { de: '2026-10-05', ate: '2026-10-10' });

    expect(r).toEqual({
      meta: 925, google: 75, total: 1000,
      metaMedido: 925, googleMedido: 75,
      campanhasMetaMedidas: 2, campanhasGoogleMedidas: 1,
      campanhasMetaTotal: 2, campanhasGoogleTotal: 1,
      campanhasMeta: [campanhas[0].nome, campanhas[2].nome],
      campanhasGoogle: [campanhas[1].nome],
      zerosMeta: [], zerosGoogle: [], semDadoMeta: [], semDadoGoogle: [],
      campanhasRemarketing: [campanhas[2].nome],
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
  it('conta iscas, C3 e remarketing da página; pré-captação fica fora, igual ao card da Visão geral', () => {
    const contam = campanhas.filter(contaNoInvestimentoCaptacao).map((c) => c.id);
    expect(contam).toEqual(['c2', 'c3', 'remarketing']);
  });
});
