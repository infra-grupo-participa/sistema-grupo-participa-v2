// crm-integracao-webhook — F5 do CRM Comercial (migration 20261006044653). Publicada em 06/10/2026 (verify_jwt=false).
//
// Rotas (POST): /crm-integracao-webhook/activecampaign | /unnichat | /sendflow
// Faz só três coisas: lê o corpo, normaliza o MÍNIMO (funções abaixo, num arquivo só como as outras Edges) e chama public.crm_integracao_receber.
// Toda regra mora no banco: token conferido contra o Vault (crm_webhook_<fonte>), kill-switch por fonte em crm.config,
// idempotência por (fonte, id do evento), casamento da pessoa (e-mail; telefone só sem e-mail e com 1 candidato).
// Nenhum segredo aqui: a Edge não conhece o token, só repassa o que recebeu.
//
// Token: header `x-webhook-secret`. ActiveCampaign e SendFlow só mandam URL (sem header): para eles existe
// `?token=` — DESLIGADO por padrão (a URL inteira vai para o log das Edge Functions: pentest 29/09). Liga com a env
// CRM_WEBHOOK_TOKEN_NA_URL=sim, decisão do Arthur (ver 20261006c.explain.md).
// Deploy: verify_jwt = false (provedor não manda JWT). Resposta 200 também quando a fonte está desligada (o provedor não
// desliga o webhook por erro em série); 401 token errado; 400 corpo inválido; 500 erro do banco (ou banco > 3 s).
//
// Incidente 08/10/2026 20:04–20:10 UTC: ~38 mil webhooks do AC em 6 min saturaram o pool (522, banco reiniciado).
// Desde a migration 20261008230000 a RPC só ENFILEIRA (crm.integracao_fila); o processamento pesado roda no cron.
// Freios daqui: CRM_WEBHOOK_PAUSADO=sim responde 200 sem tocar no banco (funciona com o banco fora; o evento se perde,
// o AC não reenvia); a espera pela RPC é cortada em 3 s (libera o worker da Edge; a consulta já iniciada segue no
// banco até o statement_timeout do authenticator, 8 s). Nunca 410: o AC desliga o webhook para sempre com 410.
import { createClient } from "jsr:@supabase/supabase-js@2.117.2";

// ─── Normalização (pura, sem rede) ───
export type Fonte = "activecampaign" | "unnichat" | "sendflow";

export interface EventoNormalizado {
  id: string;
  tipo: string;
  ocorreuEm: string | null;
  email: string | null;
  telefone: string | null;
  nome: string | null;
  lista: string | null;
  tag: string | null;
  utm: { source?: string; medium?: string; campaign?: string; content?: string } | null;
}

type Obj = Record<string, unknown>;

const FONTES: readonly Fonte[] = ["activecampaign", "unnichat", "sendflow"];

export function fonteDaRota(pathname: string): Fonte | null {
  const ultimo = pathname.split("/").filter(Boolean).pop() ?? "";
  return (FONTES as readonly string[]).includes(ultimo) ? (ultimo as Fonte) : null;
}

const txt = (v: unknown, max = 200): string | null => {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  return s ? s.slice(0, max) : null;
};

export function tipoValido(t: string): string | null {
  const s = t.trim().toLowerCase().replace(/[^a-z0-9_.:-]+/g, "_").slice(0, 60);
  return /^[a-z0-9_.:-]{1,60}$/.test(s) ? s : null;
}

// ActiveCampaign manda application/x-www-form-urlencoded com chaves "contact[email]" etc.
// Tipos usados: subscribe, unsubscribe, contact_tag_added, contact_tag_removed, bounce (o resto passa com o nome cru).
// "date_time" vem como "YYYY-MM-DD HH:MM:SS" no fuso da conta: sem fuso explícito o banco usa o do servidor (UTC).
// Por isso o fuso da conta vai em AC_FUSO (ex.: "-03:00") quando a data não trouxer offset.
export function activecampaign(form: URLSearchParams, fuso = "-03:00"): EventoNormalizado | null {
  const tipo = tipoValido(form.get("type") ?? "");
  const contato = txt(form.get("contact[id]"), 40);
  if (!tipo || !contato) return null;
  const dt = txt(form.get("date_time"), 40);
  const ocorreuEm = dt ? (/[zZ]|[+-]\d{2}:?\d{2}$/.test(dt) ? dt : `${dt.replace(" ", "T")}${fuso}`) : null;
  const lista = txt(form.get("list"), 200) ?? txt(form.get("list[name]"), 200);
  const tag = txt(form.get("tag"), 200);
  const nome = [form.get("contact[first_name]"), form.get("contact[last_name]")].filter(Boolean).join(" ").trim() || null;
  return {
    id: [contato, tipo, dt ?? "", lista ?? "", tag ?? ""].join(":").slice(0, 200),
    tipo,
    ocorreuEm,
    email: txt(form.get("contact[email]"), 320),
    telefone: txt(form.get("contact[phone]"), 40),
    nome: nome ? nome.slice(0, 160) : null,
    lista,
    tag,
    utm: null,
  };
}

// Unnichat: { contact: { id, name, email, phoneNumber, tags }, event_date, triggerData } (formato visto em
// controle.unnichat_evento). O tipo vem na URL (?evento=template_enviado | convite_grupo | workbook | …), como no legado.
export function unnichat(body: Obj, evento: string | null): EventoNormalizado | null {
  const c = (body?.contact ?? {}) as Obj;
  const tipo = tipoValido(evento ?? String(body?.event ?? ""));
  const contato = txt(c?.id, 80);
  const quando = txt(body?.event_date, 40);
  if (!tipo || !contato) return null;
  return {
    id: [contato, tipo, quando ?? ""].join(":").slice(0, 200),
    tipo,
    ocorreuEm: quando,
    email: txt(c?.email, 320),
    telefone: txt(c?.phoneNumber, 40),
    nome: txt(c?.name, 160),
    lista: null,
    tag: txt(body?.tag ?? evento, 200),
    utm: null,
  };
}

// SendFlow (sendhook): { event, data: { createdAt, groupId, groupName, number, campaignName } }. Pronto e DESLIGADO:
// hoje a entrada em grupo já chega por sendflow-webhook → controle.grupo_evento → grupo_evento_unificado (lido pela jornada).
export function sendflow(body: Obj): EventoNormalizado | null {
  const d = ((body?.data ?? body) ?? {}) as Obj;
  const ev = String(body?.event ?? d?.event ?? "").toLowerCase();
  const tipo = ev.includes("remov") || ev.includes("left") || ev.includes("leave") || ev.includes("saiu")
    ? "saida"
    : ev.includes("add") || ev.includes("join") || ev.includes("entr") ? "entrada" : null;
  const numero = txt(d?.number, 40);
  const grupo = txt(d?.groupId, 80);
  const quando = txt(d?.createdAt, 40);
  if (!tipo || !numero || !grupo) return null;
  return {
    id: [numero.replace(/\D/g, ""), grupo, tipo, quando ?? ""].join(":").slice(0, 200),
    tipo,
    ocorreuEm: quando,
    email: null,
    telefone: numero,
    nome: null,
    lista: txt(d?.groupName, 200),
    tag: txt(d?.campaignName, 200),
    utm: null,
  };
}

// ─── Handler ───
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const TOKEN_NA_URL = ["sim", "true", "1", "on"].includes((Deno.env.get("CRM_WEBHOOK_TOKEN_NA_URL") ?? "").trim().toLowerCase());
const AC_FUSO = Deno.env.get("AC_FUSO") ?? "-03:00";
const MAX_BYTES = 64_000;
const RPC_TIMEOUT_MS = 3_000;
const PAUSADO = ["sim", "true", "1", "on"].includes((Deno.env.get("CRM_WEBHOOK_PAUSADO") ?? "").trim().toLowerCase());

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, reason: "method_not_allowed" }, 405);
  // Freio de emergência (mesmo ponto da v7 publicada): antes de tudo, sem ler o corpo e sem tocar no banco (o token é
  // conferido NO banco). 200 para o provedor não desligar o webhook.
  if (PAUSADO) return json({ ok: true, ignorado: "pausado" });
  if (!SUPABASE_URL || !SERVICE_ROLE) {
    console.error("crm-integracao-webhook: env do Supabase ausente");
    return json({ ok: false, reason: "server_misconfigured" }, 500);
  }
  const url = new URL(req.url);
  const fonte = fonteDaRota(url.pathname);
  if (!fonte) return json({ ok: false, reason: "fonte_invalida" }, 404);

  const token = req.headers.get("x-webhook-secret") ?? (TOKEN_NA_URL ? url.searchParams.get("token") : null);
  if (!token) return json({ ok: false, reason: "unauthorized" }, 401);

  const bruto = await req.text();
  if (bruto.length > MAX_BYTES) return json({ ok: false, reason: "payload_grande" }, 413);

  const eventos: EventoNormalizado[] = [];
  try {
    if (fonte === "activecampaign") {
      const ct = req.headers.get("content-type") ?? "";
      const form = ct.includes("application/json")
        ? new URLSearchParams(Object.entries(JSON.parse(bruto) as Record<string, string>))
        : new URLSearchParams(bruto);
      const e = activecampaign(form, AC_FUSO);
      if (e) eventos.push(e);
    } else {
      const corpo = JSON.parse(bruto);
      const lista = Array.isArray(corpo) ? corpo.slice(0, 100) : [corpo];
      for (const item of lista) {
        const e = fonte === "unnichat" ? unnichat(item, url.searchParams.get("evento")) : sendflow(item);
        if (e) eventos.push(e);
      }
    }
  } catch {
    return json({ ok: false, reason: "corpo_invalido" }, 400);
  }
  if (eventos.length === 0) return json({ ok: false, reason: "sem_evento_reconhecido" }, 400);

  const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await db
    .rpc("crm_integracao_receber", { p_fonte: fonte, p_chave: token, p_eventos: eventos })
    .abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
  if (error) {
    // nunca o corpo nem a mensagem: tem e-mail/telefone. Timeout/rede pode chegar sem code.
    console.error(`crm-integracao-webhook: rpc falhou (${error.code || "timeout_ou_rede"})`);
    return json({ ok: false, reason: "db_error" }, 500);
  }
  const r = (data ?? {}) as Record<string, unknown>;
  if (r.autorizado === false) return json({ ok: false, reason: "unauthorized" }, 401);
  return json(r, r.ok === false ? 400 : 200);
});
