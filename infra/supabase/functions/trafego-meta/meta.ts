// trafego-meta: a parte pura da coleta Meta Ads (migration 20261006i). Sem Deno, sem banco: testada no vitest com
// respostas simuladas (web/modules/marketing/trafego/infrastructure/coleta.test.ts, fixtures em
// infra/supabase/functions/_trafego-fixtures). O index.ts liga isto ao banco e ao Deno.serve.
//
// O que lê da Graph API (só leitura), por conta de anúncio ativa de mkt_trafego.contas (plataforma meta):
//   GET /act_<conta>/campaigns?fields=id,name,effective_status        (nome EXATO e status de cada campanha)
//   GET /act_<conta>/insights?level=campaign&time_increment=1&time_range={since,until}
//       &fields=campaign_id,campaign_name,date_start,spend,impressions,clicks,inline_link_clicks,actions
//               + (20261009230000) reach,frequency,outbound_clicks,video_play_actions,video_thruplay_watched_actions,
//                 video_p25/p50/p75/p100_watched_actions (post_engagement e landing_page_view vêm de actions)
//   GET /act_<conta>/insights?level=campaign&date_preset=maximum&filtering=[campaign.id IN ...] (20261009230000)
//       &fields=campaign_id,date_start,date_stop,spend,impressions,reach,frequency
//       alcance e frequência do período INTEIRO de cada campanha que gastou (alcance não soma por dia). Falha aqui não
//       derruba a conta: vira totais_erro no resultado e o desempenho diário segue gravado.
// e grava pelas funções de entrada da 20261006g, no formato delas:
//   trafego_campanhas_receber   [{plataforma, conta, id, nome, status}]
//   trafego_desempenho_receber  [{plataforma, campanha, dia, gasto, impressoes, cliques_link, cliques_total, leads,
//                                 + alcance, frequencia, cliques_saida, landing_page_views, engajamento, video_*}]
//   trafego_desempenho_total_receber [{plataforma, campanha, de, ate, gasto, impressoes, alcance, frequencia}]
// Métrica nova que a API não mandar fica null (sem dado), nunca 0.
// cliques_link = inline_link_clicks (o clique do CTR, do CPC e do connect rate, decisão do Victor); cliques_total =
// clicks (só informação); leads = a ação "lead" que o Meta informa (só informação; o lead da Central é o da base).
// Token: no header Authorization (nunca na URL que a gente monta, nunca no registro). Vem do Vault (meta_ads_token da
// conta centralizadora, ou o segredo da própria conta em contas.token_vault): quem escolhe é o Victor.

export const META_API_VERSAO_PADRAO = 'v23.0';
export const PLATAFORMA = 'meta';
const BASE = 'https://graph.facebook.com';
/** Ação do Meta que vira leads_plataforma. */
export const ACAO_LEAD = 'lead';
const LOTE_DESEMPENHO = 5000;

export interface ContaMeta { conta_externa: string; nome: string; token: string | null; token_origem: string }
export interface CampanhaMeta { id?: string; name?: string; effective_status?: string }
export interface InsightMeta {
  campaign_id?: string; campaign_name?: string; date_start?: string; spend?: string; impressions?: string;
  clicks?: string; inline_link_clicks?: string; actions?: { action_type?: string; value?: string }[];
  date_stop?: string; reach?: string; frequency?: string;
  outbound_clicks?: Acao[]; video_play_actions?: Acao[]; video_thruplay_watched_actions?: Acao[];
  video_p25_watched_actions?: Acao[]; video_p50_watched_actions?: Acao[]; video_p75_watched_actions?: Acao[];
  video_p100_watched_actions?: Acao[];
}
type Acao = { action_type?: string; value?: string };
export interface LinhaCampanha { plataforma: 'meta'; conta: string; id: string; nome: string; status: string | null }
export interface LinhaDesempenho {
  plataforma: 'meta'; campanha: string; dia: string; gasto: number; impressoes: number; cliques_link: number;
  cliques_total: number | null; leads: number | null;
  // 20261009230000: métricas de distribuição de conteúdo (null = a API não mandou)
  alcance: number | null; frequencia: number | null; cliques_saida: number | null; landing_page_views: number | null;
  engajamento: number | null; video_plays: number | null; video_thruplay: number | null;
  video_p25: number | null; video_p50: number | null; video_p75: number | null; video_p100: number | null;
}
export interface LinhaTotal {
  plataforma: 'meta'; campanha: string; de: string; ate: string; gasto: number | null; impressoes: number | null;
  alcance: number | null; frequencia: number | null;
}

/** Dia de hoje em São Paulo (AAAA-MM-DD). */
export function hojeSaoPaulo(agora: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(agora);
}

function somaDias(ymd: string, n: number): string {
  const d = new Date(`${ymd}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const RE_DIA = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Período da leitura: os `dias` dias completos antes de hoje e hoje (o Meta ainda ajusta os últimos dias).
 * dias = 0 lê só hoje. `de`/`ate` explícitos (recarga) valem se forem datas válidas, de <= ate e até 92 dias.
 */
export function periodo(hoje: string, dias: number, de?: string | null, ate?: string | null): { de: string; ate: string } | null {
  if (de || ate) {
    if (!de || !ate || !RE_DIA.test(de) || !RE_DIA.test(ate) || de > ate || ate > hoje) return null;
    const n = Math.round((Date.parse(ate) - Date.parse(de)) / 86400000);
    return n > 92 ? null : { de, ate };
  }
  const d = Number.isFinite(dias) ? Math.min(Math.max(Math.trunc(dias), 0), 30) : 3;
  return { de: somaDias(hoje, -d), ate: hoje };
}

export function urlCampanhas(versao: string, conta: string): string {
  const q = new URLSearchParams({ fields: 'id,name,effective_status', limit: '500' });
  return `${BASE}/${versao}/act_${encodeURIComponent(conta)}/campaigns?${q}`;
}

export function urlInsights(versao: string, conta: string, de: string, ate: string): string {
  const q = new URLSearchParams({
    level: 'campaign',
    time_increment: '1',
    time_range: JSON.stringify({ since: de, until: ate }),
    fields: 'campaign_id,campaign_name,date_start,spend,impressions,clicks,inline_link_clicks,actions,' + CAMPOS_DISTRIBUICAO,
    limit: '500',
  });
  return `${BASE}/${versao}/act_${encodeURIComponent(conta)}/insights?${q}`;
}

/** 20261009230000: campos de distribuição de conteúdo (conferidos na v23.0 em 09/10/2026). */
export const CAMPOS_DISTRIBUICAO = 'reach,frequency,outbound_clicks,video_play_actions,video_thruplay_watched_actions,'
  + 'video_p25_watched_actions,video_p50_watched_actions,video_p75_watched_actions,video_p100_watched_actions';
/** Ids por leitura do total (filtro campaign.id IN). */
export const LOTE_TOTAIS = 50;

/** Total do período inteiro de cada campanha (date_preset=maximum): alcance e frequência sem somar dias. */
export function urlTotais(versao: string, conta: string, campanhas: string[]): string {
  const q = new URLSearchParams({
    level: 'campaign',
    date_preset: 'maximum',
    filtering: JSON.stringify([{ field: 'campaign.id', operator: 'IN', value: campanhas }]),
    fields: 'campaign_id,date_start,date_stop,spend,impressions,reach,frequency',
    limit: '500',
  });
  return `${BASE}/${versao}/act_${encodeURIComponent(conta)}/insights?${q}`;
}

const inteiro = (v: unknown): number | null => {
  if (v == null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n) : null;
};
const dinheiro = (v: unknown): number | null => {
  if (v == null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : null;
};

const decimal = (v: unknown): number | null => {
  if (v == null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 10000) / 10000 : null;
};
/** Valor de uma ação numa lista do Meta; sem a ação (ou sem a lista) = null. tipo nulo = soma da lista inteira. */
export function acao(lista: Acao[] | undefined, tipo: string | null): number | null {
  if (!Array.isArray(lista) || !lista.length) return null;
  const xs = tipo == null ? lista : lista.filter((x) => x?.action_type === tipo);
  if (!xs.length) return null;
  let t = 0;
  for (const x of xs) { const v = inteiro(x?.value); if (v == null) return null; t += v; }
  return t;
}

/** Leads que o Meta informa (ação "lead"); sem a ação = null (a plataforma não informou). */
export function leadsDasAcoes(acoes: InsightMeta['actions']): number | null {
  const a = (acoes ?? []).find((x) => x?.action_type === ACAO_LEAD);
  return a ? inteiro(a.value) : null;
}

/** Linhas de desempenho no formato de trafego_desempenho_receber. Linha sem campanha, dia ou gasto válido é descartada. */
export function paraDesempenho(insights: InsightMeta[]): { linhas: LinhaDesempenho[]; descartadas: number } {
  const linhas: LinhaDesempenho[] = [];
  let descartadas = 0;
  for (const i of insights) {
    const gasto = dinheiro(i.spend);
    if (!i.campaign_id || !i.date_start || !RE_DIA.test(i.date_start) || gasto == null) { descartadas++; continue; }
    linhas.push({
      plataforma: PLATAFORMA, campanha: String(i.campaign_id), dia: i.date_start, gasto,
      impressoes: inteiro(i.impressions) ?? 0,
      cliques_link: inteiro(i.inline_link_clicks) ?? 0,
      cliques_total: inteiro(i.clicks),
      leads: leadsDasAcoes(i.actions),
      alcance: inteiro(i.reach),
      frequencia: decimal(i.frequency),
      cliques_saida: acao(i.outbound_clicks, 'outbound_click'),
      landing_page_views: acao(i.actions, 'landing_page_view'),
      engajamento: acao(i.actions, 'post_engagement'),
      video_plays: acao(i.video_play_actions, null),
      video_thruplay: acao(i.video_thruplay_watched_actions, null),
      video_p25: acao(i.video_p25_watched_actions, null),
      video_p50: acao(i.video_p50_watched_actions, null),
      video_p75: acao(i.video_p75_watched_actions, null),
      video_p100: acao(i.video_p100_watched_actions, null),
    });
  }
  return { linhas, descartadas };
}

/** Totais do período inteiro no formato de trafego_desempenho_total_receber. Sem campanha ou datas válidas descarta. */
export function paraTotais(insights: InsightMeta[]): LinhaTotal[] {
  const out: LinhaTotal[] = [];
  for (const i of insights) {
    if (!i.campaign_id || !i.date_start || !i.date_stop || !RE_DIA.test(i.date_start) || !RE_DIA.test(i.date_stop)) continue;
    out.push({ plataforma: PLATAFORMA, campanha: String(i.campaign_id), de: i.date_start, ate: i.date_stop,
      gasto: dinheiro(i.spend), impressoes: inteiro(i.impressions), alcance: inteiro(i.reach), frequencia: decimal(i.frequency) });
  }
  return out;
}

/**
 * Campanhas no formato de trafego_campanhas_receber: as da lista da conta e, se alguma só aparecer nos insights
 * (apagada ou arquivada depois de gastar), com o nome dos insights e status nulo. Nome sempre EXATO.
 */
export function paraCampanhas(conta: string, campanhas: CampanhaMeta[], insights: InsightMeta[]): LinhaCampanha[] {
  const m = new Map<string, LinhaCampanha>();
  for (const c of campanhas) {
    if (!c.id || !c.name) continue;
    m.set(String(c.id), { plataforma: PLATAFORMA, conta, id: String(c.id), nome: c.name, status: c.effective_status ?? null });
  }
  for (const i of insights) {
    if (!i.campaign_id || !i.campaign_name || m.has(String(i.campaign_id))) continue;
    m.set(String(i.campaign_id), { plataforma: PLATAFORMA, conta, id: String(i.campaign_id), nome: i.campaign_name, status: null });
  }
  return [...m.values()];
}

export class ErroMeta extends Error {
  constructor(public codigo: string) { super(codigo); }
}

type Buscar = (url: string, init?: { headers?: Record<string, string>; signal?: AbortSignal }) => Promise<{
  ok: boolean; status: number; json(): Promise<unknown>;
}>;

/** Lê todas as páginas (paging.next) de uma leitura da Graph API. Erro vira ErroMeta com código curto (sem mensagem). */
export async function lerPaginas<T>(buscar: Buscar, url: string, token: string, maxPaginas = 40): Promise<T[]> {
  const todos: T[] = [];
  let proxima: string | null = url;
  for (let n = 0; proxima && n < maxPaginas; n++) {
    let r;
    try {
      r = await buscar(proxima, { headers: { Authorization: `Bearer ${token}` } });
    } catch {
      throw new ErroMeta('rede');
    }
    let corpo: { data?: T[]; paging?: { next?: string }; error?: { code?: number; error_subcode?: number } };
    try {
      corpo = (await r.json()) as typeof corpo;
    } catch {
      throw new ErroMeta(`http_${r.status}`);
    }
    if (!r.ok || corpo?.error) {
      const c = corpo?.error?.code;
      throw new ErroMeta(c != null ? `meta_${c}${corpo?.error?.error_subcode ? `_${corpo.error.error_subcode}` : ''}` : `http_${r.status}`);
    }
    todos.push(...(corpo.data ?? []));
    proxima = corpo.paging?.next ?? null;
    if (proxima && !proxima.startsWith(`${BASE}/`)) throw new ErroMeta('paginacao');
  }
  if (proxima) throw new ErroMeta('paginas_demais');
  return todos;
}

export interface ResultadoConta {
  conta: string; token_origem: string; ok: boolean; erro?: string;
  campanhas?: number; linhas?: number; descartadas?: number; recusas_campanhas?: number; recusas_desempenho?: number;
  totais?: number; totais_erro?: string;
}

export interface DepsMeta {
  buscar: Buscar;
  versao: string;
  de: string;
  ate: string;
  receberCampanhas: (linhas: LinhaCampanha[]) => Promise<{ ok?: boolean; recusas?: unknown[] }>;
  receberDesempenho: (linhas: LinhaDesempenho[]) => Promise<{ ok?: boolean; recusas?: unknown[] }>;
  /** 20261009230000: totais do período inteiro (opcional; sem ele a leitura dos totais não é feita). */
  receberTotais?: (linhas: LinhaTotal[]) => Promise<{ ok?: boolean; recusas?: unknown[] }>;
  /** Para de começar conta nova depois deste instante (ms). */
  ate_ms?: number;
}

/** Coleta uma conta: campanhas, insights, grava campanhas ANTES do desempenho (o desempenho precisa da campanha). */
export async function coletarConta(c: ContaMeta, d: DepsMeta): Promise<ResultadoConta> {
  const base = { conta: c.conta_externa, token_origem: c.token_origem };
  if (!c.token) return { ...base, ok: false, erro: 'sem_token' };
  try {
    const campanhas = await lerPaginas<CampanhaMeta>(d.buscar, urlCampanhas(d.versao, c.conta_externa), c.token);
    const insights = await lerPaginas<InsightMeta>(d.buscar, urlInsights(d.versao, c.conta_externa, d.de, d.ate), c.token);
    const lc = paraCampanhas(c.conta_externa, campanhas, insights);
    const { linhas, descartadas } = paraDesempenho(insights);
    let recC = 0;
    let recD = 0;
    if (lc.length) {
      const r = await d.receberCampanhas(lc);
      if (r?.ok === false) return { ...base, ok: false, erro: 'banco_campanhas' };
      recC = r?.recusas?.length ?? 0;
    }
    for (let i = 0; i < linhas.length; i += LOTE_DESEMPENHO) {
      const r = await d.receberDesempenho(linhas.slice(i, i + LOTE_DESEMPENHO));
      if (r?.ok === false) return { ...base, ok: false, erro: 'banco_desempenho' };
      recD += r?.recusas?.length ?? 0;
    }
    // sem tempo (orçamento ate_ms passou), não lê os totais: a Edge morre em 150 s e não registraria a coleta (pentester)
    const semTempo = d.ate_ms != null && Date.now() > d.ate_ms;
    const extra = !d.receberTotais || !linhas.length ? {}
      : semTempo ? { totais_erro: 'sem_tempo' }
      : await totaisDaConta(c, d, [...new Set(linhas.map((l) => l.campanha))]);
    return { ...base, ok: true, campanhas: lc.length, linhas: linhas.length, descartadas, recusas_campanhas: recC, recusas_desempenho: recD, ...extra };
  } catch (e) {
    return { ...base, ok: false, erro: e instanceof ErroMeta ? e.codigo : 'falha' };
  }
}

/** Alcance e frequência do período inteiro das campanhas que gastaram. Nunca derruba a conta: erro vira totais_erro. */
async function totaisDaConta(c: ContaMeta, d: DepsMeta, ids: string[]): Promise<{ totais?: number; totais_erro?: string }> {
  try {
    let n = 0;
    for (let i = 0; i < ids.length; i += LOTE_TOTAIS) {
      const ins = await lerPaginas<InsightMeta>(d.buscar, urlTotais(d.versao, c.conta_externa, ids.slice(i, i + LOTE_TOTAIS)), c.token!);
      const lt = paraTotais(ins);
      if (lt.length) {
        const r = await d.receberTotais!(lt);
        if (r?.ok === false) return { totais: n, totais_erro: 'banco_totais' };
        n += lt.length;
      }
    }
    return { totais: n };
  } catch (e) {
    return { totais_erro: e instanceof ErroMeta ? e.codigo : 'falha' };
  }
}

export interface ResultadoMeta { de: string; ate: string; contas: ResultadoConta[]; puladas: number }

/** Coleta as contas uma a uma (a Graph API limita por conta; uma falha não para as outras). */
export async function coletarMeta(contas: ContaMeta[], d: DepsMeta, agora: () => number = Date.now): Promise<ResultadoMeta> {
  const res: ResultadoConta[] = [];
  let puladas = 0;
  for (const c of contas) {
    if (d.ate_ms != null && agora() > d.ate_ms) { puladas++; continue; }
    res.push(await coletarConta(c, d));
  }
  return { de: d.de, ate: d.ate, contas: res, puladas };
}
