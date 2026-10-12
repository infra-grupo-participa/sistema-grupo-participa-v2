// Coleta por conjunto e por anúncio do Meta (migration 20261012120000), testada SEM credencial e SEM API real: as
// respostas do Meta são fixtures inventadas (ids 9000000000003xx/4xx/5xx, marcadas "ENSAIO") em
// infra/supabase/functions/_trafego-fixtures, no formato documentado da Graph API. O banco e o Storage são simulados:
// o que se confere é o que a Edge manda para as funções de entrada e para o bucket.
import { describe, expect, it, vi } from 'vitest';
import {
  CAMPOS_DISTRIBUICAO, lerPaginas, paraDesempenho, type ContaMeta, type InsightMeta,
} from '../../../../../infra/supabase/functions/trafego-meta/meta';
import {
  CUSTO_MINIATURA_MS, LOTE_IDS, MAX_MINIATURAS, MINIATURA_MAX_BYTES, TIMEOUT_BANCO_MS, baixarMiniatura, coletarAnuncios, contasDaFlag, hostDeMiniaturaOk,
  paraDesempenhoAnuncio, tipoDaImagem, urlInsightsAnuncio, urlPorIds,
  type Baixar, type DepsAnuncios, type LinhaAnuncio, type LinhaConjunto, type LinhaDesempenhoAnuncio, type LinhaMiniatura,
} from '../../../../../infra/supabase/functions/trafego-meta/anuncios';
import insightsP1 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-insights-anuncio-p1.json';
import insightsP2 from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-insights-anuncio-p2.json';
import idsConjuntos from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-ids-conjuntos.json';
import idsAnuncios from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-ids-anuncios.json';
import erroToken from '../../../../../infra/supabase/functions/_trafego-fixtures/meta-erro-token.json';

type Resp = { ok: boolean; status: number; json(): Promise<unknown> };
const resp = (corpo: unknown, status = 200): Resp => ({ ok: status < 400, status, json: async () => corpo });

const CONTA: ContaMeta = { conta_externa: '000555', nome: 'Conta Ensaio R', token: 'token-ficticio-ensaio', token_origem: 'meta_ads_token' };
const JPG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);
const WEBP = new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);

/** fetch falso do Meta: responde pelas fixtures e guarda cada URL e o header (o token nunca vai na URL). */
function metaFalso(o: { erroInsights?: boolean; erroIds?: boolean } = {}) {
  const pedidos: { url: string; auth?: string }[] = [];
  const buscar = async (url: string, init?: { headers?: Record<string, string> }) => {
    pedidos.push({ url, auth: init?.headers?.Authorization });
    if (url.includes('/insights')) {
      if (o.erroInsights) return resp(erroToken, 400);
      return resp(url.includes('after=') ? insightsP2 : insightsP1);
    }
    if (url.includes('/?ids=')) {
      if (o.erroIds) return resp({ error: { code: 100 } }, 400);
      const ids = new URL(url).searchParams.get('ids')!.split(',');
      const fonte: Record<string, unknown> = url.includes('creative') ? idsAnuncios : idsConjuntos;
      return resp(Object.fromEntries(ids.filter((i) => fonte[i]).map((i) => [i, fonte[i]])));
    }
    return resp({ error: { code: 100 } }, 400);
  };
  return { buscar, pedidos };
}

/** Download falso: bytes por URL, conta as chamadas e guarda o init (redirect tem que ser 'error'). */
function baixarFalso(bytes: Record<string, Uint8Array<ArrayBuffer>> = {}, status = 200) {
  const chamadas: { url: string; redirect: string }[] = [];
  const baixar: Baixar = async (url, init) => {
    chamadas.push({ url, redirect: init.redirect });
    const b = bytes[url] ?? JPG;
    return { ok: status < 400, status, headers: new Headers(), body: new Response(b).body };
  };
  return { baixar, chamadas };
}

function deps(over: Partial<DepsAnuncios> = {}) {
  const ordem: string[] = [];
  const gravado = {
    conjuntos: [] as LinhaConjunto[], anuncios: [] as LinhaAnuncio[], desempenho: [] as LinhaDesempenhoAnuncio[],
    miniaturas: [] as LinhaMiniatura[], subidas: [] as { caminho: string; mime: string; tamanho: number }[],
  };
  const meta = metaFalso();
  const d: DepsAnuncios = {
    buscar: meta.buscar, versao: 'v23.0', de: '2026-10-10', ate: '2026-10-11', ate_ms: Date.now() + 110_000,
    lerPaginas, paraDesempenho, camposDistribuicao: CAMPOS_DISTRIBUICAO,
    receberConjuntos: async (l) => { ordem.push('conjuntos'); gravado.conjuntos.push(...l); return { ok: true, recusas: [] }; },
    receberAnuncios: async (l) => {
      ordem.push('anuncios'); gravado.anuncios.push(...l);
      return { ok: true, recusas: [], pendentes_miniatura: [...new Set(l.map((a) => a.criativo).filter(Boolean))] };
    },
    receberDesempenhoAnuncio: async (l) => { ordem.push('desempenho'); gravado.desempenho.push(...l); return { ok: true, recusas: [] }; },
    receberMiniaturas: async (l) => { ordem.push('miniaturas'); gravado.miniaturas.push(...l); return { ok: true, recusas: [] }; },
    subirMiniatura: async (caminho, bytes, mime) => { gravado.subidas.push({ caminho, mime, tamanho: bytes.byteLength }); },
    ...over,
  };
  return { d, ordem, gravado, pedidos: meta.pedidos };
}

describe('coleta Meta por conjunto e anúncio (respostas simuladas)', () => {
  it('URL dos insights: level=ad, por dia, mesmos campos de distribuição; sem token', () => {
    const u = new URL(urlInsightsAnuncio('v23.0', '000555', '2026-10-10', '2026-10-11', CAMPOS_DISTRIBUICAO));
    expect(u.pathname).toBe('/v23.0/act_000555/insights');
    expect(u.searchParams.get('level')).toBe('ad');
    expect(u.searchParams.get('time_increment')).toBe('1');
    expect(JSON.parse(u.searchParams.get('time_range')!)).toEqual({ since: '2026-10-10', until: '2026-10-11' });
    const campos = u.searchParams.get('fields')!;
    for (const c of ['ad_id', 'ad_name', 'adset_id', 'adset_name', 'campaign_id', 'spend', 'actions']) expect(campos.split(',')).toContain(c);
    expect(campos.endsWith(CAMPOS_DISTRIBUICAO)).toBe(true);
    expect(u.toString()).not.toContain('token');
  });

  it('?ids= em blocos de 50, sem repetidos e sem id fora do padrão', () => {
    const ids = Array.from({ length: 51 }, (_, k) => String(900000000000000 + k));
    const urls = urlPorIds('v23.0', [...ids, ids[0], 'abc', '1;drop'], 'id,name');
    expect(urls).toHaveLength(2);
    expect(new URL(urls[0]).searchParams.get('ids')!.split(',')).toHaveLength(LOTE_IDS);
    expect(new URL(urls[1]).searchParams.get('ids')).toBe(ids[50]);
    expect(new URL(urls[0]).pathname).toBe('/v23.0/');
    expect(urlPorIds('v23.0', [], 'id')).toEqual([]);
  });

  it('desempenho por anúncio = mesma conversão da campanha, trocando campanha por anúncio; sem ad_id descarta', () => {
    const insights = [...insightsP1.data, ...insightsP2.data] as InsightMeta[];
    const r = paraDesempenhoAnuncio(insights, paraDesempenho);
    expect(r.descartadas).toBe(1);
    expect(r.linhas.map((l) => l.anuncio)).toEqual(['900000000000401', '900000000000402', '900000000000403']);
    const camp = paraDesempenho([insights[0]]).linhas[0];
    const { campanha: _c, ...semCampanha } = camp;
    expect(r.linhas[0]).toEqual({ ...semCampanha, anuncio: '900000000000401' });
    expect(r.linhas[0]).toMatchObject({ gasto: 10.5, leads: 3, alcance: 800, frequencia: 1.25, cliques_saida: 28, video_p100: 50 });
    expect('campanha' in r.linhas[0]).toBe(false);
  });

  it('flag: nula, vazia ou lixo = nenhuma; só conta pedida, com token e ok nesta rodada', () => {
    const outra: ContaMeta = { ...CONTA, conta_externa: '000777' };
    const semToken: ContaMeta = { ...CONTA, conta_externa: '000888', token: null };
    const contas = [CONTA, outra, semToken];
    const res = [{ conta: '000555', ok: true }, { conta: '000777', ok: false }, { conta: '000888', ok: true }];
    expect(contasDaFlag(null, contas, res)).toEqual([]);
    expect(contasDaFlag('', contas, res)).toEqual([]);
    expect(contasDaFlag('  ', contas, res)).toEqual([]);
    expect(contasDaFlag(42, contas, res)).toEqual([]);
    expect(contasDaFlag("x' or 1=1, act_000555", contas, res)).toEqual([]);
    expect(contasDaFlag('000555', contas, res)).toEqual([CONTA]);
    expect(contasDaFlag('000555, 000777,000888', contas, res)).toEqual([CONTA]);
    expect(contasDaFlag('000999', contas, res)).toEqual([]);
  });

  it('caminho feliz: ordem conjuntos > anúncios > desempenho > miniaturas, paginação e nomes exatos', async () => {
    const { baixar, chamadas } = baixarFalso({
      'https://scontent.ensaio.fbcdn.net/v/t45.1600-4/ensaio-502.png': PNG,
    });
    const { d, ordem, gravado, pedidos } = deps({ baixar });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.puladas).toBe(0);
    expect(r.contas).toEqual([{ conta: '000555', ok: true, conjuntos: 2, anuncios: 3, linhas: 3, descartadas: 1, recusas: 0,
      cadastro_parcial: 0, miniaturas: 2, miniaturas_erro: 0 }]);
    expect(ordem).toEqual(['conjuntos', 'anuncios', 'desempenho', 'miniaturas']);
    // paginação: a segunda leitura de insights segue o paging.next (after=)
    const ins = pedidos.filter((p) => p.url.includes('/insights'));
    expect(ins).toHaveLength(2);
    expect(ins[1].url).toContain('after=MQZDZD');
    // token só no header, nunca na URL
    for (const p of pedidos) {
      expect(p.auth).toBe('Bearer token-ficticio-ensaio');
      expect(p.url).not.toContain('token-ficticio-ensaio');
    }
    expect(gravado.conjuntos).toContainEqual({ plataforma: 'meta', campanha: '900000000000201', id: '900000000000301',
      nome: 'ENSAIO | CONJ 01 | MORNO', status: 'ACTIVE', meta_otimizacao: 'LEAD_GENERATION' });
    expect(gravado.anuncios).toContainEqual({ plataforma: 'meta', conjunto: '900000000000301', id: '900000000000401',
      nome: 'ENSAIO | BF26 | C1 | TEASER | AD 01', status: 'ACTIVE', criativo: '900000000000501', video_id: '900000000000601',
      url_tags: 'utm_source=FB&utm_content={{ad.name}}|{{ad.id}}' });
    expect(gravado.desempenho.map((l) => `${l.anuncio}@${l.dia}`)).toEqual([
      '900000000000401@2026-10-10', '900000000000402@2026-10-10', '900000000000403@2026-10-11']);
    // miniatura: um download por criativo (dois anúncios dividem o 501), sem redirect, caminho meta/<conta>/<criativo>.<ext>
    expect(chamadas).toHaveLength(2);
    expect(chamadas.every((c) => c.redirect === 'error')).toBe(true);
    expect(gravado.subidas.map((s) => `${s.caminho} ${s.mime}`).sort()).toEqual([
      'meta/000555/900000000000501.jpg image/jpeg', 'meta/000555/900000000000502.png image/png']);
    expect(gravado.miniaturas).toEqual(expect.arrayContaining([
      { criativo: '900000000000501', caminho: 'meta/000555/900000000000501.jpg' },
      { criativo: '900000000000502', caminho: 'meta/000555/900000000000502.png' }]));
    // a URL do Meta nunca vai para o banco
    expect(JSON.stringify(gravado)).not.toContain('fbcdn');
  });

  it('erro do Meta nos insights vira código curto e nada é gravado', async () => {
    const { d, ordem } = deps({ buscar: metaFalso({ erroInsights: true }).buscar });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toEqual({ conta: '000555', ok: false, erro: 'meta_190_463' });
    expect(ordem).toEqual([]);
  });

  it('banco recusa conjuntos (ok:false): para a conta com banco_conjuntos', async () => {
    const { d, ordem } = deps({ receberConjuntos: async () => ({ ok: false }) });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toEqual({ conta: '000555', ok: false, erro: 'banco_conjuntos' });
    expect(ordem).toEqual([]);
  });

  it('função de entrada lança: vira "banco", sem derrubar a rodada', async () => {
    const { d } = deps({ receberDesempenhoAnuncio: async () => { throw new Error('conexao'); } });
    const r = await coletarAnuncios([CONTA, { ...CONTA, conta_externa: '000556' }], d);
    expect(r.contas.map((c) => c.erro)).toEqual(['banco', 'banco']);
  });

  it('sem tempo: nenhuma chamada ao Meta, conta pulada', async () => {
    const { d, pedidos, ordem } = deps({ ate_ms: 1000 });
    const r = await coletarAnuncios([CONTA], d, () => 2000);
    expect(r).toEqual({ ms: 0, puladas: 1, contas: [{ conta: '000555', ok: false, erro: 'sem_tempo' }] });
    expect(pedidos).toHaveLength(0);
    expect(ordem).toEqual([]);
  });

  it('busca por ids falha: cadastro sai dos insights (parcial) e o desempenho é gravado igual', async () => {
    const { d, gravado } = deps({ buscar: metaFalso({ erroIds: true }).buscar, baixar: baixarFalso().baixar });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toMatchObject({ ok: true, conjuntos: 2, anuncios: 3, linhas: 3, cadastro_parcial: 5,
      cadastro_erro: 'meta_100', miniaturas: 0 });
    expect(gravado.desempenho).toHaveLength(3);
    expect(gravado.anuncios.every((a) => a.status === null && a.criativo === null)).toBe(true);
    expect(gravado.conjuntos.find((c) => c.id === '900000000000302')?.nome).toBe('ENSAIO | CONJ 02 | FRIO');
  });

  it('sem baixar/subirMiniatura (env ausente): miniatura não é tocada', async () => {
    const { d, ordem, gravado } = deps();
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toMatchObject({ ok: true, miniaturas: 0, miniaturas_erro: 0 });
    expect(ordem).not.toContain('miniaturas');
    expect(gravado.subidas).toEqual([]);
  });

  it('miniatura no fim do orçamento (menos que download + upload + folga): não baixa', async () => {
    const { baixar, chamadas } = baixarFalso();
    const { d } = deps({ baixar, ate_ms: CUSTO_MINIATURA_MS - 1 });
    const r = await coletarAnuncios([CONTA], d, () => 0);
    expect(r.contas[0]).toMatchObject({ ok: true, miniaturas: 0 });
    expect(chamadas).toHaveLength(0);
  });

  it('upload falha: erro miniatura_upload registrado no banco', async () => {
    const { d, gravado } = deps({ baixar: baixarFalso().baixar, subirMiniatura: async () => { throw new Error('storage_500'); } });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toMatchObject({ ok: true, miniaturas: 0, miniaturas_erro: 2 });
    expect(gravado.miniaturas.every((m) => 'erro' in m && m.erro === 'miniatura_upload')).toBe(true);
  });

  it('limite de miniaturas por rodada', async () => {
    const urls = new Map<string, string>();
    const pend = Array.from({ length: MAX_MINIATURAS + 5 }, (_, k) => String(900000000000700 + k));
    for (const p of pend) urls.set(p, `https://scontent.ensaio.fbcdn.net/${p}.jpg`);
    const lidos = pend.map((p, k) => ({ id: String(900000000000800 + k), name: `ENSAIO ${k}`, adset_id: '900000000000301',
      creative: { id: p, thumbnail_url: urls.get(p) } }));
    const { baixar, chamadas } = baixarFalso();
    const meta = metaFalso();
    const buscar = async (url: string, init?: { headers?: Record<string, string> }) => {
      if (url.includes('/?ids=') && url.includes('creative')) return resp(Object.fromEntries(lidos.map((a) => [a.id, a])));
      if (url.includes('/insights') && !url.includes('after=')) {
        return resp({ data: lidos.map((a) => ({ ad_id: a.id, ad_name: a.name, adset_id: '900000000000301', adset_name: 'ENSAIO',
          campaign_id: '900000000000201', date_start: '2026-10-10', spend: '1.00' })) });
      }
      return meta.buscar(url, init);
    };
    const { d } = deps({ buscar, baixar });
    const r = await coletarAnuncios([CONTA], d);
    expect(r.contas[0]).toMatchObject({ ok: true, anuncios: MAX_MINIATURAS + 5, miniaturas: MAX_MINIATURAS });
    expect(chamadas).toHaveLength(MAX_MINIATURAS);
  });
});

describe('download da miniatura', () => {
  it('host: só https em *.fbcdn.net, sem porta nem usuário', () => {
    expect(hostDeMiniaturaOk('https://scontent.ensaio.fbcdn.net/a.jpg')).toBe(true);
    for (const u of ['http://scontent.ensaio.fbcdn.net/a.jpg', 'https://169.254.169.254/latest/meta-data',
      'https://fbcdn.net.evil.com/a.jpg', 'https://evilfbcdn.net/a.jpg', 'https://scontent.fbcdn.net:8443/a.jpg',
      'https://u:p@scontent.fbcdn.net/a.jpg', 'file:///etc/passwd', 'nao e url']) {
      expect(hostDeMiniaturaOk(u)).toBe(false);
    }
  });

  it('host fora da lista não faz fetch', async () => {
    const { baixar, chamadas } = baixarFalso();
    expect(await baixarMiniatura('https://169.254.169.254/x.jpg', baixar)).toEqual({ ok: false, erro: 'miniatura_host' });
    expect(await baixarMiniatura('http://scontent.fbcdn.net/x.jpg', baixar)).toEqual({ ok: false, erro: 'miniatura_host' });
    expect(chamadas).toHaveLength(0);
  });

  it('tipo pelos bytes: jpg, png, webp; o resto recusado', async () => {
    expect(tipoDaImagem(JPG)?.ext).toBe('jpg');
    expect(tipoDaImagem(PNG)?.ext).toBe('png');
    expect(tipoDaImagem(WEBP)?.mime).toBe('image/webp');
    const url = 'https://scontent.ensaio.fbcdn.net/x.jpg';
    const html = new TextEncoder().encode('<html>nao e imagem</html>');
    expect(await baixarMiniatura(url, baixarFalso({ [url]: html }).baixar)).toEqual({ ok: false, erro: 'miniatura_tipo' });
    const ok = await baixarMiniatura(url, baixarFalso({ [url]: WEBP }).baixar);
    expect(ok).toMatchObject({ ok: true, ext: 'webp', mime: 'image/webp' });
  });

  it('maior que 1 MB: recusada lendo o stream (sem confiar no content-length)', async () => {
    const url = 'https://scontent.ensaio.fbcdn.net/x.jpg';
    const grande = new Uint8Array(MINIATURA_MAX_BYTES + 1);
    grande.set(JPG);
    expect(await baixarMiniatura(url, baixarFalso({ [url]: grande }).baixar)).toEqual({ ok: false, erro: 'miniatura_grande' });
    const exato = new Uint8Array(MINIATURA_MAX_BYTES);
    exato.set(JPG);
    expect(await baixarMiniatura(url, baixarFalso({ [url]: exato }).baixar)).toMatchObject({ ok: true, ext: 'jpg' });
  });

  it('content-length acima do limite: recusa antes de ler', async () => {
    const url = 'https://scontent.ensaio.fbcdn.net/x.jpg';
    const baixar: Baixar = async () => ({ ok: true, status: 200, headers: new Headers({ 'content-length': '5000000' }),
      body: new Response(JPG).body });
    expect(await baixarMiniatura(url, baixar)).toEqual({ ok: false, erro: 'miniatura_grande' });
  });

  it('HTTP de erro e falha de rede (inclui redirect recusado)', async () => {
    const url = 'https://scontent.ensaio.fbcdn.net/x.jpg';
    expect(await baixarMiniatura(url, baixarFalso({}, 403).baixar)).toEqual({ ok: false, erro: 'miniatura_http_403' });
    const rede: Baixar = async () => { throw new TypeError('redirect mode is set to error'); };
    expect(await baixarMiniatura(url, rede)).toEqual({ ok: false, erro: 'miniatura_rede' });
  });
});

// Ressalva do pentester (12/10/2026): a fase de anúncios tem orçamento próprio, conferido antes de CADA chamada, para
// nunca levar a Edge aos 150 s sem o coleta_registrar da rodada de campanha. Relógio falso: o tempo anda só quando o
// teste manda.
describe('orçamento da fase de anúncios (para por tempo)', () => {
  it('o relógio passa do fim no meio da conta: para antes da próxima chamada, sem gravar, e a conta seguinte é pulada', async () => {
    let t = 0;
    const meta = metaFalso();
    const sinais: (AbortSignal | undefined)[] = [];
    // cada leitura do Meta "leva" 10 s
    const buscar = async (url: string, init?: { headers?: Record<string, string>; signal?: AbortSignal }) => {
      sinais.push(init?.signal);
      const r = await meta.buscar(url, init);
      t += 10_000;
      return r;
    };
    const { d, ordem } = deps({ buscar, ate_ms: 25_000 });
    const r = await coletarAnuncios([CONTA, { ...CONTA, conta_externa: '000556' }], d, () => t);
    // insights p1 (0 s), insights p2 (10 s), ?ids= dos conjuntos (20 s); aos 30 s não começa mais nada
    expect(meta.pedidos.map((p) => (p.url.includes('/insights') ? 'insights' : 'ids'))).toEqual(['insights', 'insights', 'ids']);
    expect(ordem).toEqual([]);
    expect(r.puladas).toBe(1);
    expect(r.contas).toEqual([{ conta: '000555', ok: false, erro: 'sem_tempo' }, { conta: '000556', ok: false, erro: 'sem_tempo' }]);
    // toda leitura do Meta saiu com timeout próprio (o lerPaginas não põe signal)
    expect(sinais.every((s) => s instanceof AbortSignal)).toBe(true);
  });

  it('timeout de cada função de entrada = o menor entre o teto e o que resta da fase', async () => {
    const ms: number[] = [];
    const { d } = deps({
      ate_ms: 12_000,
      receberConjuntos: async (_l, m) => { ms.push(m); return { ok: true, recusas: [] }; },
      receberAnuncios: async (_l, m) => { ms.push(m); return { ok: true, recusas: [] }; },
      receberDesempenhoAnuncio: async (_l, m) => { ms.push(m); return { ok: true, recusas: [] }; },
    });
    const r = await coletarAnuncios([CONTA], d, () => 0);
    expect(r.contas[0]).toMatchObject({ ok: true });
    expect(ms).toEqual([12_000, 12_000, 12_000]);
    const { d: d2 } = deps({ ate_ms: 100_000, receberConjuntos: async (_l, m) => { ms.push(m); return { ok: true }; } });
    await coletarAnuncios([CONTA], d2, () => 0);
    expect(ms.at(-1)).toBe(TIMEOUT_BANCO_MS);
  });

  it('função de entrada que trava é abandonada no fim da fase: conta sai com sem_tempo e nada depois dela roda', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    try {
      let t = 0;
      const pedido: number[] = [];
      const { d, ordem } = deps({
        ate_ms: 8_000,
        receberAnuncios: (_l, m) => { pedido.push(m); return new Promise(() => { /* banco travado */ }); },
      });
      const rodada = coletarAnuncios([CONTA], d, () => t);
      await vi.advanceTimersByTimeAsync(7_999);
      t = 7_999;
      let acabou = false;
      void rodada.then(() => { acabou = true; });
      await Promise.resolve();
      expect(acabou).toBe(false);
      t = 8_000;
      await vi.advanceTimersByTimeAsync(1);
      const r = await rodada;
      expect(pedido).toEqual([8_000]);
      expect(ordem).toEqual(['conjuntos']);
      expect(r.contas).toEqual([{ conta: '000555', ok: false, erro: 'sem_tempo' }]);
    } finally {
      vi.useRealTimers();
    }
  });

  it('miniatura só começa se couber download + upload + folga; o upload recebe o timeout dele', async () => {
    const { baixar, chamadas } = baixarFalso();
    const subidas: number[] = [];
    const { d } = deps({ baixar, ate_ms: CUSTO_MINIATURA_MS, subirMiniatura: async (_c, _b, _m, ms) => { subidas.push(ms); } });
    const r = await coletarAnuncios([CONTA], d, () => 0);
    expect(r.contas[0]).toMatchObject({ ok: true, miniaturas: 2 });
    expect(chamadas).toHaveLength(2);
    expect(subidas).toEqual([15_000, 15_000]);
  });
});
