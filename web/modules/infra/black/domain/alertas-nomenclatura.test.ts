import { describe, expect, it } from 'vitest';
import { alertasNomenclatura } from './alertas-nomenclatura';
import type { LinhaPerfil, TrafegoBlack } from './tipos';

const trafego: TrafegoBlack = {
  campanhas: [
    { id: 'c1', nome: 'CF | BF26 | C1 | LEADS | META | black-friday-2026-10', canal: 'meta', funil: 'c1', fase: null, etapa: 'C1', subtipo: null, conflito: false },
    { id: 'c2', nome: 'CF | BF26 | C2 | ISCA | META | black-friday-2026-10', canal: 'meta', funil: 'iscas', fase: null, etapa: 'C2', subtipo: 'ISCA', conflito: true },
    { id: 'cx', nome: 'Campanha antiga', canal: 'meta', funil: null, fase: null, etapa: null, subtipo: null, conflito: false },
  ],
  conjuntos: [
    { id: 'j1', campanhaId: 'c2', nome: 'MIX PQ | CHECKUP', isca: null, conjuntoC3: null },
    { id: 'j2', campanhaId: 'c2', nome: '00 - legado', isca: null, conjuntoC3: null },
    { id: 'j3', campanhaId: 'c1', nome: '00 - C1 legado', isca: null, conjuntoC3: null },
  ],
  anuncios: [
    { id: 'a1', conjuntoId: 'j1', nome: 'FUTUROMETRO - criativo', formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null },
    { id: 'a2', conjuntoId: 'j3', nome: 'FAKE LIVE', formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null },
  ],
  paginas: [], dias: [], totais: [], coletadoEm: null,
};
const perfil = (props: Partial<LinhaPerfil> = {}): LinhaPerfil => ({
  leadId: 'l1', pessoaId: 'p1', criadoEm: '2026-10-15T10:00:00-03:00', primeiraPorta: true,
  porta: null, funil: null, isca: null, conjuntoC3: null, campanhaId: null, conjuntoId: null, anuncioId: null, paginaId: null,
  origem: null, canal: null, utmSource: null, utmMedium: null, utmCampaign: null, utmContent: null, utmTerm: null,
  profissao: null, profissaoBruta: null, uf: null, ufOrigem: null, listaOrigem: null, temperaturaBase: null,
  jaNaBase: null, entrouGrupoEm: null, teste: false, ...props,
});

describe('alertasNomenclatura', () => {
  it('avalia nomes de campanha, conjunto e anúncio usando os valores da fonte', () => {
    const alertas = alertasNomenclatura(trafego, []);
    expect(alertas.find((x) => x.nome === 'Campanha antiga')?.regras).toContain('R6');
    expect(alertas.find((x) => x.nome === 'Campanha antiga')?.regras).toContain('R1');
    expect(alertas.find((x) => x.nome === '00 - legado')?.regras).toContain('R8');
    expect(alertas.find((x) => x.nome === '00 - legado')?.regras).toContain('R12');
    expect(alertas.find((x) => x.nome === 'FAKE LIVE')?.regras).toContain('R9');
    expect(alertas.find((x) => x.nome === 'FUTUROMETRO - criativo')?.regras).toContain('R11');
  });

  it('aceita o padrão dos gestores (GESTOR | BF26 | ETAPA | ... | etiqueta) sem R2 nem R5', () => {
    const nomes = [
      'CF | BF26 | C1 | AQUECIMENTO | MANIFESTO | META | PQ | ABO | THRUPLAY | black-friday-2026-10',
      'CF | BF26 | C3 | CAPTAÇÃO | META | PQ | ABO | LEAD | black-friday-2026-10',
      'CF | BF26 | C2 | ISCAS | CAPTAÇÃO | META | PQ | ABO | LEAD | black-friday-2026-10',
    ];
    const alertas = alertasNomenclatura({ ...trafego, conjuntos: [], anuncios: [], campanhas: nomes.map((nome, i) => ({
      id: `n${i}`, nome, canal: 'meta', funil: null, fase: null, etapa: 'C1', subtipo: null, conflito: false,
    })) }, []);
    expect(alertas).toEqual([]);
  });

  it('marca R2 com menos de 4 campos e R5 sem etapa no 3º campo', () => {
    const alertas = alertasNomenclatura({ ...trafego, conjuntos: [], anuncios: [], campanhas: [
      { id: 'x1', nome: 'CF | BF26 | black-friday-2026-10', canal: 'meta', funil: null, fase: null, etapa: 'C1', subtipo: null, conflito: false },
      { id: 'x2', nome: 'CF | BF26 | LEADS | C1 | black-friday-2026-10', canal: 'meta', funil: null, fase: null, etapa: 'C1', subtipo: null, conflito: false },
    ] }, []);
    expect(alertas.find((x) => x.nome === 'CF | BF26 | black-friday-2026-10')?.regras).toEqual(['R2', 'R5']);
    expect(alertas.find((x) => x.nome === 'CF | BF26 | LEADS | C1 | black-friday-2026-10')?.regras).toEqual(['R5']);
  });

  it('agrupa UTM fora do padrão e ausente, sem incluir pessoas ou dados pessoais', () => {
    const alertas = alertasNomenclatura({ ...trafego, campanhas: [], conjuntos: [], anuncios: [] }, [
      perfil({ aCorrigir: ['utm_campaign_fora_do_padrao'], utmCampaign: 'campanha-x' }),
      perfil({ leadId: 'l2', pessoaId: 'p2', aCorrigir: ['utm_campaign_fora_do_padrao'], utmCampaign: 'campanha-x' }),
      perfil({ leadId: 'l3', pessoaId: 'p3', aCorrigir: ['sem_utm'] }),
    ]);
    expect(alertas).toEqual([
      { chave: 'UTM:campanha-x', nome: 'campanha-x', tipo: 'UTM', regras: ['U1'], ocorrencias: 2 },
      { chave: 'UTM:Sem UTM', nome: 'Sem UTM', tipo: 'UTM', regras: ['U2'], ocorrencias: 1 },
    ]);
  });
});
