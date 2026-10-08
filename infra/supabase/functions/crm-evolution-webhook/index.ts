// crm-evolution-webhook — entrada do WhatsApp conectado por QR (Evolution API v2) no CRM Comercial (migration 20261008152212).
// Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
//
// A Evolution chama POST <esta função>?i=<instância> (configurado pelo sistema ao criar a instância, um webhook por
// instância, byEvents=false, base64=true) com os eventos MESSAGES_UPSERT, CONNECTION_UPDATE e QRCODE_UPDATED.
//
// Autenticação (fail-closed): header x-crm-chave = chave própria da instância (crm.numero_whatsapp_segredo, gerada no banco
// ao criar o número), lida por crm.evolution_chave_webhook(instância) e comparada em tempo constante. Instância
// desconhecida ou sem chave → 401. verify_jwt = false (config.toml).
//
// Fluxo: normaliza (normalizar.ts, puro e testado) → crm.evolution_webhook(canal, eventos) guarda/deduplica/processa no
// banco (kill-switch crm.config.evolution_ligado: desligado = mensagem guardada e processada depois) → para cada mensagem
// com arquivo pendente, sobe o base64 que veio no webhook para o bucket privado crm-midia e grava com
// crm.whatsapp_midia_resultado. Grupos, status e canais são ignorados aqui (nem chegam ao banco).
//
// Respostas: 200 quando o banco gravou (inclusive duplicado/ignorado); 500 quando falhou (a Evolution reenvia; o reenvio é
// idempotente pelo id da mensagem). Log só com contagens: nunca corpo, telefone, QR ou chave.
import postgres from "npm:postgres@3.4.4";
import { bytesDoBase64, caminhoArquivo, INSTANCIA_RE, mimeBase, mimeSeguro, normalizarWebhook, type EventoMensagem } from "./normalizar.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
// mensagem com arquivo vem com o base64 junto (até ~25 MB de arquivo); acima disso é abuso
const LIMITE_BYTES = 40 * 1024 * 1024;
const CHAVE_TTL_MS = 300_000;
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "crm-midia";

type Obj = Record<string, unknown>;

export function semSegredo(v: unknown): string {
  return String(v)
    .replace(/\b(Bearer|Basic|App)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***")
    .replace(/eyJ[A-Za-z0-9._-]{10,}/g, "***")
    .replace(/[^\s"'<>@]+@[^\s"'<>@]+/g, "***@***")
    .replace(/\d[\d.\-\s]{8,}\d/g, "***");
}

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });

function recusa(req: Request, status: number, msg: string): Response {
  console.warn("crm-evolution-webhook: recusado", JSON.stringify({
    status, msg, tamanho: req.headers.get("content-length"), ua: (req.headers.get("user-agent") ?? "").slice(0, 40),
  }));
  return json({ ok: false, msg }, status);
}

function igual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let d = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) d |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return d === 0;
}

const cache = new Map<string, { canal: string | null; chave: string; ate: number }>();
async function chaveDa(instancia: string): Promise<{ canal: string | null; chave: string }> {
  const c = cache.get(instancia);
  if (c && c.ate > Date.now()) return c;
  const [r] = await sql`select canal_id, chave from crm.evolution_chave_webhook(${instancia})`;
  const v = { canal: r?.canal_id ? String(r.canal_id) : null, chave: String(r?.chave ?? ""), ate: Date.now() + CHAVE_TTL_MS };
  cache.set(instancia, v);
  return v;
}

function decodificar(b64: string): Uint8Array {
  const bin = atob(b64.replace(/\s/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function subir(caminho: string, mime: string, dados: Uint8Array): Promise<string | null> {
  if (!SUPABASE_URL || !SERVICE_ROLE) return "Storage não configurado na Edge.";
  try {
    const r = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}/${caminho.split("/").map(encodeURIComponent).join("/")}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE, "Content-Type": mime, "x-upsert": "true", "cache-control": "3600" },
      body: new Blob([dados as BlobPart], { type: mime }),
      signal: AbortSignal.timeout(20_000),
    });
    await r.body?.cancel().catch(() => {});
    return r.ok ? null : `Storage HTTP ${r.status}`;
  } catch (e) {
    return (e instanceof Error && e.name === "TimeoutError") ? "Storage: timeout" : "Storage: falha de rede";
  }
}

// Sobe o arquivo que veio no webhook. Falha = tenta de novo quando a Evolution reenviar; sem reenvio, o banco marca
// "não chegou" em 15 min (crm.evolution_fila_pegar).
async function guardarArquivo(m: { mensagemId: string; conversaId: string }, ev: EventoMensagem, b64: string, limite: number): Promise<string> {
  const tamanho = bytesDoBase64(b64);
  if (tamanho > limite) {
    const [x] = await sql`select crm.whatsapp_midia_resultado(${m.mensagemId}::uuid, ${"grande_demais"}, ${null}, ${ev.mime},
                                 ${tamanho}, ${ev.arquivo}, ${"Arquivo acima do limite do CRM."}) as x`;
    return String(x?.x ?? "?");
  }
  let dados: Uint8Array;
  try {
    dados = decodificar(b64);
  } catch {
    const [x] = await sql`select crm.whatsapp_midia_resultado(${m.mensagemId}::uuid, ${"falhou"}, ${null}, ${null}, ${null}, ${null}, ${"Arquivo corrompido."}) as x`;
    return String(x?.x ?? "?");
  }
  const mime = mimeSeguro(ev.mime);
  const caminho = caminhoArquivo(m.conversaId, m.mensagemId, mime);
  const erro = await subir(caminho, mime, dados);
  if (erro) return "tentar";
  const [x] = await sql`select crm.whatsapp_midia_resultado(${m.mensagemId}::uuid, ${"ok"}, ${caminho}, ${mimeBase(ev.mime) || mime},
                               ${dados.byteLength}, ${ev.arquivo}, ${null}) as x`;
  return String(x?.x ?? "?");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return recusa(req, 405, "Método não permitido.");
  const instancia = new URL(req.url).searchParams.get("i") ?? "";
  if (!INSTANCIA_RE.test(instancia)) return recusa(req, 401, "Não autorizado.");

  let cred: { canal: string | null; chave: string };
  try {
    cred = await chaveDa(instancia);
  } catch (e) {
    console.error("crm-evolution-webhook: falha ao ler a chave", semSegredo(e));
    return json({ ok: false, msg: "Indisponível." }, 503);
  }
  const recebida = req.headers.get("x-crm-chave") ?? "";
  if (!cred.canal || !cred.chave || !recebida || !igual(recebida, cred.chave)) return recusa(req, 401, "Não autorizado.");

  const tamanho = Number(req.headers.get("content-length") ?? "0");
  if (tamanho > LIMITE_BYTES) return recusa(req, 413, "Corpo grande demais.");
  const texto = await req.text();
  if (texto.length > LIMITE_BYTES) return recusa(req, 413, "Corpo grande demais.");

  let corpo: unknown;
  try {
    corpo = JSON.parse(texto);
  } catch {
    return recusa(req, 400, "JSON inválido.");
  }
  const n = normalizarWebhook(corpo);
  if (n.instancia && n.instancia !== instancia) return recusa(req, 400, "Instância diferente da do endereço.");
  if (n.eventos.length === 0) {
    console.log("crm-evolution-webhook", JSON.stringify({ eventos: 0, ignorados: n.ignorados.length }));
    return json({ ok: true });
  }

  // o banco não recebe base64; vai só o evento normalizado
  try {
    const [r] = await sql`select crm.evolution_webhook(${cred.canal}::uuid, ${sql.json(n.eventos as never)}) as r`;
    const res = (r?.r ?? {}) as Obj;
    const midias = Array.isArray(res.midias) ? (res.midias as { ref: number; mensagemId: string; conversaId: string }[]) : [];
    const cont: Record<string, number> = {};
    if (midias.length) {
      const [lim] = await sql`select midia_limite_bytes from crm.config`;
      const limite = Number(lim?.midia_limite_bytes) || 26_214_400;
      for (const m of midias) {
        const ev = n.eventos[m.ref];
        const b64 = n.arquivos[m.ref];
        if (!ev || ev.evento !== "mensagem" || !b64) continue;
        let resultado: string;
        try {
          resultado = await guardarArquivo(m, ev, b64, limite);
        } catch (e) {
          console.error("crm-evolution-webhook: falha no arquivo", semSegredo(e));
          resultado = "erro";
        }
        cont[resultado] = (cont[resultado] ?? 0) + 1;
      }
    }
    console.log("crm-evolution-webhook", JSON.stringify({
      recebidos: res.recebidos, novos: res.novos, duplicados: res.duplicados, ignorados: Number(res.ignorados ?? 0) + n.ignorados.length,
      processados: res.processados, erros: res.erros, ligado: res.ligado, arquivos: cont,
    }));
    if (res.ok === false) return json({ ok: false, msg: "Instância sem canal." }, 404);
    return json({ ok: true });
  } catch (e) {
    console.error("crm-evolution-webhook: falha no banco", semSegredo(e));
    return json({ ok: false, msg: "Falha ao gravar." }, 500);
  }
});
