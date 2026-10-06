// trafego-meta: a parte pura da coleta Meta Ads (migration 20261005r). Sem Deno, sem banco: testada no vitest com
// respostas simuladas (web/modules/marketing/trafego/infrastructure/coleta.test.ts, fixtures em
// infra/supabase/functions/_trafego-fixtures). O index.ts liga isto ao banco e ao Deno.serve.
//
// O que lê da Graph API (só leitura), por conta de anúncio ativa de mkt_trafego.contas (plataforma meta):
//   GET /act_<conta>/campaigns?fields=id,name,effective_status        (nome EXATO e status de cada campanha)
//   GET /act_<conta>/insights?level=campaign&time_increment=1&time_range={since,until}
//       &fields=campaign_id,campaign_name,date_start,spend,impressions,clicks,inline_link_clicks,actions
// e grava pelas funções de entrada da 20261005p, no formato delas:
//   trafego_campanhas_receber   [{plataforma, conta, id, nome, status}]
//   trafego_desempenho_receber  [{plataforma, campanha, dia, gasto, impressoes, cliques_link, cliques_total, leads}]
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
}
export interface LinhaCampanha { plataforma: 'meta'; conta: string; id: string; nome: string; status: string | null }
export interface LinhaDesempenho {
  plataforma: 'meta'; campanha: string; dia: string; gasto: number; impressoes: number; cliques_link: number;
  cliques_total: number | null; leads: number | null;
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
    fields: 'campaign_id,campaign_name,date_start,spend,impressions,clicks,inline_link_clicks,actions',
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
    });
  }
  return { linhas, descartadas };
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
}

export interface DepsMeta {
  buscar: Buscar;
  versao: string;
  de: string;
  ate: string;
  receberCampanhas: (linhas: LinhaCampanha[]) => Promise<{ ok?: boolean; recusas?: unknown[] }>;
  receberDesempenho: (linhas: LinhaDesempenho[]) => Promise<{ ok?: boolean; recusas?: unknown[] }>;
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
    return { ...base, ok: true, campanhas: lc.length, linhas: linhas.length, descartadas, recusas_campanhas: recC, recusas_desempenho: recD };
  } catch (e) {
    return { ...base, ok: false, erro: e instanceof ErroMeta ? e.codigo : 'falha' };
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
