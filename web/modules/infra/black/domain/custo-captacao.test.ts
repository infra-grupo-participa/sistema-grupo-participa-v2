import { describe, expect, it } from 'vitest';
import { investimentoCaptacao } from './custo-captacao';
import type { Campanha, TrafegoBlack } from './tipos';

const campanhas: Campanha[] = [
  { id: 'c2', nome: 'CF | BF26 | LEADS | C2 | CONSULTORIA', canal: 'meta', funil: 'consultoria', etapa: 'C2', fase: 'captacao' },
  { id: 'c3', nome: 'CF | BF26 | LEAD | C3 | CAPTACAO', canal: 'google', funil: 'c3', etapa: 'C3', fase: 'captacao' },
  { id: 'sem-lead', nome: 'CF | BF26 | C2 | CONSULTORIA', canal: 'meta', funil: 'consultoria', etapa: 'C2', fase: 'captacao' },
  { id: 'remarketing', nome: 'CF | BF26 | LEAD | C3 | REMARKETING', canal: 'meta', funil: 'c3', etapa: 'C3', fase: 'remarketing' },
  { id: 'c1', nome: 'CF | BF26 | LEAD | C1', canal: 'meta', funil: 'c1', etapa: 'C1', fase: 'distribuicao' },
  { id: 'sem-etapa', nome: 'CF | BF26 | LEAD', canal: 'meta', funil: null, etapa: null, fase: 'captacao' },
];

const trafego = (gastoCampanhas: NonNullable<TrafegoBlack['gastoCampanhas']>): TrafegoBlack => ({
  campanhas, conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null, gastoCampanhas,
});

describe('investimento de captação', () => {
  it('soma apenas nomes com LEAD em C2/C3, separa canais e exclui remarketing/C1/Sem etapa', () => {
    const r = investimentoCaptacao(trafego([
      { campanhaId: 'c2', gasto: 125 }, { campanhaId: 'c3', gasto: 75 },
      { campanhaId: 'sem-lead', gasto: 9000 }, { campanhaId: 'remarketing', gasto: 8000 },
      { campanhaId: 'c1', gasto: 7000 }, { campanhaId: 'sem-etapa', gasto: 6000 },
    ]), { de: '2026-10-05', ate: '2026-10-10' });

    expect(r).toEqual({
      meta: 125, google: 75, total: 200,
      metaMedido: 125, googleMedido: 75,
      campanhasMetaMedidas: 1, campanhasGoogleMedidas: 1,
      campanhasMetaTotal: 1, campanhasGoogleTotal: 1,
      campanhasMeta: ['CF | BF26 | LEADS | C2 | CONSULTORIA'],
      campanhasGoogle: ['CF | BF26 | LEAD | C3 | CAPTACAO'],
      campanhasSemLead: ['CF | BF26 | C2 | CONSULTORIA'],
      campanhasRemarketing: ['CF | BF26 | LEAD | C3 | REMARKETING'],
    });
  });

  it('sem gasto positivo medido mantém os valores como Sem dado', () => {
    const r = investimentoCaptacao(trafego([{ campanhaId: 'c2', gasto: 0 }, { campanhaId: 'c3', gasto: 0 }]),
      { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.google, r.total]).toEqual([null, null, null]);
  });

  it('total fica sem dado se um dos canais não tem fonte, sem tratar o canal ausente como zero', () => {
    const trafegoSoMeta = { ...trafego([{ campanhaId: 'c2', gasto: 125 }]), campanhas: campanhas.filter((c) => c.canal === 'meta') };
    const r = investimentoCaptacao(trafegoSoMeta, { de: '2026-10-05', ate: '2026-10-10' });
    expect([r.meta, r.google, r.total]).toEqual([125, null, null]);
    expect([r.metaMedido, r.googleMedido, r.campanhasMetaMedidas, r.campanhasMetaTotal]).toEqual([125, null, 1, 1]);
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
});
