// trafego-clickup: a parte pura da leitura do ClickUp (migration 20261005r). Sem Deno, sem banco: testada no vitest com
// respostas simuladas (web/modules/marketing/trafego/infrastructure/coleta.test.ts, fixtures em
// infra/supabase/functions/_trafego-fixtures). SÓ LEITURA no ClickUp: um único endpoint GET, nunca escrita.
//
//   GET https://api.clickup.com/api/v2/team/<workspace>/task?tags[]=<etiqueta>&include_closed=true&subtasks=true&page=N
//   (100 tarefas por página; para em last_page ou página vazia)
//
// Para cada etiqueta de projeto (mkt.projetos.etiqueta_clickup dos projetos ativos), lê TODAS as páginas e só então
// manda o conjunto inteiro para public.trafego_clickup_receber (que tira a etiqueta de quem não veio). Se uma página
// falhar, aquela etiqueta não é gravada nessa rodada (o espelho fica como estava).
// Espelho mínimo: id, nome, status, datas, responsáveis (nome de usuário, sem e-mail), etiquetas, url.

const BASE = 'https://api.clickup.com/api/v2';

export interface TarefaClickupApi {
  id?: string; name?: string; status?: { status?: string } | null; url?: string;
  date_created?: string | null; date_updated?: string | null; start_date?: string | null; due_date?: string | null;
  date_done?: string | null; date_closed?: string | null;
  assignees?: { username?: string | null }[]; tags?: { name?: string }[];
}

export interface TarefaEspelho {
  id: string; nome: string; status: string | null; criada_em: string | null; atualizada_em: string | null;
  inicio: string | null; prazo: string | null; concluida_em: string | null; responsaveis: string[]; etiquetas: string[];
  url: string | null;
}

export function urlTarefas(team: string, etiqueta: string, pagina: number): string {
  const q = new URLSearchParams({ include_closed: 'true', subtasks: 'true', page: String(pagina), order_by: 'updated' });
  q.append('tags[]', etiqueta);
  return `${BASE}/team/${encodeURIComponent(team)}/task?${q}`;
}

/** O ClickUp manda datas como milissegundos em texto. */
export function msParaIso(v: string | number | null | undefined): string | null {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return null;
  const d = new Date(n);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

export function paraEspelho(t: TarefaClickupApi): TarefaEspelho | null {
  if (!t.id || !t.name) return null;
  return {
    id: String(t.id),
    nome: t.name,
    status: t.status?.status ?? null,
    criada_em: msParaIso(t.date_created),
    atualizada_em: msParaIso(t.date_updated),
    inicio: msParaIso(t.start_date),
    prazo: msParaIso(t.due_date),
    concluida_em: msParaIso(t.date_done ?? t.date_closed),
    responsaveis: (t.assignees ?? []).map((a) => a?.username ?? '').filter((u) => u.trim() !== ''),
    etiquetas: (t.tags ?? []).map((x) => (x?.name ?? '').toLowerCase()).filter((x) => x.trim() !== ''),
    url: t.url && t.url.startsWith('https://app.clickup.com/') ? t.url : null,
  };
}

type Buscar = (url: string, init?: { headers?: Record<string, string> }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export class ErroClickup extends Error {
  constructor(public codigo: string) { super(codigo); }
}

/** Todas as tarefas de uma etiqueta (todas as páginas) ou erro. */
export async function lerEtiqueta(buscar: Buscar, token: string, team: string, etiqueta: string, maxPaginas = 50): Promise<TarefaEspelho[]> {
  const todas: TarefaEspelho[] = [];
  for (let p = 0; p < maxPaginas; p++) {
    let r;
    try {
      r = await buscar(urlTarefas(team, etiqueta, p), { headers: { Authorization: token } });
    } catch {
      throw new ErroClickup('rede');
    }
    if (!r.ok) throw new ErroClickup(`http_${r.status}`);
    let corpo: { tasks?: TarefaClickupApi[]; last_page?: boolean };
    try {
      corpo = (await r.json()) as typeof corpo;
    } catch {
      throw new ErroClickup('json');
    }
    const tarefas = corpo.tasks ?? [];
    for (const t of tarefas) {
      const e = paraEspelho(t);
      if (e) todas.push(e);
    }
    if (corpo.last_page !== false || tarefas.length === 0) return todas;
  }
  throw new ErroClickup('paginas_demais');
}

export interface ResultadoEtiqueta { etiqueta: string; ok: boolean; erro?: string; tarefas?: number; removidas?: number; recusas?: number }

export interface DepsClickup {
  buscar: Buscar;
  token: string;
  team: string;
  receber: (payload: { etiqueta: string; tarefas: TarefaEspelho[] }) => Promise<{ ok?: boolean; removidas?: number; recusas?: unknown[] }>;
}

export async function coletarClickup(etiquetas: string[], d: DepsClickup): Promise<ResultadoEtiqueta[]> {
  const res: ResultadoEtiqueta[] = [];
  for (const etiqueta of etiquetas) {
    try {
      const tarefas = await lerEtiqueta(d.buscar, d.token, d.team, etiqueta);
      const r = await d.receber({ etiqueta, tarefas });
      if (r?.ok === false) { res.push({ etiqueta, ok: false, erro: 'banco' }); continue; }
      res.push({ etiqueta, ok: true, tarefas: tarefas.length, removidas: r?.removidas ?? 0, recusas: r?.recusas?.length ?? 0 });
    } catch (e) {
      res.push({ etiqueta, ok: false, erro: e instanceof ErroClickup ? e.codigo : 'falha' });
    }
  }
  return res;
}

// ─── Etiquetas reais dos spaces (20261006a): para a tela escolher a etiqueta do projeto em vez de digitar ──────────
//   GET https://api.clickup.com/api/v2/team/<workspace>/space?archived=false   → { spaces: [{ id }] }
//   GET https://api.clickup.com/api/v2/space/<space>/tag                        → { tags: [{ name }] }
// Só leitura. Uma falha em qualquer chamada = erro (a lista no banco fica como estava).

export const urlSpaces = (team: string) => `${BASE}/team/${encodeURIComponent(team)}/space?archived=false`;
export const urlTagsSpace = (space: string) => `${BASE}/space/${encodeURIComponent(space)}/tag`;

async function getJson(buscar: Buscar, token: string, url: string): Promise<unknown> {
  let r;
  try {
    r = await buscar(url, { headers: { Authorization: token } });
  } catch {
    throw new ErroClickup('rede');
  }
  if (!r.ok) throw new ErroClickup(`http_${r.status}`);
  try {
    return await r.json();
  } catch {
    throw new ErroClickup('json');
  }
}

/** Todas as etiquetas (em minúsculas, sem repetição, em ordem) dos spaces não arquivados do workspace. */
export async function lerEtiquetasDosSpaces(buscar: Buscar, token: string, team: string): Promise<string[]> {
  const sp = (await getJson(buscar, token, urlSpaces(team))) as { spaces?: { id?: string | number }[] };
  const nomes = new Set<string>();
  for (const s of sp.spaces ?? []) {
    if (s?.id == null) continue;
    const tg = (await getJson(buscar, token, urlTagsSpace(String(s.id)))) as { tags?: { name?: string }[] };
    for (const t of tg.tags ?? []) {
      const n = (t?.name ?? '').trim().toLowerCase();
      if (n) nomes.add(n);
    }
  }
  return [...nomes].sort();
}
