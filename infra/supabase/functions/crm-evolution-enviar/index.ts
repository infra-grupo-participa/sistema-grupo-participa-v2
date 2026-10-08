// crm-evolution-enviar — saída do WhatsApp conectado por QR (Evolution API v2) do CRM Comercial (migration 20261008152212).
// Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
//
// Quem chama: crm.evolution_disparar_envio() logo depois do COMMIT de crm_enviar_mensagem, e o cron
// `crm-evolution-enviar` (1/min, ops.cron_post) só quando crm.evolution_fila_tem(). Header x-crm-chave = Vault
// crm_whatsapp_envio_chave (a mesma chave interna das Edges do WhatsApp). verify_jwt = false.
//
// crm.evolution_fila_pegar(lote) já revalidou no banco (kill-switches evolution_ligado + envio_ligado, número conectado e
// que envia, opt-out, anexo existe) e travou as mensagens (status 'enviando', SKIP LOCKED). O anti-ban de volume (por
// minuto/hora/primeiro contato, sem disparo em massa) está no trigger crm.tg_mensagem_canal, antes de entrar na fila.
// Aqui: uma mensagem por vez por número, com pausa de 1,2–2,4 s entre elas; POST na Evolution; resultado no banco:
//   2xx → 'enviada' (+ key.id para casar com o eco do webhook) · 429 → volta para a fila · 4xx → 'falhou'
//   5xx/rede/timeout → falha incerta (NUNCA reenvia o que pode ter saído).
// Arquivo: URL assinada de 1 h do bucket privado crm-midia (a Evolution baixa dali).
//
// Segredos (Vault, nunca em código): evolution_api_url, evolution_api_key, crm_whatsapp_envio_chave — lidos por
// crm.evolution_credenciais() (só o dono executa; conexão SUPABASE_DB_URL). Fail-closed: sem chave/URL → 503.
import postgres from "npm:postgres@3.4.4";
import { baseEvolution, classificar, erroDaResposta, idDaResposta, pausaMs, pedidoEvolution, type FilaEvolution } from "./evolution.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const PRAZO_MS = 45_000;
const RQ_MAX_MS = 15_000;
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "crm-midia";

type Cred = { url: string | null; api_key: string | null; chave_envio: string | null };

export function semSegredo(v: unknown): string {
  return String(v)
    .replace(/\b(Bearer|Basic|App)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***")
    .replace(/eyJ[A-Za-z0-9._-]{10,}/g, "***")
    .replace(/[^\s"'<>@]+@[^\s"'<>@]+/g, "***@***")
    .replace(/\d[\d.\-\s]{8,}\d/g, "***");
}

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });

function igual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let d = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) d |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return d === 0;
}

const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function assinar(caminho: string): Promise<string | null> {
  if (!SUPABASE_URL || !SERVICE_ROLE) return null;
  try {
    const r = await fetch(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET}/${caminho.split("/").map(encodeURIComponent).join("/")}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE, "Content-Type": "application/json" },
      body: JSON.stringify({ expiresIn: 3600 }),
      signal: AbortSignal.timeout(RQ_MAX_MS),
    });
    if (!r.ok) return null;
    const d = (await r.json().catch(() => null)) as Record<string, unknown> | null;
    const rel = String(d?.signedURL ?? d?.signedUrl ?? "");
    return rel ? `${SUPABASE_URL}/storage/v1${rel.startsWith("/") ? "" : "/"}${rel}` : null;
  } catch {
    return null;
  }
}

async function resultado(id: string, http: number, msgId: string | null, erro: string | null, reenfileirar: boolean): Promise<string> {
  const [x] = await sql`select crm.evolution_fila_resultado(${id}::uuid, ${http}, ${msgId}, ${erro}, ${reenfileirar}) as x`;
  return String(x?.x ?? "?");
}

async function enviarUma(base: string, apiKey: string, m: FilaEvolution): Promise<string> {
  const url = m.midia_caminho ? await assinar(m.midia_caminho) : null;
  if (m.midia_caminho && !url) return resultado(m.mensagem_id, -1, null, "Não foi possível preparar o anexo.", true);
  const p = pedidoEvolution(m, url);
  if (!p) return resultado(m.mensagem_id, 400, null, "Mensagem fora do formato aceito.", false);
  let http = 0;
  let dados: unknown = null;
  try {
    const r = await fetch(base + p.caminho, {
      method: "POST",
      headers: { apikey: apiKey, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(p.corpo),
      signal: AbortSignal.timeout(RQ_MAX_MS),
    });
    http = r.status;
    dados = await r.json().catch(() => null);
  } catch (e) {
    const erro = (e instanceof Error && e.name === "TimeoutError") ? "timeout" : "falha de rede";
    return resultado(m.mensagem_id, 0, null, erro, false);
  }
  const c = classificar(http);
  if (c === "ok") return resultado(m.mensagem_id, http, idDaResposta(dados), null, false);
  return resultado(m.mensagem_id, http, null, erroDaResposta(http, dados), c === "reenfileirar");
}

async function enviar(base: string, apiKey: string, inicio: number): Promise<Record<string, unknown>> {
  const fila = (await sql`select * from crm.evolution_fila_pegar(20)`) as unknown as FilaEvolution[];
  const cont: Record<string, number> = {};
  // um trabalhador por número; dentro do número, uma por vez com pausa
  const porNumero = new Map<string, FilaEvolution[]>();
  for (const m of fila) porNumero.set(m.instancia, [...(porNumero.get(m.instancia) ?? []), m]);
  await Promise.all([...porNumero.values()].map(async (lista) => {
    for (let i = 0; i < lista.length; i++) {
      const m = lista[i];
      let res: string;
      if (Date.now() - inicio > PRAZO_MS) {
        res = await resultado(m.mensagem_id, -1, null, "prazo do ciclo esgotado", true).catch(() => "erro_gravacao");
      } else {
        try {
          res = await enviarUma(base, apiKey, m);
        } catch (e) {
          console.error("crm-evolution-enviar: falha ao gravar resultado", semSegredo(e));
          res = "erro_gravacao";
        }
        if (i < lista.length - 1) await dormir(pausaMs(Math.random()));
      }
      cont[res] = (cont[res] ?? 0) + 1;
    }
  }));
  return { pegas: fila.length, numeros: porNumero.size, resultado: cont };
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  if (req.method !== "POST") return json({ ok: false, msg: "Método não permitido." }, 405);
  let cred: Cred;
  try {
    const [r] = await sql`select url, api_key, chave_envio from crm.evolution_credenciais()`;
    cred = { url: r?.url ?? null, api_key: r?.api_key ?? null, chave_envio: r?.chave_envio ?? null };
  } catch (e) {
    console.error("crm-evolution-enviar: falha ao ler credenciais", semSegredo(e));
    return json({ ok: false, msg: "Indisponível." }, 503);
  }
  if (!cred.chave_envio) return json({ ok: false, msg: "Envio não configurado." }, 503);
  if (!igual(req.headers.get("x-crm-chave") ?? "", cred.chave_envio)) return json({ ok: false, msg: "Não autorizado." }, 401);
  const base = baseEvolution(cred.url);
  if (!base || !cred.api_key) return json({ ok: false, msg: "Evolution não configurada (Vault evolution_api_url / evolution_api_key)." }, 503);

  try {
    const out = await enviar(base, cred.api_key, inicio);
    console.log("crm-evolution-enviar", JSON.stringify(out), `${Date.now() - inicio} ms`);
    return json({ ok: true, ...out });
  } catch (e) {
    console.error("crm-evolution-enviar: falha", semSegredo(e));
    return json({ ok: false, msg: "Falha no ciclo." }, 500);
  }
});
