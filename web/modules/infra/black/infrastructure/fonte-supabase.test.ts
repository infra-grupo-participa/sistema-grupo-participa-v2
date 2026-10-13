import { beforeEach, describe, expect, it, vi } from 'vitest';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/shared/infrastructure/supabase/browser-client', () => ({ createBrowserSupabase: () => ({ rpc }) }));
vi.mock('@/shared/infrastructure/supabase/query-log', () => ({ logQueryError: vi.fn() }));

import { alinharIds } from '../domain/alinhar';
import { cardMql, cardsGrupo, grupoSemDado, recorteGrupoDe, ROTULO_CRUZADO } from '../domain/grupo';
import { CHAVE_BLACK } from './fixtures/catalogo';
import { criarFonteFixtures } from './fixtures/fonte-fixtures';
import {
  AVISO_NAO_LIGADA, configReal, fonteSupabaseBlack, mapearGrupo, mapearLeads, mapearPerfil, mapearTrafego,
} from './fonte-supabase';
import { RESPOSTA_GRUPO, RESPOSTA_LEADS, RESPOSTA_PERFIL, RESPOSTA_TRAFEGO } from './respostas-rpc-black';

const P = { de: '2026-10-04', ate: '2026-10-12' };

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
  it('tráfego sem campanhas ou resposta inválida = semDado', () => {
    expect(mapearTrafego({ campanhas: [] }).semDado).toBe(true);
    expect(mapearTrafego(null).semDado).toBe(true);
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
  it('config: só o início cadastrado; metas null; chave desconhecida dá erro', () => {
    const c = configReal(CHAVE_BLACK);
    expect(c.semDado).toBe(false);
    expect(c.data.inicio).toBe('2026-10-04');
    expect([c.data.metaLeads, c.data.cplAlvoMedio, c.data.orcamentoTotal, c.data.liveEm, c.data.reguaCpl]).toEqual([null, null, null, null, null]);
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
});

describe('fonte real (Supabase simulado)', () => {
  beforeEach(() => rpc.mockReset());

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
