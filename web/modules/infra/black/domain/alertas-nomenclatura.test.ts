import { describe, expect, it } from 'vitest';
import { alertasNomenclatura } from './alertas-nomenclatura';
import type { Campanha, Conjunto, LinhaPerfil, TrafegoBlack } from './tipos';

// Nomes REAIS do guia do Caio (15/10/2026, Projetos/dashboard-black-friday/NOMENCLATURA-META-CAIO.md). `linha`, `no` e
// `iscaBanco` são o que a RPC dados_black_trafego devolve (contrato de 16/10): o alerta lê o banco, não adivinha pelo nome.
const ETQ = 'black-friday-2026-10';
type Cp = Campanha;
const camp = (id: string, nome: string, linha: Cp['linha'], extra: Partial<Cp> = {}): Cp => ({
  id, nome, canal: 'meta', funil: null, fase: null, etapa: null, subtipo: null, conflito: false, linha, ...extra,
});
const conj = (id: string, campanhaId: string, nome: string, extra: Partial<Conjunto> = {}): Conjunto => ({
  id, campanhaId, nome, isca: null, conjuntoC3: null, ...extra,
});
const anun = (id: string, conjuntoId: string, nome: string) => ({
  id, conjuntoId, nome, formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null,
});
const NOME = {
  teaser: `CF | BF26 | ANTECIPAÇÃO | FB | PQ | ABO | ${ETQ}`,
  distribuicao: `CF | BF26 | ANTECIPAÇÃO | FB | PF | ABO | ${ETQ}`,
  manifesto: `CF | BF26 | AQUECIMENTO | FB | PQ | ABO | ${ETQ}`,
  iscas: `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`,
  base: `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`,
  eHoje: 'CF | BF26 | É HOJE | AQUECIMENTO | FB | PQ | ABO | black-friday-UN2026-10',
  fakeLive: 'CF | BF26 | AQUECIMENTO | LIVE FAKE',
  entresafra: `CF | BF26 | C3 | ENTRESAFRA | META | MORNO | ABO | LEAD | ${ETQ}`,
  cpf01: 'BF26 | CPF01 | META | IG | MORNO | ABO | VV ANTIGO | black-friday-2026-10',
};
const trafego: TrafegoBlack = {
  campanhas: [
    camp('teaser', NOME.teaser, 'c1'),
    camp('dist', NOME.distribuicao, 'distribuicao'),
    camp('mani', NOME.manifesto, 'c1'),
    camp('iscas', NOME.iscas, 'c2'),
    camp('base', NOME.base, 'c3'),
    camp('ehoje', NOME.eHoje, 'lembrete'),
    camp('fake', NOME.fakeLive, 'fake_live'),
    camp('entre', NOME.entresafra, 'pre_captacao'),
    camp('cpf', NOME.cpf01, 'pre_captacao'),
    camp('cx', 'Campanha antiga', null),
  ],
  conjuntos: [
    conj('j-teaser', 'teaser', 'C1 | TEASER | LEADS HT', { linha: 'c1', no: 'teaser' }),
    conj('j-teaser-antigo', 'teaser', 'PQ | 00 | LEADS HT', { linha: 'c1', no: 'teaser' }),
    conj('j-reels', 'dist', 'C1 | REELS | ADV+', { linha: 'distribuicao', no: 'reels_pago' }),
    conj('j-mani', 'mani', 'MANIFESTO EP02 | MQL CNHF  2.0', { linha: 'c1', no: 'manifesto' }),
    conj('j-cons', 'iscas', 'VV C1 | CONSULTORIA', { linha: 'consultoria', no: 'consultoria', iscaBanco: 'CONSULTORIA' }),
    conj('j-flux', 'iscas', 'VV C1 | FLUXOGRAMA', { linha: 'iscas', no: 'iscas', iscaBanco: 'FLUXOGRAMA' }),
    conj('j-misto', 'iscas', 'MIX PQ', { linha: 'iscas', no: 'iscas', iscaBanco: null }),
    conj('j-estranho', 'base', 'público sem padrão', { linha: 'c3', no: null }),
  ],
  anuncios: [
    anun('a-teaser', 'j-teaser', 'ADV_BF26_C1_TEASER_A'),
    anun('a-teaser-sem-peca', 'j-teaser', 'ADV_BF26_C1_VIDEO_A'),
    anun('a-reels', 'j-reels', 'Legenda do post do Instagram'),
    anun('a-cons', 'j-cons', 'C2_CONSULTORIA_MORNO_01'),
    anun('a-flux', 'j-flux', 'ADV_BF26_C2-3_FLUXOGRAMA_A'),
    anun('a-flux-sem-isca', 'j-flux', 'ADV_BF26_C2-3_A'),
    anun('a-flux-outra', 'j-flux', 'ADV_BF26_C2-3_CHECKUP_A'),
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

const regrasDe = (alertas: ReturnType<typeof alertasNomenclatura>, tipo: string, nome: string) =>
  alertas.find((x) => x.tipo === tipo && x.nome === nome)?.regras;

describe('alertasNomenclatura', () => {
  it('nomes do guia, lidos pelo banco, não geram alerta de nomenclatura', () => {
    const alertas = alertasNomenclatura(trafego, []);
    for (const nome of [NOME.teaser, NOME.distribuicao, NOME.manifesto, NOME.iscas, NOME.base]) expect(regrasDe(alertas, 'Campanha', nome)).toBeUndefined();
    // Conjuntos novos (C1 | TEASER, C1 | REELS, MANIFESTO EPnn, VV C1 | isca) e o nome antigo ainda válido (PQ | 00).
    for (const nome of ['C1 | TEASER | LEADS HT', 'PQ | 00 | LEADS HT', 'C1 | REELS | ADV+', 'MANIFESTO EP02 | MQL CNHF  2.0', 'VV C1 | CONSULTORIA', 'VV C1 | FLUXOGRAMA']) {
      expect(regrasDe(alertas, 'Conjunto', nome)).toBeUndefined();
    }
    // O anúncio da consultoria e o da isca citam a isca do conjunto; o reel da distribuição leva a legenda do post (R9 não vale).
    for (const nome of ['ADV_BF26_C1_TEASER_A', 'Legenda do post do Instagram', 'C2_CONSULTORIA_MORNO_01', 'ADV_BF26_C2-3_FLUXOGRAMA_A']) {
      expect(regrasDe(alertas, 'Anúncio', nome)).toBeUndefined();
    }
  });

  it('campanhas: a chave, o gestor e a fase são lidos por valor, em qualquer posição', () => {
    const alertas = alertasNomenclatura(trafego, []);
    // R1: a É HOJE saiu com `black-friday-UN2026-10`; a LIVE FAKE não tem chave.
    expect(regrasDe(alertas, 'Campanha', NOME.eHoje)).toEqual(['R1']);
    expect(regrasDe(alertas, 'Campanha', NOME.fakeLive)).toEqual(['R1']);
    // CPF01: não começa por gestor (R3) e não traz fase (R5); é pré-captação reconhecida (sem R6).
    expect(regrasDe(alertas, 'Campanha', NOME.cpf01)).toEqual(['R3', 'R5']);
    // ENTRESAFRA tem a etapa no lugar da fase: R5, e só.
    expect(regrasDe(alertas, 'Campanha', NOME.entresafra)).toEqual(['R5']);
    // Sem classificação do banco: R6 (e as demais, porque o nome não segue o padrão).
    expect(regrasDe(alertas, 'Campanha', 'Campanha antiga')).toEqual(['R1', 'R2', 'R3', 'R4', 'R5', 'R6']);
  });

  it('marca R2 com menos de 3 campos e R7 em campanha em conflito', () => {
    const alertas = alertasNomenclatura({ ...trafego, conjuntos: [], anuncios: [], campanhas: [
      camp('x1', 'CF | BF26', 'c1'),
      camp('x2', `CF | BF26 | CAPTAÇÃO | ISCAS | ${ETQ}`, 'c2', { conflito: true }),
    ] }, []);
    expect(regrasDe(alertas, 'Campanha', 'CF | BF26')).toEqual(['R1', 'R2', 'R5']);
    expect(regrasDe(alertas, 'Campanha', `CF | BF26 | CAPTAÇÃO | ISCAS | ${ETQ}`)).toEqual(['R7']);
  });

  it('conjunto: R8 quando o banco não reconhece o nó e o nome não é do padrão antigo; R12 em isca sem isca', () => {
    const alertas = alertasNomenclatura(trafego, []);
    expect(regrasDe(alertas, 'Conjunto', 'público sem padrão')).toEqual(['R8']);
    expect(regrasDe(alertas, 'Conjunto', 'MIX PQ')).toEqual(['R12']);
  });

  it('anúncio: R9 em teaser sem TEASER, R10 sem isca e R11 com isca diferente da do conjunto', () => {
    const alertas = alertasNomenclatura(trafego, []);
    expect(regrasDe(alertas, 'Anúncio', 'ADV_BF26_C1_VIDEO_A')).toEqual(['R9']);
    expect(regrasDe(alertas, 'Anúncio', 'ADV_BF26_C2-3_A')).toEqual(['R10']);
    expect(regrasDe(alertas, 'Anúncio', 'ADV_BF26_C2-3_CHECKUP_A')).toEqual(['R11']);
  });

  it('sem `linha` no banco (RPC antiga), o fallback legado não inventa R6 para campanha com funil conhecido', () => {
    const alertas = alertasNomenclatura({ ...trafego, conjuntos: [], anuncios: [], campanhas: [
      { id: 'l1', nome: NOME.iscas, canal: 'meta', funil: 'iscas', fase: null, etapa: 'C2', subtipo: 'ISCA', conflito: false },
    ] }, []);
    expect(alertas).toEqual([]);
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
