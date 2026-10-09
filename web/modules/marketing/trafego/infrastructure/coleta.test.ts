// Rotinas de coleta do Tráfego (migration 20261006i) testadas SEM credencial e SEM API real: as respostas do Meta, do
// ClickUp e do Google são simuladas (fixtures inventadas, marcadas "ENSAIO", em infra/supabase/functions/_trafego-fixtures,
// no formato documentado de cada API). O que se confere: o que a Edge manda para as funções de entrada do banco.
import { describe, expect, it } from 'vitest';
import {
  acao, paraTotais, urlTotais, type LinhaTotal,
  coletarConta, coletarMeta, hojeSaoPaulo, leadsDasAcoes, lerPaginas, paraCampanhas, paraDesempenho, periodo, urlInsights,
  type ContaMeta, type LinhaCampanha, type LinhaDesempenho,
} from '../../../../../infra/supabase/functions/trafego-meta/meta';
import { coletarClickup, lerEtiquetasDosSpaces, msParaIso, paraEspelho, urlTarefas, type TarefaEspelho } from '../../../../../infra/supabase/functions/trafego-clickup/clickup';
import { consultaGaql, paraEntrada } from '../../../../../infra/supabase/functions/trafego-google/google';
import campanhasP1 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-campanhas-p1.json';
import campanhasP2 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-campanhas-p2.json';
import insightsP1 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-insights-p1.json';
import insightsP2 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-insights-p2.json';
import erroToken from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-erro-token.json';
import clickupP0 from '../../../../../infra/supabase/functions/_trafego-fixtures/clickup-p0.json';
import clickupP1 from '../../../../../infra/supabase/functions/_trafego-fixtures/clickup-p1.json';
import googleStream from '../../../../../infra/supabase/functions/_trafego-fixtures/google-searchstream.json';

type Resp = { ok: boolean; status: number; json(): Promise<unknown> };
const resp = (corpo: unknown, status = 200): Resp => ({ ok: status < 400, status, json: async () => corpo });

/** fetch falso do Meta: responde pelas fixtures e guarda o que foi pedido (para conferir que o token não vai na URL). */
function metaFalso(opcoes: { erro?: boolean } = {}) {
  const pedidos: { url: string; auth?: string }[] = [];
  const buscar = async (url: string, init?: { headers?: Record<string, string> }) => {
    pedidos.push({ url, auth: init?.headers?.Authorization });
    if (opcoes.erro) return resp(erroToken, 400);
    if (url.includes('/campaigns')) return resp(url.includes('after=') ? campanhasP2 : campanhasP1);
    if (url.includes('/insights')) return resp(url.includes('after=') ? insightsP2 : insightsP1);
    return resp({ error: { code: 100 } }, 400);
  };
  return { buscar, pedidos };
}

const CONTA: ContaMeta = { conta_externa: '000555', nome: 'Conta Ensaio R', token: 'token-ficticio-ensaio', token_origem: 'meta_ads_token' };

describe('coleta Meta Ads (respostas simuladas)', () => {
  it('período: dias completos para trás + hoje; recarga até 92 dias; datas ruins recusadas', () => {
    expect(periodo('2026-10-05', 3)).toEqual({ de: '2026-10-02', ate: '2026-10-05' });
    expect(periodo('2026-10-05', 0)).toEqual({ de: '2026-10-05', ate: '2026-10-05' });
    expect(periodo('2026-03-01', 1)).toEqual({ de: '2026-02-28', ate: '2026-03-01' });
    expect(periodo('2026-10-05', 3, '2026-09-01', '2026-09-30')).toEqual({ de: '2026-09-01', ate: '2026-09-30' });
    expect(periodo('2026-10-05', 3, '2026-01-01', '2026-09-30')).toBeNull();
    expect(periodo('2026-10-05', 3, '2026-10-04', '2026-10-01')).toBeNull();
    expect(periodo('2026-10-05', 3, '2026-10-04', '2026-10-09')).toBeNull();
    expect(periodo('2026-10-05', 3, 'ontem', '2026-10-01')).toBeNull();
  });

  it('hoje em São Paulo (UTC-3): 02h UTC ainda é o dia anterior', () => {
    expect(hojeSaoPaulo(new Date('2026-10-06T02:00:00Z'))).toBe('2026-10-05');
    expect(hojeSaoPaulo(new Date('2026-10-06T03:30:00Z'))).toBe('2026-10-06');
  });

  it('URL dos insights: por campanha e dia, cliques no link e ações; sem token', () => {
    const u = new URL(urlInsights('v23.0', '000555', '2026-10-02', '2026-10-05'));
    expect(u.pathname).toBe('/v23.0/act_000555/insights');
    expect(u.searchParams.get('level')).toBe('campaign');
    expect(u.searchParams.get('time_increment')).toBe('1');
    expect(JSON.parse(u.searchParams.get('time_range')!)).toEqual({ since: '2026-10-02', until: '2026-10-05' });
    expect(u.searchParams.get('fields')).toContain('inline_link_clicks');
    expect(u.searchParams.has('access_token')).toBe(false);
  });

  it('desempenho: cliques no link = inline_link_clicks, totais = clicks, leads = ação "lead"; sem gasto descarta', () => {
    const { linhas, descartadas } = paraDesempenho([...insightsP1.data, ...insightsP2.data]);
    expect(descartadas).toBe(1);
    expect(linhas).toEqual<LinhaDesempenho[]>([
      { plataforma: 'meta', campanha: '900000000000201', dia: '2026-10-03', gasto: 150.25, impressoes: 12000, cliques_link: 180, cliques_total: 260, leads: 12, alcance: null, frequencia: null, cliques_saida: null, landing_page_views: 130, engajamento: null, video_plays: null, video_thruplay: null, video_p25: null, video_p50: null, video_p75: null, video_p100: null },
      { plataforma: 'meta', campanha: '900000000000201', dia: '2026-10-04', gasto: 149.75, impressoes: 11000, cliques_link: 170, cliques_total: 240, leads: 9, alcance: null, frequencia: null, cliques_saida: null, landing_page_views: null, engajamento: null, video_plays: null, video_thruplay: null, video_p25: null, video_p50: null, video_p75: null, video_p100: null },
      { plataforma: 'meta', campanha: '900000000000202', dia: '2026-10-04', gasto: 20, impressoes: 3000, cliques_link: 0, cliques_total: 15, leads: null, alcance: null, frequencia: null, cliques_saida: null, landing_page_views: null, engajamento: null, video_plays: null, video_thruplay: null, video_p25: null, video_p50: null, video_p75: null, video_p100: null },
      { plataforma: 'meta', campanha: '900000000000209', dia: '2026-10-03', gasto: 5.5, impressoes: 400, cliques_link: 3, cliques_total: null, leads: null, alcance: null, frequencia: null, cliques_saida: null, landing_page_views: null, engajamento: null, video_plays: null, video_thruplay: null, video_p25: null, video_p50: null, video_p75: null, video_p100: null },
    ]);
    expect(leadsDasAcoes([{ action_type: 'link_click', value: '3' }])).toBeNull();
  });

  it('20261009230000: métricas de distribuição (alcance, frequência, vídeo, engajamento); ausente = null, nunca 0', () => {
    const { linhas } = paraDesempenho([{
      campaign_id: '900000000000301', date_start: '2026-10-08', spend: '50.06', impressions: '886', clicks: '12', inline_link_clicks: '0',
      reach: '772', frequency: '1.147668',
      actions: [{ action_type: 'post_engagement', value: '363' }, { action_type: 'video_view', value: '355' }],
      video_play_actions: [{ action_type: 'video_view', value: '811' }], video_thruplay_watched_actions: [{ action_type: 'video_view', value: '92' }],
      video_p25_watched_actions: [{ action_type: 'video_view', value: '11' }], video_p50_watched_actions: [{ action_type: 'video_view', value: '6' }],
      video_p75_watched_actions: [{ action_type: 'video_view', value: '4' }], video_p100_watched_actions: [{ action_type: 'video_view', value: '4' }],
    }]);
    expect(linhas[0]).toMatchObject({ alcance: 772, frequencia: 1.1477, engajamento: 363, video_plays: 811, video_thruplay: 92,
      video_p25: 11, video_p50: 6, video_p75: 4, video_p100: 4, cliques_saida: null, landing_page_views: null, cliques_link: 0 });
    expect(acao([{ action_type: 'outbound_click', value: '5' }], 'outbound_click')).toBe(5);
    expect(acao(undefined, null)).toBeNull();
  });

  it('20261009230000: total do período inteiro por campanha (alcance não soma por dia); URL com date_preset=maximum e filtro por id', () => {
    const u = new URL(urlTotais('v23.0', '000555', ['900000000000201', '900000000000202']));
    expect(u.searchParams.get('date_preset')).toBe('maximum');
    expect(u.searchParams.has('time_increment')).toBe(false);
    expect(JSON.parse(u.searchParams.get('filtering')!)).toEqual([{ field: 'campaign.id', operator: 'IN', value: ['900000000000201', '900000000000202'] }]);
    expect(paraTotais([{ campaign_id: '900000000000201', date_start: '2026-10-08', date_stop: '2026-10-09', spend: '87.26', impressions: '1434', reach: '985', frequency: '1.455838' },
      { campaign_id: '900000000000202', date_start: 'ontem', date_stop: '2026-10-09' }]))
      .toEqual<LinhaTotal[]>([{ plataforma: 'meta', campanha: '900000000000201', de: '2026-10-08', ate: '2026-10-09', gasto: 87.26, impressoes: 1434, alcance: 985, frequencia: 1.4558 }]);
  });

  it('20261009230000: falha na leitura dos totais não derruba a conta (vira totais_erro)', async () => {
    const { buscar } = metaFalso();
    const quebra = async (url: string, init?: { headers?: Record<string, string> }) =>
      url.includes('date_preset=maximum') ? resp({ error: { code: 100 } }, 400) : buscar(url, init);
    const nada = async () => ({ ok: true, recusas: [] });
    const r = await coletarConta(CONTA, { buscar: quebra, versao: 'v23.0', de: '2026-10-02', ate: '2026-10-05',
      receberCampanhas: nada, receberDesempenho: nada, receberTotais: nada });
    expect([r.ok, r.linhas, r.totais_erro]).toEqual([true, 4, 'meta_100']);
  });

  it('campanhas: nome exato da lista + a que só aparece nos insights (status nulo)', () => {
    const lc = paraCampanhas('000555', [...campanhasP1.data, ...campanhasP2.data], [...insightsP1.data, ...insightsP2.data]);
    expect(lc).toEqual<LinhaCampanha[]>([
      { plataforma: 'meta', conta: '000555', id: '900000000000201', nome: 'RS | ZZ28 | LEADS | ENSAIO PÚBLICO FRIO | AK1', status: 'ACTIVE' },
      { plataforma: 'meta', conta: '000555', id: '900000000000202', nome: 'CF | ZZ28 | REMARKETING | ENSAIO', status: 'PAUSED' },
      { plataforma: 'meta', conta: '000555', id: '900000000000203', nome: 'Campanha ENSAIO fora do padrão', status: 'ACTIVE' },
      { plataforma: 'meta', conta: '000555', id: '900000000000209', nome: 'RS | ZZ28 | LEADS | ENSAIO APAGADA', status: null },
    ]);
  });

  it('conta inteira: lê as 2 páginas de cada, grava campanhas antes do desempenho, token só no header', async () => {
    const { buscar, pedidos } = metaFalso();
    const ordem: string[] = [];
    let campanhas: LinhaCampanha[] = [];
    let desempenho: LinhaDesempenho[] = [];
    const r = await coletarConta(CONTA, {
      buscar, versao: 'v23.0', de: '2026-10-02', ate: '2026-10-05',
      receberCampanhas: async (l) => { ordem.push('campanhas'); campanhas = l; return { ok: true, recusas: [] }; },
      receberDesempenho: async (l) => { ordem.push('desempenho'); desempenho = l; return { ok: true, recusas: [{ motivo: 'x' }] }; },
    });
    expect(r).toEqual({ conta: '000555', token_origem: 'meta_ads_token', ok: true, campanhas: 4, linhas: 4, descartadas: 1, recusas_campanhas: 0, recusas_desempenho: 1 });
    expect(ordem).toEqual(['campanhas', 'desempenho']);
    expect(campanhas).toHaveLength(4);
    expect(desempenho.reduce((a, l) => a + l.gasto, 0)).toBeCloseTo(325.5, 2);
    expect(pedidos).toHaveLength(4);
    expect(pedidos.every((p) => p.auth === 'Bearer token-ficticio-ensaio' && !p.url.includes('token-ficticio'))).toBe(true);
  });

  it('erros: token inválido vira código curto (sem a mensagem do Meta); sem token não chama a API; uma conta não para as outras', async () => {
    const { buscar } = metaFalso({ erro: true });
    const nada = async () => ({ ok: true, recusas: [] });
    const deps = { buscar, versao: 'v23.0', de: '2026-10-05', ate: '2026-10-05', receberCampanhas: nada, receberDesempenho: nada };
    const r = await coletarMeta([CONTA, { ...CONTA, conta_externa: '000556', token: null, token_origem: 'meta_ads_token_zz' }], deps);
    expect(r.contas).toEqual([
      { conta: '000555', token_origem: 'meta_ads_token', ok: false, erro: 'meta_190_463' },
      { conta: '000556', token_origem: 'meta_ads_token_zz', ok: false, erro: 'sem_token' },
    ]);
    expect(JSON.stringify(r)).not.toContain('Error validating');
  });

  it('paginação para fora do Graph é recusada; orçamento de tempo pula as contas restantes', async () => {
    const buscar = async () => resp({ data: [], paging: { next: 'https://exemplo.invalid/pega-token' } });
    await expect(lerPaginas(buscar, 'https://graph.facebook.com/v23.0/act_1/campaigns', 't')).rejects.toThrow('paginacao');
    const { buscar: b2 } = metaFalso();
    const nada = async () => ({ ok: true, recusas: [] });
    let t = 0;
    const r = await coletarMeta([CONTA, CONTA], { buscar: b2, versao: 'v23.0', de: 'x', ate: 'y', receberCampanhas: nada, receberDesempenho: nada, ate_ms: 0 }, () => t++);
    expect([r.contas.length, r.puladas]).toEqual([1, 1]);
  });

  it('o banco recusou o lote: a conta sai com erro e o desempenho não é mandado', async () => {
    const { buscar } = metaFalso();
    let mandou = false;
    const r = await coletarConta(CONTA, {
      buscar, versao: 'v23.0', de: 'a', ate: 'b',
      receberCampanhas: async () => ({ ok: false }),
      receberDesempenho: async () => { mandou = true; return { ok: true }; },
    });
    expect([r.ok, r.erro, mandou]).toEqual([false, 'banco_campanhas', false]);
  });
});

describe('leitura do ClickUp (respostas simuladas, só leitura)', () => {
  it('URL: tarefas do workspace pela etiqueta, com as fechadas e as subtarefas', () => {
    const u = new URL(urlTarefas('9000001', 'zz-ensaio-r', 1));
    expect(u.pathname).toBe('/api/v2/team/9000001/task');
    expect(u.searchParams.getAll('tags[]')).toEqual(['zz-ensaio-r']);
    expect([u.searchParams.get('include_closed'), u.searchParams.get('subtasks'), u.searchParams.get('page')]).toEqual(['true', 'true', '1']);
  });

  it('espelho mínimo: datas em ISO, responsável pelo nome (sem e-mail), etiqueta em minúsculas, url só do ClickUp', () => {
    const e = paraEspelho(clickupP0.tasks[0])!;
    expect(e).toEqual<TarefaEspelho>({
      id: '86ensaio1', nome: 'Subir campanhas de captação (ENSAIO)', status: 'complete',
      criada_em: '2025-09-27T19:06:40.000Z', atualizada_em: '2025-10-02T10:13:20.000Z', inicio: null,
      prazo: '2025-10-02T09:00:00.000Z', concluida_em: '2025-10-02T10:13:20.000Z',
      responsaveis: ['Responsável Ensaio'], etiquetas: ['zz-ensaio-r'], url: 'https://app.clickup.com/t/86ensaio1',
    });
    expect(JSON.stringify(e)).not.toContain('exemplo.invalid');
    expect(paraEspelho(clickupP0.tasks[1])!.etiquetas).toEqual(['zz-ensaio-r', 'outra-etq']);
    expect(paraEspelho(clickupP1.tasks[0])!.url).toBeNull();
    expect(paraEspelho(clickupP1.tasks[1] as never)).toBeNull();
    expect([msParaIso(null), msParaIso(''), msParaIso('abc')]).toEqual([null, null, null]);
  });

  it('lê todas as páginas e manda o conjunto inteiro por etiqueta; falha numa etiqueta não grava ela', async () => {
    const pedidos: string[] = [];
    const buscar = async (url: string, init?: { headers?: Record<string, string> }) => {
      pedidos.push(`${init?.headers?.Authorization}|${url}`);
      if (url.includes('tags%5B%5D=quebrada')) return resp({}, 500);
      return resp(url.includes('page=1') ? clickupP1 : clickupP0);
    };
    const gravados: { etiqueta: string; tarefas: TarefaEspelho[] }[] = [];
    const r = await coletarClickup(['zz-ensaio-r', 'quebrada'], {
      buscar, token: 'pk_ficticio', team: '9000001',
      receber: async (p) => { gravados.push(p); return { ok: true, removidas: 0, recusas: [] }; },
    });
    expect(r).toEqual([
      { etiqueta: 'zz-ensaio-r', ok: true, tarefas: 3, removidas: 0, recusas: 0 },
      { etiqueta: 'quebrada', ok: false, erro: 'http_500' },
    ]);
    expect(gravados.map((g) => [g.etiqueta, g.tarefas.map((t) => t.id)])).toEqual([['zz-ensaio-r', ['86ensaio1', '86ensaio2', '86ensaio3']]]);
    expect(pedidos.every((p) => p.startsWith('pk_ficticio|https://api.clickup.com/api/v2/team/9000001/task?'))).toBe(true);
  });

  it('20261006j: etiquetas reais dos spaces (só GET), minúsculas, sem repetição; falha = erro', async () => {
    const pedidos: string[] = [];
    const buscar = async (url: string) => {
      pedidos.push(url);
      if (url.endsWith('/team/9000001/space?archived=false')) return resp({ spaces: [{ id: '901' }, { id: 902 }] });
      if (url.endsWith('/space/901/tag')) return resp({ tags: [{ name: 'zz-ensaio-b' }, { name: 'ZZ-Ensaio-A' }] });
      if (url.endsWith('/space/902/tag')) return resp({ tags: [{ name: 'zz-ensaio-a' }, { name: '' }] });
      return resp({}, 404);
    };
    expect(await lerEtiquetasDosSpaces(buscar, 'pk_ficticio', '9000001')).toEqual(['zz-ensaio-a', 'zz-ensaio-b']);
    expect(pedidos).toEqual([
      'https://api.clickup.com/api/v2/team/9000001/space?archived=false',
      'https://api.clickup.com/api/v2/space/901/tag', 'https://api.clickup.com/api/v2/space/902/tag',
    ]);
    await expect(lerEtiquetasDosSpaces(async () => resp({}, 401), 'pk_ficticio', '9000001')).rejects.toThrow('http_401');
  });
});

describe('Google Ads (esqueleto, resposta simulada)', () => {
  it('GAQL por campanha e dia; custo em micros vira reais; cliques = cliques no link (decisão pendente)', () => {
    expect(consultaGaql('2026-10-01', '2026-10-05')).toContain("segments.date BETWEEN '2026-10-01' AND '2026-10-05'");
    expect(() => consultaGaql("2026-10-01' OR 1=1 --", '2026-10-05')).toThrow();
    const r = paraEntrada('0000000001', googleStream);
    expect(r.campanhas).toEqual([{ plataforma: 'google', conta: '0000000001', id: '700001', nome: 'CF | ZZ28 | LEADS | ENSAIO PESQUISA', status: 'ENABLED' }]);
    expect(r.desempenho.map((d) => [d.dia, d.gasto, d.impressoes, d.cliques_link])).toEqual([['2026-10-04', 45.67, 1500, 60], ['2026-10-03', 1, 90, 0]]);
  });
});
