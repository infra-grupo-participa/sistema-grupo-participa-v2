// mkt-web-pagespeed: teste de laboratório do Google (PageSpeed Insights) das páginas da Web, 1 vez por dia
// (migration 20261006h). Quem chama: o cron mkt-web-pagespeed, pelo ops.cron_post, com o header x-sync-chave
// (= Vault mkt_web_pagespeed_chave). A Edge entra no banco como postgres (SUPABASE_DB_URL), pede a fila
// (mkt_web.pagespeed_fila: páginas ativas de projeto com a coleta ligada, sem teste nas últimas 20 h), roda o Google
// 3 de cada vez e guarda cada resultado (mkt_web.pagespeed_guardar), inclusive a falha (ex.: HTTP 429 da cota pública).
// Chave do Google: OPCIONAL, Vault mkt_web_pagespeed_api_key (lida por mkt_web.pagespeed_credenciais). Nunca no código.
// O que não couber no orçamento fica para o dia seguinte (a fila começa pelas mais antigas).
import postgres from "npm:postgres@3.4.4";
import { resumirGoogle, urlGoogle } from "./resumo.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const ORCAMENTO_MS = 120_000; // não começa teste novo depois disso (a Edge morre em 150 s)
const TESTE_MAX_MS = 60_000; // um teste do Google leva de 10 a 40 s
const AO_MESMO_TEMPO = 3;
const CRED_TTL_MS = 600_000;

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

let credCache: { chave: string | null; apiKey: string | null; ate: number } | null = null;
async function credenciais() {
  if (credCache && credCache.ate > Date.now()) return credCache;
  const [r] = await sql`select chave, api_key from mkt_web.pagespeed_credenciais()`;
  credCache = { chave: r?.chave ?? null, apiKey: r?.api_key ?? null, ate: Date.now() + CRED_TTL_MS };
  return credCache;
}

interface Item { pagina_id: number; url: string; estrategia: "mobile" | "desktop" }

async function medir(item: Item, apiKey: string | null, ate: number): Promise<"ok" | "erro"> {
  const base = { pagina_id: item.pagina_id, estrategia: item.estrategia, url: item.url };
  let erro = "";
  try {
    const r = await fetch(urlGoogle(item.url, item.estrategia, apiKey), {
      signal: AbortSignal.timeout(Math.max(1000, Math.min(TESTE_MAX_MS, ate + 25_000 - Date.now()))),
    });
    if (r.ok) {
      const resumo = resumirGoogle(await r.json());
      await sql`select mkt_web.pagespeed_guardar(${sql.json({ ...base, ...resumo })})`;
      return "ok";
    }
    await r.body?.cancel();
    erro = `HTTP ${r.status}`; // nunca o corpo nem a URL do pedido (leva a chave)
  } catch (e) {
    erro = e instanceof DOMException && e.name === "TimeoutError" ? "tempo esgotado" : "falha de rede";
  }
  await sql`select mkt_web.pagespeed_guardar(${sql.json({ ...base, erro })})`;
  return "erro";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "método" }, 405);
  let cred;
  try {
    cred = await credenciais();
  } catch {
    return json({ erro: "banco" }, 503);
  }
  const recebida = req.headers.get("x-sync-chave") ?? "";
  if (!cred.chave || !igual(recebida, cred.chave)) return json({ erro: "chave" }, 401);

  const ate = Date.now() + ORCAMENTO_MS;
  const fila: Item[] = (await sql`select pagina_id, url, estrategia from mkt_web.pagespeed_fila(12)`).map((r) => ({
    pagina_id: Number(r.pagina_id), url: String(r.url), estrategia: r.estrategia,
  }));
  let ok = 0, erros = 0, pulados = 0;
  const trabalhador = async () => {
    for (let item = fila.shift(); item; item = fila.shift()) {
      if (Date.now() > ate) { pulados++; continue; }
      if ((await medir(item, cred.apiKey, ate)) === "ok") ok++; else erros++;
    }
  };
  await Promise.all(Array.from({ length: AO_MESMO_TEMPO }, trabalhador));
  return json({ ok, erros, pulados, com_chave: !!cred.apiKey });
});
