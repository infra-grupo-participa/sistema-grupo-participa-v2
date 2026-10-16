import { beforeEach, describe, expect, it, vi } from 'vitest';

const { rpc, createSignedUrls } = vi.hoisted(() => ({ rpc: vi.fn(), createSignedUrls: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({
  createBrowserSupabase: () => ({ rpc, storage: { from: (bucket: string) => (bucket === 'trafego-miniaturas' ? { createSignedUrls } : {}) } }),
}));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { alinharIds } from '../domain/alinhar';
import { cardMql, cardsGrupo, grupoSemDado, recorteDaTela, recorteGrupoDe, ROTULO_CRUZADO } from '../domain/grupo';
import type { FiltroCriativos } from '../domain/tipos';
import { CHAVE_BLACK } from './fixtures/catalogo';
import { criarFonteFixtures } from './fixtures/fonte-fixtures';
import {
  AVISO_NAO_LIGADA, assinarMiniaturas, caminhosMiniatura, configReal, fonteSupabaseBlack, limparCacheMiniaturas, linkGerenciadorMeta,
  mapearDetalheLive, mapearGrupo, mapearLeads, mapearLives, mapearPerfil, mapearPreviaImportacao, mapearTrafego, MINIATURA_TTL_S,
} from './fonte-supabase';
import { RESPOSTA_GRUPO, RESPOSTA_LEADS, RESPOSTA_PERFIL, RESPOSTA_TRAFEGO } from './respostas-rpc-black';

const P = { de: '2026-10-04', ate: '2026-10-12' };
const semChave = (o: object, k: string) => Object.fromEntries(Object.entries(o).filter(([c]) => c !== k));

describe('mapeadores das RPCs da Black', () => {
  it('tráfego: centavos viram reais, sem etapa = funil null, métrica ausente continua null', () => {
    const { data, semDado } = mapearTrafego(RESPOSTA_TRAFEGO);
    expect(semDado).toBe(false);
    expect(data.campanhas.map((c) => [c.id, c.funil])).toEqual([['101', 'iscas'], ['102', null], ['103', 'c1']]);
    expect(data.dias).toHaveLength(1);
    expect(data.dias[0].gasto).toBeCloseTo(123.45, 6);
    expect(data.dias[0].thruplay).toBeNull();
    expect(data.dias[0].videoP50).toBeNull();
    expect(data.anuncios.find((a) => a.id === '301')?.idExterno).toBe('990001');
    expect(data.anuncioDesde).toBe('2026-10-08');
    expect(data.gastoCampanhas?.find((g) => g.campanhaId === '101')?.gasto).toBeCloseTo(130, 6);
  });
  it('mapeia totais por campanha sem somar alcance nem frequência', () => {
    const { data } = mapearTrafego({ ...RESPOSTA_TRAFEGO, totais: [
      { campanha_id: 103, de: '2026-10-04', ate: '2026-10-13', gasto_centavos: 1511020, impressoes: 921921,
        alcance: 200722, frequencia: 4.593, coletado_em: '2026-10-13T22:15:00Z' },
      { campanha_id: 101, de: '2026-10-10', ate: '2026-10-13', gasto_centavos: null, impressoes: null,
        alcance: null, frequencia: null, coletado_em: '2026-10-13T22:15:00Z' },
    ] });
    expect(data.totais).toEqual([
      { nivel: 'campanha', id: '103', de: '2026-10-04', ate: '2026-10-13', gasto: 15110.2, impressoes: 921921,
        alcance: 200722, frequencia: 4.593, coletadoEm: '2026-10-13T22:15:00Z' },
      { nivel: 'campanha', id: '101', de: '2026-10-10', ate: '2026-10-13', gasto: null, impressoes: null,
        alcance: null, frequencia: null, coletadoEm: '2026-10-13T22:15:00Z' },
    ]);
  });
  it('mapeia primeira observação e prova de coleta por campanha, sem inferir zero no front', () => {
    const { data } = mapearTrafego({ ...RESPOSTA_TRAFEGO, campanhas: [
      { id: 901, nome: 'Campanha nova', plataforma: 'meta', etapa: 'C2', subtipo: null,
        primeira_vista_em: '2026-10-12T22:45:00Z', sem_entrega_comprovada: true,
        coleta: { estado: 'atual', ultima_ok_em: '2026-10-13T23:45:00Z', ultima_falha_em: null, validade_min: 75 } },
    ], dias_campanha: [] });
    expect(data.campanhas[0]).toMatchObject({
      id: '901', primeiraVistaEm: '2026-10-12T22:45:00Z', semEntregaComprovada: true,
      coleta: { estado: 'atual', ultimaOkEm: '2026-10-13T23:45:00Z', validadeMin: 75 },
    });
  });
  it('mapeia gasto diário por campanha para a régua de investimento', () => {
    const { data } = mapearTrafego({ ...RESPOSTA_TRAFEGO, dias_campanha: [
      { campanha_id: 101, dia: '2026-10-12', gasto_centavos: 12345 },
      { campanha_id: 101, dia: '2026-10-13', gasto_centavos: 0 },
    ] });
    expect(data.gastoCampanhasDiario).toEqual([
      { campanhaId: '101', dia: '2026-10-12', gasto: 123.45 },
      { campanhaId: '101', dia: '2026-10-13', gasto: 0 },
    ]);
  });
  it('funil C1 provisório pelo nome: ANTECIPAÇÃO e MANIFESTO sem etapa viram C1; com etapa no nome, o banco manda', () => {
    const camp = (id: string, nome: string, etapa: string | null, subtipo: string | null = null) =>
      ({ id, nome, plataforma: 'meta', status: 'ACTIVE', objetivo: 'VIDEO', conta: 'c', projeto_id: 1, etapa, subtipo, conflito: false });
    const { data } = mapearTrafego({ ...RESPOSTA_TRAFEGO, campanhas: [
      camp('1', 'CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY', null),
      camp('2', 'CF | BF26 | AQUECIMENTO | MANIFESTO | META | PQ | ABO | THRUPLAY', null),
      camp('3', 'BF26 | CPF01 | META | IG | MORNO | ABO | LEAD', null),
      camp('4', 'CF | BF26 | C2 | ANTECIPAÇÃO | ISCA | META', 'C2', 'ISCA'),
      camp('5', 'CF | BF26 | C1 | CORTES | META', 'C1', 'CORTES'),
    ] });
    expect(data.campanhas.map((c) => [c.id, c.funil])).toEqual([['1', 'c1'], ['2', 'c1'], ['3', null], ['4', 'iscas'], ['5', 'c1']]);
    expect(data.campanhas.map((c) => [c.id, c.fase])).toEqual([['1', 'antecipacao'], ['2', 'aquecimento'], ['3', 'captacao'], ['4', 'antecipacao'], ['5', null]]);
  });
  describe('classificação do banco (linha, fase, no, isca) com nomes do guia do Caio', () => {
    const ETQ = 'black-friday-2026-10';
    const camp = (id: string, nome: string, extra: object) =>
      ({ id, nome, plataforma: 'meta', status: 'ACTIVE', objetivo: 'LEAD', conta: 'c', projeto_id: 1, etapa: null, subtipo: null, conflito: false, ...extra });
    const cj = (id: string, campanha_id: string, nome: string, extra: object) =>
      ({ id, campanha_id, nome, status: 'ACTIVE', meta_otimizacao: 'LEAD', ...extra });
    const resposta = (comLinha: boolean) => ({
      ...RESPOSTA_TRAFEGO,
      campanhas: [
        camp('1', `CF | BF26 | CAPTAÇÃO | ISCAS | FB | PQ | ABO | LEAD | ${ETQ}`, comLinha ? { linha: 'c2', fase: 'captacao' } : {}),
        camp('2', `CF | BF26 | CAPTAÇÃO | BASE | FB | PQ | ABO | LEAD | ${ETQ}`, comLinha ? { linha: 'c3', fase: 'captacao' } : {}),
        camp('3', 'BF26 | CPF01 | META | IG | MORNO | ABO | LEAD', comLinha ? { linha: null, fase: null } : {}),
        camp('4', 'CF | BF26 | ENTRESAFRA | META', comLinha ? { linha: 'pre_captacao', fase: 'pre_captacao' } : {}),
      ],
      conjuntos: [
        cj('11', '1', 'VV C1 | CONSULTORIA', comLinha ? { linha: 'consultoria', no: 'consultoria', isca: 'CONSULTORIA' } : {}),
        cj('12', '1', 'VV C1 | FUTUROMETRO', comLinha ? { linha: 'iscas', no: 'iscas', isca: 'FUTUROMETRO' } : {}),
        cj('21', '2', 'C3 | MIX PQ | CONVITE--DIRETO_01', comLinha ? { linha: 'c3', no: 'c3', isca: null } : {}),
        cj('31', '3', 'C1 | TEASER | LEADS HT', comLinha ? { linha: null, no: null, isca: null } : {}),
      ],
      anuncios: [], dias_campanha: [], dias_anuncio: [],
    });

    it('com `linha`: classifica só pelo que o banco devolve (campanha, conjunto, no, isca e fase)', () => {
      const { data } = mapearTrafego(resposta(true));
      expect(data.campanhas.map((c) => [c.id, c.linha, c.fase])).toEqual([
        ['1', 'c2', 'captacao'], ['2', 'c3', 'captacao'], ['3', null, null], ['4', 'pre_captacao', null],
      ]);
      expect(data.campanhas.map((c) => [c.id, c.funil])).toEqual([['1', 'iscas'], ['2', 'c3'], ['3', null], ['4', null]]);
      expect(data.conjuntos.map((j) => [j.id, j.linha, j.no, j.isca])).toEqual([
        ['11', 'consultoria', 'consultoria', null], ['12', 'iscas', 'iscas', 'Futurômetro'],
        ['21', 'c3', 'c3', null], ['31', null, null, null],
      ]);
      expect(data.conjuntos.find((j) => j.id === '11')?.iscaBanco).toBe('CONSULTORIA');
    });
    it('`linha: null` vira "Sem classificação" e nunca cai no legado, mesmo com nome que o legado reconheceria', () => {
      const { data } = mapearTrafego(resposta(true));
      expect(data.campanhas.find((c) => c.id === '3')?.linha).toBeNull();
      expect(data.conjuntos.find((j) => j.id === '31')?.linha).toBeNull();
    });
    it('valor fora do contrato (linha, no) vira null, não é repassado', () => {
      const { data } = mapearTrafego({ ...resposta(true),
        campanhas: [camp('9', 'X', { linha: 'inventada', fase: 'qualquer' })],
        conjuntos: [cj('91', '9', 'Y', { linha: 'inventada', no: 'inventado', isca: 'OUTRA' })],
      });
      expect(data.campanhas[0]).toMatchObject({ linha: null, fase: null });
      expect(data.conjuntos[0]).toMatchObject({ linha: null, no: null, isca: null });
    });
    it('sem a chave `linha` (RPC antiga): `linha` fica undefined e o front usa o legado pelo nome e pela etapa', () => {
      const { data } = mapearTrafego(resposta(false));
      expect(data.campanhas.every((c) => c.linha === undefined)).toBe(true);
      expect(data.conjuntos.every((j) => j.linha === undefined && j.no === undefined)).toBe(true);
      // legado: o último bloco do nome do conjunto ainda dá a isca (só quando a chave não veio)
      expect(data.conjuntos.find((j) => j.id === '12')?.isca).toBe('Futurômetro');
    });
  });
  it('tráfego: link do Gerenciador pela conta da campanha e o id do anúncio; sem id do anúncio = sem link; prévia e miniatura null', () => {
    const { data } = mapearTrafego(RESPOSTA_TRAFEGO);
    const a = data.anuncios.find((x) => x.id === '301'); const b = data.anuncios.find((x) => x.id === '302');
    expect(a?.linkGerenciador).toBe('https://adsmanager.facebook.com/adsmanager/manage/ads?act=1234567890&selected_ad_ids=990001');
    expect(b?.linkGerenciador).toBeNull();
    expect([a?.linkPrevia, a?.miniaturaUrl]).toEqual([null, null]);
    // RPC antiga (sem conta_externa): sem link, nada inventado
    const semConta = mapearTrafego({ ...RESPOSTA_TRAFEGO, campanhas: RESPOSTA_TRAFEGO.campanhas.map((c) => semChave(c, 'conta_externa')) });
    expect(semConta.data.anuncios.find((x) => x.id === '301')?.linkGerenciador).toBeNull();
  });
  it('linkGerenciadorMeta só aceita os dois ids numéricos', () => {
    expect(linkGerenciadorMeta('act_1234567890', '990001')).toBeNull();
    expect(linkGerenciadorMeta('1234567890', '99a')).toBeNull();
    expect(linkGerenciadorMeta('1234567890', '990001&x=1')).toBeNull();
    expect(linkGerenciadorMeta(null, '990001')).toBeNull();
    expect(linkGerenciadorMeta('1', '2')).toBe('https://adsmanager.facebook.com/adsmanager/manage/ads?act=1&selected_ad_ids=2');
  });
  it('caminhosMiniatura: só o formato da coleta (meta/<conta>/<criativo>.<ext>); URL, ../ e vazio ficam fora', () => {
    const m = caminhosMiniatura({ anuncios: [
      { id: '1', miniatura_caminho: 'meta/1570090828117070/1234567890123456.jpg' },
      { id: '2', miniatura_caminho: '../meta/1/2.jpg' },
      { id: '3', miniatura_caminho: 'https://scontent.xx.fbcdn.net/x.jpg' },
      { id: '4', miniatura_caminho: null },
      { id: '5', miniatura_caminho: 'meta/1/2.jpg/../../x.jpg' },
    ] });
    expect([...m]).toEqual([['1', 'meta/1570090828117070/1234567890123456.jpg']]);
    expect(caminhosMiniatura(RESPOSTA_TRAFEGO).get('301')).toBe('meta/1234567890/555001.jpg');
  });
  it('tráfego sem campanhas ou resposta inválida = semDado', () => {
    expect(mapearTrafego({ campanhas: [] }).semDado).toBe(true);
    expect(mapearTrafego(null).semDado).toBe(true);
  });
  it('mapeia cruzamentos de leads por segmento e sobreposições da RPC de grupos', () => {
    const { data } = mapearGrupo({ ...RESPOSTA_GRUPO,
      leads_em_algum_grupo: 9, leads_em_mais_de_um_grupo: 1,
      grupos: RESPOSTA_GRUPO.grupos.map((g, i) => ({ ...g,
        leads_no_grupo: [4, 2, 3][i], leads_do_segmento: [6, 4, 5][i],
        leads_no_grupo_por_classe: { advogado: i === 0 ? 4 : 0, estudante_direito: 0, contador: i === 1 ? 2 : 0, outros: i === 2 ? 3 : 0, sem_profissao: 0 },
      })),
    });
    expect(data.grupos.map((g) => [g.leadsNoGrupo, g.leadsDoSegmento])).toEqual([[4, 6], [2, 4], [3, 5]]);
    expect(data.leadsEmAlgumGrupo).toBe(9);
    expect(data.leadsEmMaisDeUmGrupo).toBe(1);
  });
  it('mapeia a taxa geral de ingresso agregada pelo banco e preserva null com recorte', () => {
    const geral = mapearGrupo({ ...RESPOSTA_GRUPO,
      ingresso_geral: { numeros_unicos_no_grupo: 169, leads_unicos: 259, pct: 65.3 },
    }).data;
    expect(geral.ingressoGeral).toEqual({ numerosUnicosNoGrupo: 169, leadsUnicos: 259, pct: 65.3 });
    const recortado = mapearGrupo({ ...RESPOSTA_GRUPO, recorte: { tipo: 'porta', valor: 'isca' }, ingresso_geral: null }).data;
    expect(recortado.ingressoGeral).toBeNull();
    expect(mapearGrupo(RESPOSTA_GRUPO).data.ingressoGeral).toBeUndefined();
  });
  it('perfil: funil pela porta, ids do Meta à parte, ids internos null, linha sem lead_id fora', () => {
    const { data } = mapearPerfil(RESPOSTA_PERFIL);
    expect(data).toHaveLength(2);
    const [a, b] = data;
    expect([a.funil, b.funil]).toEqual(['c3', 'iscas']);
    expect([a.anuncioMeta, a.anuncioId, a.campanhaId]).toEqual(['990001', null, null]);
    expect([a.origem, b.origem]).toEqual(['pago', null]);
    expect(a.profissaoBruta).toBe('Advogado(a)');
    expect(b.profissao).toBeNull();
    expect(b.mql).toBeNull();
    expect(b.aCorrigir).toEqual(['profissao_vazia', 'utm_campaign_fora_do_padrao']);
    expect(b.pareceTeste).toBe(true);
  });
  it('perfil: descarta a página Respondi da consultoria por decisão do Victor', () => {
    const r = mapearPerfil([
      { lead_id: 'l-black', pessoa_id: 'p1', criado_em: '2026-10-13T10:00:00Z', pagina: 'captacao' },
      { lead_id: 'l-consultoria', pessoa_id: 'p2', criado_em: '2026-10-13T10:00:00Z', pagina: 'consultoria_respondi' },
    ]);
    expect(r.data.map((l) => l.leadId)).toEqual(['l-black']);
  });
  it('leads e grupo', () => {
    expect(mapearLeads(RESPOSTA_LEADS).data[0].leadId).toBe('captacao:1');
    const g = mapearGrupo(RESPOSTA_GRUPO).data;
    expect(g.grupos.map((x) => x.campanha)).toEqual(['BF26 - Live 03/11 - Advogados', 'BF26 - Live 03/11 - Contadores', 'BF26 - Live 03/11 - Outros']);
    expect(g.leads).toMatchObject({ unicos: 159, mql: 106, advogadoMaisEstudante: 79, contador: 27, naoMql: 53, semProfissao: 13 });
    expect(mapearGrupo('x').semDado).toBe(true);
  });
  it('alinharIds casa o anúncio do Meta com o tráfego; sem casamento fica null', () => {
    const t = mapearTrafego(RESPOSTA_TRAFEGO).data;
    const [a, b] = alinharIds(mapearPerfil(RESPOSTA_PERFIL).data, t);
    expect([a.anuncioId, a.conjuntoId, a.campanhaId]).toEqual(['301', '201', '101']);
    expect([b.anuncioId, b.conjuntoId, b.campanhaId]).toEqual([null, null, null]);
  });
  it('config: início, orçamento por fase e live cadastrados; metas de leads e CPL null; chave desconhecida dá erro', () => {
    const c = configReal(CHAVE_BLACK);
    expect(c.semDado).toBe(false);
    expect(c.data.inicio).toBe('2026-10-04');
    expect([c.data.metaLeads, c.data.metaLeadsDia, c.data.cplAlvoMedio]).toEqual([15000, null, 16.7]);
    expect(c.data.reguaCpl).toEqual({ meta: 15, teto: 20 });
    expect(c.data.metas).toEqual({ mql: 0.6, ingressoGrupo: 0.85, conversaoPagina: 0.2, connectRate: 0.85, ctr: 0.02, cpc: 3, cpm: 50 });
    // sem início da captação cadastrado, a meta acumulada do Histórico continua sem dado (não chuta data)
    expect(c.data.inicioCaptacao).toBeNull();
    expect(c.data.liveEm).toBe('2026-11-03T19:30:00-03:00');
    expect(c.data.orcamentoTotal).toBe(428571);
    expect(c.data.reserva).toBe(16496);
    expect(c.data.previstoPorFase).toEqual({
      antecipacao: 17591, distribuicao: 47575, captacao: 220000, aquecimento: 26909, remarketing: 30000, live_carrinho: 70000,
    });
    // as 6 fases + a reserva fecham o total da tabela
    expect(Object.values(c.data.previstoPorFase).reduce<number>((s, v) => s + (v ?? 0), 0) + (c.data.reserva ?? 0)).toBe(428571);
    expect(configReal('outra').erro).not.toBeNull();
  });
});

describe('cards de MQL e de grupo', () => {
  const g = mapearGrupo(RESPOSTA_GRUPO).data;
  it('MQL = mql ÷ únicos', () => {
    const c = cardMql(g);
    expect(c.total).toBe(106);
    expect(c.taxa.valor).toBeCloseTo(106 / 159, 9);
  });
  it('grupo sem recorte: zero medido é zero; denominador zero ou null = Sem dado', () => {
    const c = cardsGrupo(g);
    expect(c.cruzado).toBe(false);
    expect(c.geral.valor).toBe(0);
    expect(c.linhas.map((l) => l.taxa.den)).toEqual([79, 27, 53]);
    const semDen = cardsGrupo({ ...g, leads: { ...g.leads, mql: 0, contador: null } });
    expect(semDen.geral.valor).toBeNull();
    expect(semDen.linhas[1].taxa.valor).toBeNull();
    expect(cardsGrupo(grupoSemDado()).geral.valor).toBeNull();
  });
  it('segmento ausente ou duplicado = Sem dado com nota', () => {
    const ausente = cardsGrupo({ ...g, grupos: g.grupos.filter((x) => x.segmento !== 'contador') });
    expect(ausente.linhas[1].taxa.valor).toBeNull();
    expect(ausente.linhas[1].taxa.nota).toMatch(/Nenhum grupo/);
    const dup = cardsGrupo({ ...g, grupos: [...g.grupos, { ...g.grupos[0], campanha: 'outro' }] });
    expect(dup.linhas[0].taxa.valor).toBeNull();
  });
  it('com recorte, numerador cruzado e rótulo cruzado', () => {
    const c = cardsGrupo({ ...g, recorte: { tipo: 'porta', valor: 'consultoria' }, unicosCruzadosMql: 3 });
    expect(c.cruzado).toBe(true);
    expect(c.geral.num).toBe(3);
    expect(c.geral.nota).toContain(ROTULO_CRUZADO);
  });
  it('recorteGrupoDe: canal sem número, C1 sem número, funil vira porta, anúncio vence', () => {
    expect(recorteGrupoDe({ funil: 'todos', canal: 'meta' }).ok).toBe(false);
    expect(recorteGrupoDe({ funil: 'c1', canal: 'todos' }).ok).toBe(false);
    expect(recorteGrupoDe({ funil: 'todos', canal: 'todos' })).toEqual({ ok: true, recorte: null });
    expect(recorteGrupoDe({ funil: 'consultoria', canal: 'todos' })).toEqual({ ok: true, recorte: { tipo: 'porta', valor: 'consultoria' } });
    expect(recorteGrupoDe({ funil: 'iscas', canal: 'todos', anuncioMeta: '990001', campanhaMeta: '880001' }))
      .toEqual({ ok: true, recorte: { tipo: 'anuncio', valor: '990001' } });
  });
  it('recorteDaTela: item de Criativos vira o id do Meta; sem id = motivo, nunca o funil no lugar', () => {
    const t = {
      campanhas: [
        { id: '101', nome: 'CAMP A', idExterno: '880001' },
        { id: '102', nome: 'CAMP B', idExterno: null },
      ],
      conjuntos: [
        { id: '201', campanhaId: '101', nome: 'CONJ A', idExterno: '770001' },
        { id: '202', campanhaId: '102', nome: 'CONJ B' },
      ],
      anuncios: [
        { id: '301', nome: 'AD 01', idExterno: '990001' },
        { id: '302', nome: 'AD 02', idExterno: null },
      ],
      paginas: [
        { id: 'p1', rotulo: 'Isca X', isca: 'checklist', porta: 'isca' },
        { id: 'p2', rotulo: 'Consultoria', isca: null, porta: 'consultoria' },
        { id: 'p3', rotulo: 'Sem porta', isca: null, porta: null },
      ],
    } as unknown as Parameters<typeof recorteDaTela>[1];
    const r = (criativos: FiltroCriativos, funil: 'todos' | 'consultoria' = 'todos', canal: 'todos' | 'meta' = 'todos') =>
      recorteDaTela({ funil, canal, criativos }, t);

    expect(r({ anuncio: '301' })).toEqual({ ok: true, recorte: { tipo: 'anuncio', valor: '990001' }, descricao: 'Anúncio: AD 01' });
    expect(r({ anuncio: '302' }).ok).toBe(false);
    expect(r({ conjunto: '201' })).toEqual({ ok: true, recorte: { tipo: 'conjunto', valor: '770001' }, descricao: 'Conjunto: CONJ A' });
    const semConj = r({ conjunto: '202' });
    expect(semConj.ok).toBe(false);
    if (!semConj.ok) expect(semConj.motivo).toContain('conjunto_externa');
    expect(r({ campanha: '101' })).toEqual({ ok: true, recorte: { tipo: 'campanha', valor: '880001' }, descricao: 'Campanha: CAMP A' });
    const semCamp = r({ campanha: '102' }, 'consultoria');
    expect(semCamp.ok).toBe(false);
    if (!semCamp.ok) expect(semCamp.motivo).toContain('campanha_externa');
    expect(r({ anuncio: '301', campanha: '102' })).toMatchObject({ ok: true, recorte: { tipo: 'anuncio' } });
    expect(r({ pagina: 'p1' })).toEqual({ ok: true, recorte: { tipo: 'isca', valor: 'checklist' }, descricao: 'Página: Isca X' });
    expect(r({ pagina: 'p2' })).toEqual({ ok: true, recorte: { tipo: 'porta', valor: 'consultoria' }, descricao: 'Página: Consultoria' });
    expect(r({ pagina: 'p3' }).ok).toBe(false);
    expect(r({ anuncio: '999' }).ok).toBe(false);
    expect(r({ anuncio: '301' }, 'todos', 'meta').ok).toBe(false);
    expect(r({}, 'consultoria')).toEqual({ ok: true, recorte: { tipo: 'porta', valor: 'consultoria' }, descricao: expect.stringMatching(/^Funil: /) });
    expect(r({})).toEqual({ ok: true, recorte: null });
    const aguardando = recorteDaTela({ funil: 'todos', canal: 'todos', criativos: { anuncio: '301' } }, null);
    expect(aguardando.ok).toBe(false);
    if (!aguardando.ok) expect(aguardando.motivo).toContain('Aguardando');
  });
  it('tráfego: campanha_externa e conjunto_externa viram idExterno; ausente = null', () => {
    const resp = structuredClone(RESPOSTA_TRAFEGO) as Record<string, unknown>;
    const camps = resp.campanhas as Record<string, unknown>[];
    const conjs = resp.conjuntos as Record<string, unknown>[];
    camps[0].campanha_externa = '880001';
    conjs[0].conjunto_externa = '770001';
    const { data } = mapearTrafego(resp);
    expect(data.campanhas[0].idExterno).toBe('880001');
    expect(data.campanhas[1].idExterno ?? null).toBeNull();
    expect(data.conjuntos[0].idExterno).toBe('770001');
  });
});

describe('fonte real (Supabase simulado)', () => {
  beforeEach(() => { rpc.mockReset(); createSignedUrls.mockReset(); limparCacheMiniaturas(); });

  const URL_ASSINADA = 'https://projeto.supabase.co/storage/v1/object/sign/trafego-miniaturas/meta/1234567890/555001.jpg?token=t';
  it('tráfego: miniatura vira URL assinada (lote, 900 s) só no anúncio que tem caminho; a próxima leitura usa o cache', async () => {
    rpc.mockResolvedValue({ data: RESPOSTA_TRAFEGO, error: null });
    createSignedUrls.mockResolvedValue({ data: [{ path: 'meta/1234567890/555001.jpg', signedUrl: URL_ASSINADA, error: null }], error: null });
    const t = await fonteSupabaseBlack.trafego(CHAVE_BLACK, P);
    expect(createSignedUrls).toHaveBeenCalledWith(['meta/1234567890/555001.jpg'], MINIATURA_TTL_S);
    expect(t.erro).toBeNull();
    expect(t.data.anuncios.find((a) => a.id === '301')?.miniaturaUrl).toBe(URL_ASSINADA);
    expect(t.data.anuncios.find((a) => a.id === '302')?.miniaturaUrl).toBeNull();
    await fonteSupabaseBlack.trafego(CHAVE_BLACK, P);
    expect(createSignedUrls).toHaveBeenCalledTimes(1);
  });
  it('miniatura: renova perto de vencer; sem acesso ou falha = fictícia (null), sem erro na tela, e tenta de novo depois', async () => {
    createSignedUrls.mockResolvedValue({ data: [{ path: 'meta/1/2.jpg', signedUrl: URL_ASSINADA, error: null }], error: null });
    const t0 = 1_000_000;
    await assinarMiniaturas(['meta/1/2.jpg'], t0);
    await assinarMiniaturas(['meta/1/2.jpg'], t0 + 300_000);
    expect(createSignedUrls).toHaveBeenCalledTimes(1);
    await assinarMiniaturas(['meta/1/2.jpg'], t0 + 600_000);
    expect(createSignedUrls).toHaveBeenCalledTimes(2);

    limparCacheMiniaturas(); createSignedUrls.mockReset();
    createSignedUrls.mockResolvedValue({ data: [{ path: 'meta/1/2.jpg', signedUrl: null, error: 'Either the object does not exist or you do not have access to it' }], error: null });
    expect((await assinarMiniaturas(['meta/1/2.jpg'], t0)).size).toBe(0);
    await assinarMiniaturas(['meta/1/2.jpg'], t0 + 1);
    expect(createSignedUrls).toHaveBeenCalledTimes(2);

    rpc.mockResolvedValue({ data: RESPOSTA_TRAFEGO, error: null });
    createSignedUrls.mockResolvedValue({ data: null, error: { message: 'x' } });
    const t = await fonteSupabaseBlack.trafego(CHAVE_BLACK, P);
    expect([t.erro, t.data.anuncios.find((a) => a.id === '301')?.miniaturaUrl]).toEqual([null, null]);
    createSignedUrls.mockRejectedValue(new Error('rede'));
    expect((await fonteSupabaseBlack.trafego(CHAVE_BLACK, P)).erro).toBeNull();
  });
  it('tráfego sem caminho de miniatura (RPC antiga) não chama o Storage', async () => {
    rpc.mockResolvedValue({ data: { ...RESPOSTA_TRAFEGO, anuncios: RESPOSTA_TRAFEGO.anuncios.map((a) => semChave(a, 'miniatura_caminho')) }, error: null });
    const t = await fonteSupabaseBlack.trafego(CHAVE_BLACK, P);
    expect(createSignedUrls).not.toHaveBeenCalled();
    expect(t.data.anuncios.every((a) => a.miniaturaUrl === null)).toBe(true);
  });

  it('função inexistente (PGRST202 e 42883) = semDado com aviso, sem erro', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: 'PGRST202' } });
    const t = await fonteSupabaseBlack.trafego(CHAVE_BLACK, P);
    expect([t.semDado, t.erro, t.aviso]).toEqual([true, null, AVISO_NAO_LIGADA]);
    expect(t.data.dias).toEqual([]);
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42883' } });
    const g = await fonteSupabaseBlack.grupo(CHAVE_BLACK, P, null);
    expect([g.semDado, g.erro]).toEqual([true, null]);
    expect(g.data.leads.mql).toBeNull();
  });
  it('sem permissão (42501) é erro; falha de rede é erro', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    const r = await fonteSupabaseBlack.perfil(CHAVE_BLACK, P);
    expect(r.semDado).toBe(true);
    expect(r.erro).toMatch(/permissão/);
    rpc.mockRejectedValueOnce(new Error('rede'));
    expect((await fonteSupabaseBlack.perfil(CHAVE_BLACK, P)).erro).not.toBeNull();
  });
  it('42501 em dados_black_leads pede contato.ver e deixa o erro geral nos outros blocos', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    const leads = await fonteSupabaseBlack.leads(CHAVE_BLACK, ['lead-de-teste']);
    expect(leads.erro).toBe('Você não tem permissão para ver os contatos dos leads. Peça acesso ao Victor.');
    expect(leads.semDado).toBe(true);
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    const perfil = await fonteSupabaseBlack.perfil(CHAVE_BLACK, P);
    expect(perfil.erro).toBe('Sem permissão para ler este dashboard.');
  });
  it('argumentos: incluir_teste, p_recorte null e com recorte, leads em até 500', async () => {
    rpc.mockResolvedValue({ data: [], error: null });
    await fonteSupabaseBlack.perfil(CHAVE_BLACK, P, { incluirTeste: true });
    expect(rpc).toHaveBeenLastCalledWith('dados_black_perfil', { p_chave: CHAVE_BLACK, p_de: P.de, p_ate: P.ate, p_incluir_teste: true });
    rpc.mockResolvedValue({ data: RESPOSTA_GRUPO, error: null });
    await fonteSupabaseBlack.grupo(CHAVE_BLACK, P, null);
    expect(rpc).toHaveBeenLastCalledWith('dados_black_grupo', { p_chave: CHAVE_BLACK, p_de: P.de, p_ate: P.ate, p_incluir_teste: false, p_recorte: null });
    await fonteSupabaseBlack.grupo(CHAVE_BLACK, P, { tipo: 'porta', valor: 'consultoria' });
    expect(rpc).toHaveBeenLastCalledWith('dados_black_grupo', expect.objectContaining({ p_recorte: { tipo: 'porta', valor: 'consultoria' } }));
    rpc.mockClear();
    expect((await fonteSupabaseBlack.leads(CHAVE_BLACK, [])).data).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
    rpc.mockResolvedValue({ data: [], error: null });
    await fonteSupabaseBlack.leads(CHAVE_BLACK, Array.from({ length: 600 }, (_, i) => `captacao:${i}`));
    expect((rpc.mock.calls[0][1] as { p_lead_ids: string[] }).p_lead_ids).toHaveLength(500);
  });
  it('marcar teste: número confirmado = ok; erro traduzido; resposta sem número = erro', async () => {
    const lead = { leadId: 'captacao:1', nome: null, email: 'ficticia@exemplo.invalid', telefone: '5500000000000' };
    rpc.mockResolvedValueOnce({ data: 1, error: null });
    expect(await fonteSupabaseBlack.marcarTeste(CHAVE_BLACK, lead)).toEqual({ data: 1, erro: null });
    expect(rpc).toHaveBeenLastCalledWith('dados_marcar_teste', { p_chave: CHAVE_BLACK, p_email: lead.email, p_telefone: lead.telefone, p_motivo: 'teste' });
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    expect((await fonteSupabaseBlack.desmarcarTeste(CHAVE_BLACK, lead)).erro).toMatch(/permissão/);
    rpc.mockResolvedValueOnce({ data: null, error: null });
    expect((await fonteSupabaseBlack.marcarTeste(CHAVE_BLACK, lead)).erro).not.toBeNull();
  });
  it('mensageria e marcos: sem fonte no banco = Sem dado, sem chamar a rede', async () => {
    const [m, k] = await Promise.all([fonteSupabaseBlack.mensageria(CHAVE_BLACK, P), fonteSupabaseBlack.marcos(CHAVE_BLACK)]);
    expect([m.semDado, k.semDado]).toEqual([true, true]);
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('marcar teste no demo', () => {
  it('marcado some do perfil e do grupo; volta com incluirTeste; desmarcar restaura', async () => {
    const f = criarFonteFixtures();
    const p = { de: '2026-10-12', ate: '2026-11-03' };
    const antes = (await f.perfil(CHAVE_BLACK, p)).data;
    const alvo = antes[0];
    const mesmaPessoa = antes.filter((l) => l.pessoaId === alvo.pessoaId).length;
    const unicosAntes = (await f.grupo(CHAVE_BLACK, p, null)).data.leads.unicos;
    const lead = { leadId: alvo.leadId, nome: null, email: null, telefone: null };
    expect((await f.marcarTeste(CHAVE_BLACK, lead)).data).toBe(1);
    expect((await f.marcarTeste(CHAVE_BLACK, lead)).data).toBe(0);
    expect((await f.perfil(CHAVE_BLACK, p)).data).toHaveLength(antes.length - mesmaPessoa);
    expect((await f.perfil(CHAVE_BLACK, p, { incluirTeste: true })).data.filter((l) => l.teste)).toHaveLength(mesmaPessoa);
    expect((await f.grupo(CHAVE_BLACK, p, null)).data.leads.unicos).toBe((unicosAntes ?? 0) - 1);
    expect((await f.desmarcarTeste(CHAVE_BLACK, lead)).data).toBe(1);
    expect((await f.perfil(CHAVE_BLACK, p)).data).toHaveLength(antes.length);
  });
});

describe('aba Lives: mapeadores das RPCs', () => {
  const live = {
    video_id: 'ZZdemo00001', tipo: 'consultoria', data_prevista: '2026-10-06T22:30:00+00:00', titulo: 'ZZ Live FICTÍCIA 1', miniatura: 'https://i.ytimg.com/vi/ZZdemo00001/mqdefault.jpg',
    situacao: 'realizada', agendada_em: null, inicio: '2026-10-06T22:30:00+00:00', fim: null, duracao_seg: 5687, views: 1200, likes: null, comentarios: 14,
    coletado_em: '2026-10-07T01:00:00+00:00', espectadores_agora: null, tem_studio: true, pico: 363, pico_seg: 4080, sala_cheia_seg: 1500, ultimo_espectadores: 302,
    chat_total: 0, reacoes_total: null, chat_guardado: 25,
  };

  it('lives: mapeia os campos, nulo continua nulo (nunca zero) e zero medido continua zero', () => {
    const { data, semDado } = mapearLives({ lives: [live] });
    expect(semDado).toBe(false);
    expect(data[0]).toMatchObject({ videoId: 'ZZdemo00001', tipo: 'consultoria', situacao: 'realizada', pico: 363, picoSeg: 4080, likes: null, reacoesTotal: null, chatTotal: 0, temStudio: true, chatGuardado: 25 });
    expect(data[0].espectadoresAgora).toBeNull();
  });

  it('lives: miniatura fora do YouTube é descartada; tipo, situação e id inválidos tiram a linha; lista vazia ou resposta inválida = semDado', () => {
    const { data } = mapearLives({ lives: [{ ...live, miniatura: 'https://exemplo.test/x.jpg' }, { ...live, video_id: 'curto' }, { ...live, tipo: 'outro' }, { ...live, situacao: 'quase' }, { ...live, data_prevista: null }] });
    expect(data).toHaveLength(1);
    expect(data[0].miniatura).toBeNull();
    expect(mapearLives({ lives: [] })).toEqual({ data: [], semDado: true });
    expect(mapearLives(null).semDado).toBe(true);
    expect(mapearLives('lixo').semDado).toBe(true);
  });

  it('detalhe: minutos, chat, comentários e fotos; chat sem texto e minuto sem seg ficam fora; o nome do autor não entra na tela (nem se a RPC ainda o mandar)', () => {
    const { data, semDado } = mapearDetalheLive({
      minutos: [{ seg: 0, espectadores: 12, chat: 0, reacoes: null, origem: 'studio' }, { seg: null, espectadores: 1 }, { seg: 60, espectadores: null, chat: 3, reacoes: 1, origem: 'x' }],
      chat: [{ seg: 5, publicado_em: null, autor: 'Autor Fictício', texto: 'oi' }, { seg: 6, texto: '' }],
      comentarios: [{ publicado_em: '2026-10-07T00:00:00+00:00', autor: 'Outro Fictício', texto: 'ótima', curtidas: 2, respostas: 0 }],
      fotos: [{ coletado_em: '2026-10-07T01:00:00+00:00', views: 10, likes: null, comentarios: 1 }, { views: 1 }],
    });
    expect(semDado).toBe(false);
    expect(data.minutos).toEqual([
      { seg: 0, espectadores: 12, chat: 0, reacoes: null, origem: 'studio' },
      { seg: 60, espectadores: null, chat: 3, reacoes: 1, origem: null },
    ]);
    expect(data.chat).toEqual([{ seg: 5, publicadoEm: null, texto: 'oi' }]);
    expect(data.comentarios[0]).toEqual({ publicadoEm: '2026-10-07T00:00:00+00:00', texto: 'ótima', curtidas: 2, respostas: 0 });
    expect(JSON.stringify(data)).not.toContain('Fictício');
    expect(data.fotos).toHaveLength(1);
    expect(mapearDetalheLive({ minutos: [], chat: [], comentarios: [], fotos: [] }).semDado).toBe(true);
    expect(mapearDetalheLive(null).semDado).toBe(true);
  });

  it('prévia da importação: números, gravado só quando vem; resposta inválida = null', () => {
    expect(mapearPreviaImportacao({ linhas: 94, pico: 363, pico_seg: 4080, duracao_seg: 5687 })).toEqual({ linhas: 94, pico: 363, picoSeg: 4080, duracaoSeg: 5687, existentes: null, alteradas: null, gravado: null });
    expect(mapearPreviaImportacao({ linhas: 94, pico: 363, pico_seg: 4080, duracao_seg: 5687, existentes: 94, alteradas: 0, gravado: true })).toMatchObject({ existentes: 94, alteradas: 0, gravado: true });
    expect(mapearPreviaImportacao(null)).toBeNull();
  });
});

describe('aba Lives: ações pela fonte do banco', () => {
  beforeEach(() => { rpc.mockReset(); });

  it('lives lê dados_black_lives com a chave e devolve a lista mapeada', async () => {
    rpc.mockResolvedValue({ data: { lives: [{ video_id: 'ZZdemo00001', tipo: 'produto', data_prevista: '2026-10-08T22:30:00+00:00', situacao: 'em_breve' }] }, error: null });
    const r = await fonteSupabaseBlack.lives(CHAVE_BLACK);
    expect(rpc).toHaveBeenCalledWith('dados_black_lives', { p_chave: CHAVE_BLACK });
    expect(r.erro).toBeNull();
    expect(r.data).toHaveLength(1);
    expect(r.data[0]).toMatchObject({ tipo: 'produto', situacao: 'em_breve', pico: null });
  });

  it('erro do banco vira mensagem em português, sem código técnico, e o dado fica vazio (nunca zero)', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'permission denied' } });
    const r = await fonteSupabaseBlack.cadastrarLive(CHAVE_BLACK, 'ZZdemo00001', 'produto', '2026-10-08T19:30:00-03:00');
    expect(r.data).toBeNull();
    expect(r.erro).toBe('Só quem é master neste dashboard pode fazer isso.');
    expect(r.erro).not.toMatch(/permission|42501/);
  });

  it('cadastrar manda os 4 parâmetros do contrato; id inválido nem chama o banco', async () => {
    rpc.mockResolvedValue({ data: { video_id: 'ZZdemo00001' }, error: null });
    const f = fonteSupabaseBlack;
    await f.cadastrarLive(CHAVE_BLACK, 'ZZdemo00001', 'black', '2026-11-03T20:00:00-03:00');
    expect(rpc).toHaveBeenCalledWith('dados_black_live_cadastrar', { p_chave: CHAVE_BLACK, p_video_id: 'ZZdemo00001', p_tipo: 'black', p_data_prevista: '2026-11-03T20:00:00-03:00' });
    rpc.mockClear();
    const ruim = await f.removerLive(CHAVE_BLACK, 'curto');
    expect(ruim.erro).toMatch(/inválido/);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('importar manda as linhas e p_confirmar; sem confirmar é prévia', async () => {
    rpc.mockResolvedValue({ data: { linhas: 2, pico: 20, pico_seg: 60, duracao_seg: 120 }, error: null });
    const r = await fonteSupabaseBlack.importarLive(CHAVE_BLACK, 'ZZdemo00001', [{ seg: 0, espectadores: 10 }, { seg: 60, espectadores: 20 }], false);
    const args = rpc.mock.calls[0];
    expect(args[0]).toBe('dados_black_live_importar');
    expect(args[1]).toMatchObject({ p_chave: CHAVE_BLACK, p_video_id: 'ZZdemo00001', p_confirmar: false });
    expect(r.data).toMatchObject({ linhas: 2, pico: 20, gravado: null });
  });
});
