// respondi-sync — sincronização diária Respondi → respondi.* → ficha do aluno (migration 20261004f).
// Caminho canônico; o Python de infra/scripts/respondi fica para carga manual/acervo completo.
// API interna do painel (sem API pública). `PUT team/switch` troca o workspace ATIVO DA CONTA no servidor:
// por isso um time por vez, execução única (linha 'em_curso' em respondi.sync_execucoes) e volta para 160 no finally.
// Só baixa formulário cujo respondents_count difere do n_respostas gravado; n_respostas novo só é gravado com o
// formulário baixado até o fim (o que estourar o orçamento fica em `pendentes` e volta no dia seguinte).
// Chamada: POST com header x-sync-chave (= Vault respondi_sync_chave). Quem chama é o cron respondi-sync.
import postgres from "npm:postgres@3.4.4";
import { familia, formulario, resposta } from "./normaliza.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const API = "https://api.respondi.app/api/";
const TIMES = [160, 161, 162, 3380, 574];
const ORCAMENTO_MS = 110_000; // não começa página nova depois disso
const PRAZO_REDE_MS = 125_000; // nenhuma chamada ao Respondi passa daqui: sobram ~25 s (volta ao 160, casar, aplicar) dos 150 s
const RQ_MAX_MS = 30_000;
const LOTE = 500;
const QUEDA_MAX = 0.02; // trava: casadas não pode cair mais que 2% em relação à última execução ok
const CRED_TTL_MS = 600_000;
type Obj = Record<string, any>;

// Saída de erro passa SEMPRE por aqui: sem token, senha, e-mail ou sequência longa de dígitos (CPF/telefone).
export function semSegredo(v: unknown): string {
  return String(v)
    .replace(/\b(Bearer)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***")
    .replace(/eyJ[A-Za-z0-9._-]{10,}/g, "***")
    .replace(/("?(password|senha|token|access_token)"?\s*[:=]\s*)"?[^"\s,}]*/gi, "$1***")
    .replace(/[^\s"'<>@]+@[^\s"'<>@]+/g, "***@***")
    .replace(/\d[\d.\-\s]{8,}\d/g, "***");
}

// Credencial em cache no isolate: chamada sem chave não abre conexão no banco a cada request.
let credCache: { email: string | null; senha: string | null; chave: string | null; ate: number } | null = null;
async function credenciais() {
  if (credCache && credCache.ate > Date.now()) return credCache;
  const [r] = await sql`select email, senha, chave from respondi.sync_credenciais()`;
  credCache = { email: r?.email ?? null, senha: r?.senha ?? null, chave: r?.chave ?? null, ate: Date.now() + CRED_TTL_MS };
  return credCache;
}
function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
const espera = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
class SemPrazo extends Error {}
class Trava extends Error {}

// Erro nunca leva corpo da resposta nem query: só método, rota sem query e status.
// `ate` = instante absoluto (ms) até onde a chamada pode ir; timeout = o que sobra, no máximo 30 s; sem retry se não couber.
async function rq(ate: number, jwt: string | null, metodo: string, caminho: string, corpo?: Obj): Promise<Obj> {
  const rota = `${metodo} ${caminho.split("?")[0].replace(/\/[^/]+$/, "/…")}`;
  const headers: Record<string, string> = { Accept: "application/json", "User-Agent": "Mozilla/5.0" };
  if (jwt) headers.Authorization = `Bearer ${jwt}`;
  if (corpo) headers["Content-Type"] = "application/json";
  for (let t = 0; ; t++) {
    const resta = ate - Date.now();
    if (resta < 1000) throw new SemPrazo(`${rota}: orçamento esgotado`);
    const pausa = 2000 * (t + 1);
    const tentaDeNovo = t < 2 && resta - pausa > 3000;
    let r: Response;
    try {
      r = await fetch(API + caminho, { method: metodo, headers, body: corpo ? JSON.stringify(corpo) : undefined,
        signal: AbortSignal.timeout(Math.min(RQ_MAX_MS, resta)) });
    } catch {
      if (!tentaDeNovo) throw (ate - Date.now() < 1000 ? new SemPrazo(`${rota}: orçamento esgotado`) : new Error(`${rota}: falha de rede`));
      await espera(pausa);
      continue;
    }
    if ((r.status === 429 || r.status >= 500) && tentaDeNovo) { await r.body?.cancel(); await espera(pausa); continue; }
    if (!r.ok) { await r.body?.cancel(); throw new Error(`${rota} HTTP ${r.status}`); }
    return await r.json().catch(() => ({}));
  }
}

async function login(ate: number, email: string, senha: string): Promise<string> {
  const d = await rq(ate, null, "POST", "auth/login", { email, password: senha });
  const t = d?.access_token ?? d?.token ?? d?.data?.access_token ?? d?.data?.token;
  if (typeof t !== "string" || !t) throw new Error("login Respondi sem token na resposta");
  return t;
}

async function listar(ate: number, jwt: string): Promise<Obj[]> {
  const todos: Obj[] = [];
  for (let p = 1; p <= 100; p++) {
    const d = await rq(ate, jwt, "GET", `form?page=${p}`);
    todos.push(...(d.data ?? []));
    if (!d.next_page_url) break;
  }
  return todos;
}

const carga = async (forms: Obj[], resps: Obj[]) =>
  (await sql`select public.fn_respondi_carga(${sql.json(forms)}::jsonb, ${sql.json(resps)}::jsonb) v`)[0].v as Obj;

// Baixa um formulário inteiro (ou até o orçamento / limite de páginas). true = concluído (n_respostas gravado).
async function baixar(jwt: string, f: Obj, time: number, fam: string, n: number, existe: boolean, t0: number, out: Obj) {
  const { linha, flds, tc } = formulario(f, time, fam, n);
  if (!existe) await carga([{ ...linha, n_respostas: 0 }], []); // FK das respostas; n=0 até concluir
  const lote = new Map<string, Obj>(); // por uuid: ON CONFLICT não aceita a mesma chave duas vezes no lote
  const descarrega = async () => {
    if (!lote.size) return;
    out.respostas_gravadas += Number((await carga([], [...lote.values()])).respostas ?? 0);
    lote.clear();
  };
  let limite = Infinity; // definido pela 1ª página
  for (let p = 1; ; p++) {
    if (Date.now() - t0 > ORCAMENTO_MS) { await descarrega(); return false; }
    if (p > limite) { // a API continuaria paginando além de respondents_count: não confia, fica pendente
      await descarrega();
      console.error("respondi-sync limite de páginas", f.slug, limite);
      return false;
    }
    let d: Obj;
    try { d = await rq(t0 + PRAZO_REDE_MS, jwt, "GET", `answers/form/${encodeURIComponent(f.slug)}?page=${p}&completed=1`); }
    catch (e) { if (e instanceof SemPrazo) { await descarrega(); return false; } throw e; }
    const rs: Obj[] = d?.data?.respondents ?? [];
    if (p === 1) {
      const pp = Number(d?.data?.per_page ?? d?.per_page) || 0;
      limite = pp > 0 ? Math.ceil(n / pp) + 2 : Math.ceil(n / Math.max(1, rs.length)) * 2 + 2;
    }
    if (!rs.length) break;
    for (const r of rs) {
      const l = resposta(r, f.slug, flds, fam, tc);
      if (l) lote.set(String(l.uuid), l);
      if (lote.size >= LOTE) await descarrega();
    }
  }
  await descarrega();
  await carga([linha], []);
  return true;
}

async function fechar(id: number, status: string, out: Obj, t0: number, motivo: string | null) {
  await sql`update respondi.sync_execucoes
               set status = ${status}, terminada_em = now(), casadas = ${out.casadas ?? null}, baixados = ${out.baixados},
                   respostas = ${out.respostas_gravadas}, pendentes = ${sql.json(out.pendentes)}::jsonb,
                   ms = ${Date.now() - t0}, motivo = ${motivo}
             where id = ${id}`;
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  let exec: number | null = null;
  const out: Obj = { execucao: null, formularios_vistos: 0, baixados: 0, respostas_gravadas: 0, casar: null, casadas: null,
    aplicar: null, a_confirmar: null, pendentes: [] as string[], ms: 0 };
  try {
    const cred = await credenciais();
    // fail-closed: sem chave no Vault, ninguém entra.
    if (!cred.chave || !igual(req.headers.get("x-sync-chave") ?? "", cred.chave)) return json({ erro: "não autorizado" }, 401);
    if (!cred.email || !cred.senha) return json({ erro: "credencial ausente" }, 503);

    // Execução única: índice único parcial em status='em_curso'. Funciona atrás do pooler (não depende de sessão).
    await sql`update respondi.sync_execucoes set status = 'erro', terminada_em = now(), motivo = 'expirada: em curso há mais de 10 min'
               where status = 'em_curso' and iniciada_em < now() - interval '10 minutes'`;
    const [ins] = await sql`insert into respondi.sync_execucoes (status) values ('em_curso') on conflict do nothing returning id`;
    if (!ins) return json({ erro: "execução em curso" }, 409);
    exec = Number(ins.id);
    out.execucao = exec;

    const banco = new Map<string, number>((await sql`select slug, n_respostas from respondi.formularios`)
      .map((r) => [r.slug as string, Number(r.n_respostas)]));

    let jwt: string;
    try { jwt = await login(t0 + PRAZO_REDE_MS, cred.email, cred.senha); } catch (e) {
      const m = semSegredo(e).slice(0, 200);
      console.error("respondi-sync login", m);
      await fechar(exec, "erro", out, t0, `login Respondi falhou: ${m}`);
      exec = null;
      return json({ erro: "login Respondi falhou" }, 502);
    }
    try {
      for (const time of TIMES) {
        let forms: { f: Obj; fam: string | null; n: number }[];
        try {
          await rq(t0 + PRAZO_REDE_MS, jwt, "PUT", `team/switch/${time}`);
          forms = (await listar(t0 + PRAZO_REDE_MS, jwt))
            .map((f) => ({ f, fam: familia(String(f.name ?? "")), n: Number(f.respondents_count) || 0 }))
            .filter((x) => x.fam && x.f.draft_of == null && x.n > 0 && x.f.slug)
            .sort((a, b) => a.n - b.n); // menores primeiro: um formulário gigante não segura os outros
        } catch (e) {
          if (!(e instanceof SemPrazo)) throw e;
          out.pendentes.push(`time:${time}`); // orçamento acabou antes de listar: o time volta amanhã
          continue;
        }
        for (const { f, fam, n } of forms) {
          out.formularios_vistos++;
          if (banco.get(f.slug) === n) continue;
          if (Date.now() - t0 > ORCAMENTO_MS) { out.pendentes.push(f.slug); continue; }
          if (await baixar(jwt, f, time, fam!, n, banco.has(f.slug), t0, out)) out.baixados++;
          else out.pendentes.push(f.slug);
        }
      }
    } finally {
      // prazo próprio de 10 s: a volta ao 160 não depende do que sobrou do orçamento
      try { await rq(Date.now() + 10_000, jwt, "PUT", "team/switch/160"); } catch (e) { console.error("respondi-sync volta 160", semSegredo(e).slice(0, 200)); }
    }

    // casar + trava na mesma transação: queda > 2% desfaz o casar.
    const [ult] = await sql`select casadas from respondi.sync_execucoes
                             where status = 'ok' and casadas is not null order by terminada_em desc limit 1`;
    let base: number | null = ult ? Number(ult.casadas) : null;
    try {
      await sql.begin(async (tx) => {
        // 1ª execução (sem 'ok' anterior): base = contagem antes de casar
        const b = base ?? Number((await tx`select count(*)::int n from respondi.respostas where aluno_id is not null`)[0].n);
        base = b;
        out.casar = (await tx`select public.fn_respondi_casar() v`)[0].v;
        out.casadas = Number(out.casar?.casadas ?? 0);
        if (b > 0 && out.casadas < b * (1 - QUEDA_MAX)) throw new Trava();
      });
    } catch (e) {
      if (!(e instanceof Trava)) throw e;
      const m = `casadas cairia de ${base} para ${out.casadas} (>2%); casar desfeito, aplicar não executado`;
      console.error("respondi-sync trava", base, out.casadas);
      await fechar(exec, "travada", out, t0, m);
      exec = null;
      out.ms = Date.now() - t0;
      return json({ erro: `trava: ${m}`, ...out }, 500);
    }

    out.aplicar = (await sql`select public.fn_respondi_aplicar(false) v`)[0].v;
    out.a_confirmar = out.aplicar?.a_confirmar ?? null;
    await fechar(exec, "ok", out, t0, null);
    exec = null;
    out.ms = Date.now() - t0;
    console.log("respondi-sync", out.formularios_vistos, out.baixados, out.respostas_gravadas, out.pendentes.length, out.ms);
    return json(out);
  } catch (e) {
    const m = semSegredo(e).slice(0, 500);
    console.error("respondi-sync", m);
    if (exec !== null) { try { await fechar(exec, "erro", out, t0, m); } catch { /* fica em_curso e expira em 10 min */ } }
    return json({ erro: "falha interna" }, 500);
  }
});
