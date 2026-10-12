// trafego-meta: coleta por conjunto (adset) e por anúncio (migration 20261012120000). Parte pura, sem Deno e sem banco:
// testada no vitest (web/modules/marketing/trafego/infrastructure/coleta-anuncios.test.ts, fixtures em
// infra/supabase/functions/_trafego-fixtures/meta-*-anuncio*.json e meta-ids-*.json).
//
// LIGA E DESLIGA POR CONTA: só roda nas contas listadas em mkt_trafego.coleta_config 'meta_anuncio_contas' (nasce
// nula = desligada) e só nas que tiveram a coleta de campanha ok NESTA rodada (o conjunto precisa da campanha gravada).
// Roda DEPOIS do coletarMeta e fica FORA do ok/erro da rodada: falha aqui aparece só em
// mkt_trafego.coletas.resultado -> 'anuncios' (o vigia de rotinas não vê).
//
// ORÇAMENTO PRÓPRIO (ressalva do pentester, 12/10/2026): ate_ms é o fim da FASE de anúncios, que o index.ts põe com
// folga antes dos 150 s da Edge, para o coleta_registrar da rodada de campanha rodar sempre. O tempo é conferido antes
// de CADA chamada (insights, cada página, cada bloco de cadastro, cada função de entrada, cada miniatura) e o timeout de cada
// uma é limitado ao que resta (classe Prazo). Sem tempo, a conta para com erro 'sem_tempo' (o que já foi gravado fica:
// os upserts são idempotentes e a próxima rodada completa). Miniatura só começa se couber download (10 s) mais upload
// (15 s) mais folga (5 s).
//
// O que lê da Graph API (só leitura), por conta:
//   GET /act_<conta>/insights?level=ad&time_increment=1&time_range={since,until}
//       &fields=ad_id,ad_name,adset_id,adset_name,campaign_id,date_start,spend,impressions,clicks,inline_link_clicks,
//               actions + CAMPOS_DISTRIBUICAO (os mesmos campos da coleta por campanha)
//   GET /act_<conta>/adsets?fields=id,name,effective_status,campaign_id,optimization_goal
//       &filtering=[{id IN <até 50 conjuntos>},{effective_status IN STATUS_CADASTRO}]&limit=50
//   GET /act_<conta>/ads?fields=id,name,effective_status,adset_id,campaign_id,creative{id,thumbnail_url,video_id,url_tags}
//       &filtering=[{id IN <até 50 anúncios>},{effective_status IN STATUS_CADASTRO}]&limit=50
// As duas seguem paging.next (lerPaginas). Até 12/10/2026 o cadastro saía de GET /?ids=, que o Meta passou a recusar
// em TODA versão (HTTP 500, code 100, "The ids query parameter is deprecated in v26.0+", rodada 158; explain seção 11).
// O filtro de status é obrigatório: sem ele a borda da conta esconde ARCHIVED, e anúncio com gasto no período pode estar
// arquivado hoje (medido na CNF em 12/10/2026: 4 ids pedidos, 2 voltaram sem o filtro e os 4 com ele).
// O cadastro vem só dos ids que tiveram entrega (nunca lista /act_x/ads inteiro). Se a busca falhar, ou se um id pedido
// não voltar, o cadastro dele sai das próprias linhas de insights (nome exato, status nulo) e conta em
// cadastro_parcial: o desempenho nunca fica sem anúncio.
// Grava por public.trafego_conjuntos_receber, trafego_anuncios_receber, trafego_desempenho_anuncio_receber e
// trafego_anuncio_miniatura_receber. Miniatura: baixa a thumbnail_url (só https em *.fbcdn.net, sem redirect, até 1 MB,
// tipo pelos bytes) e guarda no bucket privado trafego-miniaturas; a URL do Meta nunca é gravada.
//
// Por que só "import type" de ./meta.ts: o tsc do web (que roda os testes) recusa import de VALOR de arquivo .ts com
// extensão (TS5097). As funções de meta.ts que este módulo usa (lerPaginas, paraDesempenho, CAMPOS_DISTRIBUICAO) chegam
// por injeção, do index.ts e do teste. Assim meta.ts não muda e o mapeamento das métricas não é duplicado.
import type { ContaMeta, InsightMeta, LinhaDesempenho, ResultadoConta } from './meta.ts';

const BASE = 'https://graph.facebook.com';
const PLATAFORMA = 'meta';
/** Ids por busca de cadastro (filtering id IN); 50 mantém a URL curta e cabe numa página (limit=50). */
export const LOTE_IDS = 50;
/** Teto das funções de entrada (20261012120000). */
export const LOTE_ANUNCIO = 5000;
/** Miniaturas por rodada (o resto fica para a próxima). */
export const MAX_MINIATURAS = 20;
export const MINIATURA_MAX_BYTES = 1_048_576;
/** Teto de cada chamada ao Meta e ao banco (ms); o efetivo é o menor entre o teto e o que resta da fase. */
export const TIMEOUT_META_MS = 30_000;
export const TIMEOUT_BANCO_MS = 20_000;
/** A menos disto do fim da fase, nenhuma chamada nova começa (ms). */
export const MIN_CHAMADA_MS = 2_000;
export const MINIATURA_DOWNLOAD_MS = 10_000;
export const MINIATURA_UPLOAD_MS = 15_000;
export const FOLGA_MINIATURA_MS = 5_000;
/** Só começa uma miniatura se sobrar isto da fase (download + upload + folga). */
export const CUSTO_MINIATURA_MS = MINIATURA_DOWNLOAD_MS + MINIATURA_UPLOAD_MS + FOLGA_MINIATURA_MS;
const RE_ID = /^[0-9]{1,30}$/;
const RE_EXTERNA = /^[A-Za-z0-9_-]{1,60}$/;

export interface InsightAnuncio extends InsightMeta { ad_id?: string; ad_name?: string; adset_id?: string; adset_name?: string }
export interface ConjuntoMeta { id?: string; name?: string; effective_status?: string; campaign_id?: string; optimization_goal?: string }
export interface AnuncioMeta {
  id?: string; name?: string; effective_status?: string; adset_id?: string; campaign_id?: string;
  creative?: { id?: string; thumbnail_url?: string; video_id?: string; url_tags?: string };
}
export interface LinhaConjunto {
  plataforma: 'meta'; campanha: string; id: string; nome: string; status: string | null; meta_otimizacao: string | null;
}
export interface LinhaAnuncio {
  plataforma: 'meta'; conjunto: string; id: string; nome: string; status: string | null;
  criativo: string | null; video_id: string | null; url_tags: string | null;
}
export type LinhaDesempenhoAnuncio = Omit<LinhaDesempenho, 'campanha'> & { anuncio: string };
export type LinhaMiniatura = { criativo: string; caminho: string } | { criativo: string; erro: string };

type Buscar = (url: string, init?: { headers?: Record<string, string>; signal?: AbortSignal }) => Promise<{
  ok: boolean; status: number; json(): Promise<unknown>;
}>;
export interface RespostaBinaria {
  ok: boolean; status: number; headers?: { get(nome: string): string | null } | null; body: ReadableStream<Uint8Array> | null;
}
export type Baixar = (url: string, init: { redirect: 'error'; signal: AbortSignal }) => Promise<RespostaBinaria>;
type Receber = { ok?: boolean; recusas?: unknown[] };

export interface DepsAnuncios {
  buscar: Buscar;
  versao: string;
  de: string;
  ate: string;
  /** Fim da FASE de anúncios (epoch ms). Nenhuma chamada começa a menos de MIN_CHAMADA_MS dele. */
  ate_ms: number;
  /** De meta.ts, injetados (ver o cabeçalho). */
  lerPaginas: <T>(buscar: Buscar, url: string, token: string) => Promise<T[]>;
  paraDesempenho: (insights: InsightMeta[]) => { linhas: LinhaDesempenho[]; descartadas: number };
  camposDistribuicao: string;
  /** ms = tempo máximo desta chamada (o index.ts aplica como statement_timeout da transação). */
  receberConjuntos: (l: LinhaConjunto[], ms: number) => Promise<Receber>;
  receberAnuncios: (l: LinhaAnuncio[], ms: number) => Promise<Receber & { pendentes_miniatura?: unknown[] }>;
  receberDesempenhoAnuncio: (l: LinhaDesempenhoAnuncio[], ms: number) => Promise<Receber>;
  receberMiniaturas: (l: LinhaMiniatura[], ms: number) => Promise<Receber>;
  /** Sem baixar ou sem subirMiniatura, as miniaturas não são tocadas (fail-closed). */
  baixar?: Baixar;
  /** ms = tempo máximo do upload (até MINIATURA_UPLOAD_MS). */
  subirMiniatura?: (caminho: string, bytes: Uint8Array<ArrayBuffer>, mime: string, ms: number) => Promise<void>;
}

export interface ResultadoContaAnuncio {
  conta: string; ok: boolean; erro?: string;
  conjuntos?: number; anuncios?: number; linhas?: number; descartadas?: number; recusas?: number;
  cadastro_parcial?: number; cadastro_erro?: string; miniaturas?: number; miniaturas_erro?: number;
}
export interface ResultadoAnuncios { ms: number; puladas: number; contas: ResultadoContaAnuncio[] }

class ErroAnuncio extends Error {
  constructor(public codigo: string) { super(codigo); }
}
/** Relógio da fase de anúncios: confere o tempo antes de cada chamada e devolve o timeout dela (teto ou o que resta). */
export class Prazo {
  estourou = false;
  constructor(readonly ate_ms: number, readonly agora: () => number) {}
  resta(): number { return this.ate_ms - this.agora(); }
  /** Lança ErroAnuncio('sem_tempo') se faltar menos que MIN_CHAMADA_MS; senão devolve min(teto, o que resta). */
  reservar(teto: number): number {
    const r = this.resta();
    if (r < MIN_CHAMADA_MS) { this.estourou = true; throw new ErroAnuncio('sem_tempo'); }
    return Math.min(teto, r);
  }
}

/** buscar no prazo: confere antes e passa um AbortSignal limitado ao que resta (vale para cada página do lerPaginas). */
function buscarNoPrazo(buscar: Buscar, prazo: Prazo): Buscar {
  return (url, init) => {
    const ms = prazo.reservar(TIMEOUT_META_MS);
    return buscar(url, { ...init, signal: AbortSignal.timeout(ms) });
  };
}

/** Chamada ao banco (ou ao Storage) no prazo: confere antes e desiste quando o tempo acaba, mesmo se a chamada travar. */
async function noPrazo<T>(prazo: Prazo, teto: number, chamar: (ms: number) => Promise<T>): Promise<T> {
  const ms = prazo.reservar(teto);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const limite = new Promise<never>((_, rejeitar) => {
    timer = setTimeout(() => { prazo.estourou = true; rejeitar(new ErroAnuncio('sem_tempo')); }, ms);
  });
  try {
    return await Promise.race([chamar(ms), limite]);
  } finally {
    clearTimeout(timer);
  }
}

/** ErroMeta (de meta.ts, que chega por lerPaginas injetado) ou ErroAnuncio: os dois têm codigo string. */
const codigoDe = (e: unknown): string | null => {
  const c = (e as { codigo?: unknown } | null)?.codigo;
  return typeof c === 'string' ? c : null;
};

/**
 * Contas da flag que podem rodar agora: id só com dígitos, presente em meta_contas(), com token e com a coleta de
 * campanha ok nesta rodada. Flag nula ou vazia = nenhuma (desligada).
 */
export function contasDaFlag(flag: unknown, contas: ContaMeta[], resultados: Pick<ResultadoConta, 'conta' | 'ok'>[]): ContaMeta[] {
  if (typeof flag !== 'string' || !flag.trim()) return [];
  const pedidas = new Set(flag.split(',').map((x) => x.trim()).filter((x) => RE_ID.test(x)));
  const okNaRodada = new Set(resultados.filter((r) => r.ok).map((r) => r.conta));
  return contas.filter((c) => pedidas.has(c.conta_externa) && okNaRodada.has(c.conta_externa) && !!c.token);
}

export function urlInsightsAnuncio(versao: string, conta: string, de: string, ate: string, camposDistribuicao: string): string {
  const q = new URLSearchParams({
    level: 'ad',
    time_increment: '1',
    time_range: JSON.stringify({ since: de, until: ate }),
    fields: 'ad_id,ad_name,adset_id,adset_name,campaign_id,date_start,spend,impressions,clicks,inline_link_clicks,actions,'
      + camposDistribuicao,
    limit: '500',
  });
  return `${BASE}/${versao}/act_${encodeURIComponent(conta)}/insights?${q}`;
}

export const CAMPOS_CONJUNTO = 'id,name,effective_status,campaign_id,optimization_goal';
export const CAMPOS_ANUNCIO = 'id,name,effective_status,adset_id,campaign_id,creative{id,thumbnail_url,video_id,url_tags}';

/**
 * Status para o filtro do cadastro: a lista que o próprio Meta devolveu ao recusar um valor inválido em
 * /act_<conta>/adsets?effective_status=[...] (v23.0, 12/10/2026), MENOS DELETED: pedido no parâmetro effective_status
 * de /act_<conta>/ads, o Meta responde "A solicitação de objetos excluídos não é aceita neste ponto de extremidade"
 * (code 100, subcode 1815001). Anúncio ou conjunto apagado com gasto no período continua caindo no cadastro parcial.
 * A mesma lista serve às duas bordas. Atenção: dentro de filtering o Meta NÃO valida o valor (um status inexistente
 * voltou HTTP 200), por isso a lista sai do Meta e não de memória.
 */
export const STATUS_CADASTRO = [
  'ACTIVE', 'PAUSED', 'PENDING_REVIEW', 'DISAPPROVED', 'PREAPPROVED', 'PENDING_BILLING_INFO', 'CAMPAIGN_PAUSED', 'ARCHIVED',
  'ADSET_PAUSED', 'IN_PROCESS', 'WITH_ISSUES',
] as const;

/**
 * URLs do cadastro na conta (act_<conta>/adsets ou /ads) com filtering id IN em blocos de LOTE_IDS e todos os status de
 * STATUS_CADASTRO. Ids repetidos ou fora do padrão ficam de fora; conta fora do padrão = nenhuma URL.
 */
export function urlCadastro(versao: string, conta: string, borda: 'adsets' | 'ads', ids: string[], campos: string): string[] {
  if (!RE_ID.test(conta)) return [];
  const uniq = [...new Set(ids.map(String))].filter((x) => RE_ID.test(x));
  const out: string[] = [];
  for (let i = 0; i < uniq.length; i += LOTE_IDS) {
    const q = new URLSearchParams({
      fields: campos,
      filtering: JSON.stringify([
        { field: 'id', operator: 'IN', value: uniq.slice(i, i + LOTE_IDS) },
        { field: 'effective_status', operator: 'IN', value: STATUS_CADASTRO },
      ]),
      limit: String(LOTE_IDS),
    });
    out.push(`${BASE}/${versao}/act_${encodeURIComponent(conta)}/${borda}?${q}`);
  }
  return out;
}

/**
 * Lê todos os blocos pelo lerPaginas injetado (segue paging.next; cada página passa pelo buscar no prazo, com token só
 * no header e erro em código curto meta_<code>). O primeiro erro devolve o código e o que já foi lido (o resto sai dos
 * insights).
 */
async function lerCadastro<T>(d: DepsAnuncios, buscar: Buscar, urls: string[], token: string): Promise<{ lidos: T[]; erro?: string }> {
  const lidos: T[] = [];
  for (const u of urls) {
    try {
      lidos.push(...(await d.lerPaginas<T>(buscar, u, token)).filter((v) => v && typeof v === 'object'));
    } catch (e) {
      return { lidos, erro: codigoDe(e) ?? 'falha' };
    }
  }
  return { lidos };
}

const texto = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t ? t.slice(0, max) : null;
};

/** Conjuntos no formato de trafego_conjuntos_receber. O que não veio da busca de cadastro sai dos insights (parcial). */
export function paraConjuntos(lidos: ConjuntoMeta[], insights: InsightAnuncio[]): { linhas: LinhaConjunto[]; parciais: number } {
  const m = new Map<string, LinhaConjunto>();
  const campanhaDoInsight = new Map<string, string>();
  for (const i of insights) if (i.adset_id && i.campaign_id) campanhaDoInsight.set(String(i.adset_id), String(i.campaign_id));
  for (const c of lidos) {
    if (!c.id || !c.name || !RE_EXTERNA.test(String(c.id))) continue;
    const campanha = c.campaign_id ? String(c.campaign_id) : campanhaDoInsight.get(String(c.id));
    if (!campanha) continue;
    m.set(String(c.id), { plataforma: PLATAFORMA, campanha, id: String(c.id), nome: c.name,
      status: texto(c.effective_status, 40), meta_otimizacao: texto(c.optimization_goal, 60) });
  }
  let parciais = 0;
  for (const i of insights) {
    if (!i.adset_id || !i.adset_name || !i.campaign_id || m.has(String(i.adset_id)) || !RE_EXTERNA.test(String(i.adset_id))) continue;
    m.set(String(i.adset_id), { plataforma: PLATAFORMA, campanha: String(i.campaign_id), id: String(i.adset_id), nome: i.adset_name,
      status: null, meta_otimizacao: null });
    parciais++;
  }
  return { linhas: [...m.values()], parciais };
}

/**
 * Anúncios no formato de trafego_anuncios_receber, mais o mapa criativo -> thumbnail_url (só em memória, para baixar a
 * miniatura nesta rodada). O que não veio da busca de cadastro sai dos insights (parcial, sem criativo).
 */
export function paraAnuncios(lidos: AnuncioMeta[], insights: InsightAnuncio[]):
  { linhas: LinhaAnuncio[]; parciais: number; miniaturas: Map<string, string> } {
  const m = new Map<string, LinhaAnuncio>();
  const miniaturas = new Map<string, string>();
  const conjuntoDoInsight = new Map<string, string>();
  for (const i of insights) if (i.ad_id && i.adset_id) conjuntoDoInsight.set(String(i.ad_id), String(i.adset_id));
  for (const a of lidos) {
    if (!a.id || !a.name || !RE_EXTERNA.test(String(a.id))) continue;
    const conjunto = a.adset_id ? String(a.adset_id) : conjuntoDoInsight.get(String(a.id));
    if (!conjunto) continue;
    const cr = a.creative ?? {};
    const criativo = cr.id != null && RE_ID.test(String(cr.id)) ? String(cr.id) : null;
    const video = cr.video_id != null && RE_ID.test(String(cr.video_id)) ? String(cr.video_id) : null;
    const tags = typeof cr.url_tags === 'string' && cr.url_tags && cr.url_tags.length <= 2000 ? cr.url_tags : null;
    m.set(String(a.id), { plataforma: PLATAFORMA, conjunto, id: String(a.id), nome: a.name, status: texto(a.effective_status, 40),
      criativo, video_id: video, url_tags: tags });
    if (criativo && typeof cr.thumbnail_url === 'string' && cr.thumbnail_url) miniaturas.set(criativo, cr.thumbnail_url);
  }
  let parciais = 0;
  for (const i of insights) {
    if (!i.ad_id || !i.ad_name || !i.adset_id || m.has(String(i.ad_id)) || !RE_EXTERNA.test(String(i.ad_id))) continue;
    m.set(String(i.ad_id), { plataforma: PLATAFORMA, conjunto: String(i.adset_id), id: String(i.ad_id), nome: i.ad_name,
      status: null, criativo: null, video_id: null, url_tags: null });
    parciais++;
  }
  return { linhas: [...m.values()], parciais, miniaturas };
}

/**
 * Desempenho por anúncio no formato de trafego_desempenho_anuncio_receber: a MESMA conversão de métricas da coleta por
 * campanha (paraDesempenho de meta.ts, injetado), linha a linha, trocando campanha por anuncio. Sem ad_id = descartada.
 */
export function paraDesempenhoAnuncio(insights: InsightAnuncio[], paraDesempenho: DepsAnuncios['paraDesempenho']):
  { linhas: LinhaDesempenhoAnuncio[]; descartadas: number } {
  const linhas: LinhaDesempenhoAnuncio[] = [];
  let descartadas = 0;
  for (const i of insights) {
    if (!i.ad_id || !RE_EXTERNA.test(String(i.ad_id))) { descartadas++; continue; }
    const r = paraDesempenho([i]);
    if (!r.linhas.length) { descartadas++; continue; }
    const { campanha: _campanha, ...metricas } = r.linhas[0];
    linhas.push({ ...metricas, anuncio: String(i.ad_id) });
  }
  return { linhas, descartadas };
}

const comeca = (b: Uint8Array, sig: number[], desde = 0) => sig.every((x, k) => b[desde + k] === x);
/** Tipo pela assinatura dos bytes (nunca pelo content-type do servidor). */
export function tipoDaImagem(b: Uint8Array): { ext: 'jpg' | 'png' | 'webp'; mime: string } | null {
  if (comeca(b, [0xff, 0xd8, 0xff])) return { ext: 'jpg', mime: 'image/jpeg' };
  if (comeca(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return { ext: 'png', mime: 'image/png' };
  if (comeca(b, [0x52, 0x49, 0x46, 0x46]) && comeca(b, [0x57, 0x45, 0x42, 0x50], 8)) return { ext: 'webp', mime: 'image/webp' };
  return null;
}

/** Só https em *.fbcdn.net, sem porta nem usuário na URL. Qualquer outra coisa não é baixada (sem fetch). */
export function hostDeMiniaturaOk(url: string): boolean {
  let u: URL;
  try { u = new URL(url); } catch { return false; }
  return u.protocol === 'https:' && !u.port && !u.username && !u.password && u.hostname.endsWith('.fbcdn.net');
}

export type Miniatura = { ok: true; bytes: Uint8Array<ArrayBuffer>; ext: 'jpg' | 'png' | 'webp'; mime: string } | { ok: false; erro: string };

/** Baixa uma miniatura: sem redirect, até 10 s (ou ms, se menor), até 1 MB lido de fato (stream), tipo pelos bytes. Nunca lança. */
export async function baixarMiniatura(url: string, baixar: Baixar, ms: number = MINIATURA_DOWNLOAD_MS): Promise<Miniatura> {
  if (!hostDeMiniaturaOk(url)) return { ok: false, erro: 'miniatura_host' };
  let r: RespostaBinaria;
  try {
    r = await baixar(url, { redirect: 'error', signal: AbortSignal.timeout(Math.max(1, Math.min(MINIATURA_DOWNLOAD_MS, ms))) });
  } catch {
    return { ok: false, erro: 'miniatura_rede' };
  }
  if (!r.ok) {
    try { await r.body?.cancel(); } catch { /* sem corpo */ }
    return { ok: false, erro: `miniatura_http_${r.status}` };
  }
  const tamanho = Number(r.headers?.get('content-length') ?? '');
  if (Number.isFinite(tamanho) && tamanho > MINIATURA_MAX_BYTES) {
    try { await r.body?.cancel(); } catch { /* sem corpo */ }
    return { ok: false, erro: 'miniatura_grande' };
  }
  if (!r.body) return { ok: false, erro: 'miniatura_tipo' };
  const partes: Uint8Array[] = [];
  let total = 0;
  const leitor = r.body.getReader();
  try {
    for (;;) {
      const { done, value } = await leitor.read();
      if (done) break;
      total += value.byteLength;
      if (total > MINIATURA_MAX_BYTES) {
        try { await leitor.cancel(); } catch { /* já fechado */ }
        return { ok: false, erro: 'miniatura_grande' };
      }
      partes.push(value);
    }
  } catch {
    return { ok: false, erro: 'miniatura_rede' };
  }
  const bytes = new Uint8Array(total);
  let pos = 0;
  for (const p of partes) { bytes.set(p, pos); pos += p.byteLength; }
  const tipo = tipoDaImagem(bytes);
  if (!tipo) return { ok: false, erro: 'miniatura_tipo' };
  return { ok: true, bytes, ...tipo };
}

async function miniaturasDaConta(conta: string, pendentes: string[], urls: Map<string, string>, d: DepsAnuncios, prazo: Prazo):
  Promise<{ miniaturas: number; miniaturas_erro: number }> {
  const subir = d.subirMiniatura;
  if (!d.baixar || !subir || !pendentes.length) return { miniaturas: 0, miniaturas_erro: 0 };
  const saida: LinhaMiniatura[] = [];
  let ok = 0;
  let erros = 0;
  for (const criativo of pendentes.slice(0, MAX_MINIATURAS)) {
    if (prazo.resta() < CUSTO_MINIATURA_MS) break; // não cabe download + upload + folga: fica para a próxima rodada
    const url = urls.get(criativo);
    if (!url || !RE_ID.test(criativo)) continue; // sem URL nesta rodada (cadastro parcial): tenta na próxima
    const m = await baixarMiniatura(url, d.baixar, prazo.resta() - MIN_CHAMADA_MS);
    if (!m.ok) { saida.push({ criativo, erro: m.erro }); erros++; continue; }
    const caminho = `meta/${conta}/${criativo}.${m.ext}`;
    try {
      await noPrazo(prazo, MINIATURA_UPLOAD_MS, (ms) => subir(caminho, m.bytes, m.mime, ms));
      saida.push({ criativo, caminho });
      ok++;
    } catch {
      saida.push({ criativo, erro: 'miniatura_upload' });
      erros++;
    }
  }
  if (saida.length) {
    try { await noPrazo(prazo, TIMEOUT_BANCO_MS, (ms) => d.receberMiniaturas(saida, ms)); } catch { /* não derruba a conta; tenta de novo na próxima rodada */ }
  }
  return { miniaturas: ok, miniaturas_erro: erros };
}

async function coletarContaAnuncios(c: ContaMeta, d: DepsAnuncios, prazo: Prazo): Promise<ResultadoContaAnuncio> {
  const base = { conta: c.conta_externa };
  if (!c.token) return { ...base, ok: false, erro: 'sem_token' };
  const buscar = buscarNoPrazo(d.buscar, prazo);
  try {
    const insights = await d.lerPaginas<InsightAnuncio>(buscar,
      urlInsightsAnuncio(d.versao, c.conta_externa, d.de, d.ate, d.camposDistribuicao), c.token);
    const { linhas, descartadas } = paraDesempenhoAnuncio(insights, d.paraDesempenho);
    if (!linhas.length) return { ...base, ok: true, conjuntos: 0, anuncios: 0, linhas: 0, descartadas, recusas: 0, cadastro_parcial: 0,
      miniaturas: 0, miniaturas_erro: 0 };

    const idsConj = [...new Set(insights.map((i) => i.adset_id).filter((x): x is string => !!x).map(String))];
    const idsAnu = [...new Set(linhas.map((l) => l.anuncio))];
    const conjLidos = await lerCadastro<ConjuntoMeta>(d, buscar,
      urlCadastro(d.versao, c.conta_externa, 'adsets', idsConj, CAMPOS_CONJUNTO), c.token);
    if (prazo.estourou) throw new ErroAnuncio('sem_tempo');
    const conj = paraConjuntos(conjLidos.lidos, insights);
    let recusas = 0;
    for (let i = 0; i < conj.linhas.length; i += LOTE_ANUNCIO) {
      const lote = conj.linhas.slice(i, i + LOTE_ANUNCIO);
      const r = await noPrazo(prazo, TIMEOUT_BANCO_MS, (ms) => d.receberConjuntos(lote, ms));
      if (r?.ok === false) return { ...base, ok: false, erro: 'banco_conjuntos' };
      recusas += r?.recusas?.length ?? 0;
    }

    const anuLidos = await lerCadastro<AnuncioMeta>(d, buscar,
      urlCadastro(d.versao, c.conta_externa, 'ads', idsAnu, CAMPOS_ANUNCIO), c.token);
    if (prazo.estourou) throw new ErroAnuncio('sem_tempo');
    const anu = paraAnuncios(anuLidos.lidos, insights);
    const pendentes: string[] = [];
    for (let i = 0; i < anu.linhas.length; i += LOTE_ANUNCIO) {
      const lote = anu.linhas.slice(i, i + LOTE_ANUNCIO);
      const r = await noPrazo(prazo, TIMEOUT_BANCO_MS, (ms) => d.receberAnuncios(lote, ms));
      if (r?.ok === false) return { ...base, ok: false, erro: 'banco_anuncios' };
      recusas += r?.recusas?.length ?? 0;
      for (const p of r?.pendentes_miniatura ?? []) if (typeof p === 'string' && !pendentes.includes(p)) pendentes.push(p);
    }

    for (let i = 0; i < linhas.length; i += LOTE_ANUNCIO) {
      const lote = linhas.slice(i, i + LOTE_ANUNCIO);
      const r = await noPrazo(prazo, TIMEOUT_BANCO_MS, (ms) => d.receberDesempenhoAnuncio(lote, ms));
      if (r?.ok === false) return { ...base, ok: false, erro: 'banco_desempenho' };
      recusas += r?.recusas?.length ?? 0;
    }

    const mini = await miniaturasDaConta(c.conta_externa, pendentes, anu.miniaturas, d, prazo);
    const erroIds = conjLidos.erro ?? anuLidos.erro;
    return { ...base, ok: true, conjuntos: conj.linhas.length, anuncios: anu.linhas.length, linhas: linhas.length, descartadas,
      recusas, cadastro_parcial: conj.parciais + anu.parciais, ...(erroIds ? { cadastro_erro: erroIds } : {}), ...mini };
  } catch (e) {
    // fim da fase: o prazo recusou ou cortou a chamada (estourou), ou um timeout limitado ao que restava a abortou
    // (lerPaginas troca qualquer falha do buscar por 'rede'; por isso a conferência é pelo prazo, não pelo código)
    if (prazo.estourou || prazo.resta() < MIN_CHAMADA_MS) return { ...base, ok: false, erro: 'sem_tempo' };
    return { ...base, ok: false, erro: codigoDe(e) ?? 'banco' };
  }
}

/** Coleta por anúncio das contas da flag, uma a uma. Nunca lança: qualquer falha vira erro curto no resultado. */
export async function coletarAnuncios(contas: ContaMeta[], d: DepsAnuncios, agora: () => number = Date.now): Promise<ResultadoAnuncios> {
  const t0 = agora();
  const prazo = new Prazo(d.ate_ms, agora);
  const res: ResultadoContaAnuncio[] = [];
  let puladas = 0;
  for (const c of contas) {
    if (prazo.resta() < MIN_CHAMADA_MS) {
      res.push({ conta: c.conta_externa, ok: false, erro: 'sem_tempo' });
      puladas++;
      continue;
    }
    try {
      prazo.estourou = false; // cada conta começa limpa; o tempo que resta é o mesmo relógio
      res.push(await coletarContaAnuncios(c, d, prazo));
    } catch {
      res.push({ conta: c.conta_externa, ok: false, erro: 'falha' });
    }
  }
  return { ms: agora() - t0, puladas, contas: res };
}
