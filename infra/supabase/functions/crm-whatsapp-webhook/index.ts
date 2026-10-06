// crm-whatsapp-webhook — entrada do WhatsApp oficial (Infobip) no CRM Comercial (migration 20261006b, F4).
// Recebe da Infobip, num único endereço: mensagens recebidas (results[].message), relatórios de entrega
// (results[].status) e vistos (results[].seenAt). Não decide nada aqui: valida a origem, limita o tamanho e entrega o
// corpo inteiro a crm.whatsapp_webhook(jsonb), que só guarda o que é do Comercial (número cadastrado / mensagem nossa),
// deduplica (reenvio da Infobip = no-op) e processa no banco. Com crm.config.whatsapp_ligado=false o bruto fica guardado
// e é processado depois (crm.whatsapp_reprocessar).
//
// Autenticação (fail-closed): segredo do Vault `crm_whatsapp_webhook_chave`, lido por crm.whatsapp_chave_webhook()
// (executável só pelo dono; esta função conecta com SUPABASE_DB_URL). Aceita:
//   - Authorization: Basic base64(<qualquer usuário>:<chave>)  ← o que a Infobip configura em "Basic auth" no webhook;
//   - x-crm-chave: <chave>.
// Sem chave no Vault → 503 (nunca aceita sem autenticar). verify_jwt = false (config.toml), como os webhooks da Hotmart.
//
// Respostas: 200 quando o banco gravou (inclusive "ignorado"/"duplicado": a Infobip não deve reenviar);
// 500 quando o banco falhou (a Infobip reenvia; o reenvio é idempotente). Log nunca leva corpo, telefone ou chave.
import postgres from "npm:postgres@3.4.4";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const LIMITE_BYTES = 1_000_000; // a Infobip manda lotes pequenos; acima disso é abuso
const CHAVE_TTL_MS = 600_000;

type Obj = Record<string, unknown>;

// Saída de erro passa SEMPRE por aqui: sem token, e-mail ou sequência longa de dígitos (telefone).
export function semSegredo(v: unknown): string {
  return String(v)
    .replace(/\b(Bearer|Basic|App)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***")
    .replace(/eyJ[A-Za-z0-9._-]{10,}/g, "***")
    .replace(/[^\s"'<>@]+@[^\s"'<>@]+/g, "***@***")
    .replace(/\d[\d.\-\s]{8,}\d/g, "***");
}

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });

// comparação em tempo constante (não vaza o tamanho do prefixo certo)
function igual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let d = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) d |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return d === 0;
}

let cache: { chave: string; ate: number } | null = null;
async function chaveWebhook(): Promise<string> {
  if (cache && cache.ate > Date.now()) return cache.chave;
  const [r] = await sql`select crm.whatsapp_chave_webhook() as chave`;
  cache = { chave: String(r?.chave ?? ""), ate: Date.now() + CHAVE_TTL_MS };
  return cache.chave;
}

function senhaRecebida(req: Request): string | null {
  const direta = req.headers.get("x-crm-chave");
  if (direta) return direta;
  const auth = req.headers.get("authorization") ?? "";
  const m = /^Basic\s+([A-Za-z0-9+\/=]+)$/i.exec(auth.trim());
  if (!m) return null;
  try {
    const dec = atob(m[1]);
    const i = dec.indexOf(":");
    return i >= 0 ? dec.slice(i + 1) : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, msg: "Método não permitido." }, 405);

  let chave: string;
  try {
    chave = await chaveWebhook();
  } catch (e) {
    console.error("crm-whatsapp-webhook: falha ao ler a chave", semSegredo(e));
    return json({ ok: false, msg: "Indisponível." }, 503);
  }
  if (!chave) return json({ ok: false, msg: "Webhook não configurado." }, 503); // fail-closed
  const senha = senhaRecebida(req);
  if (!senha || !igual(senha, chave)) return json({ ok: false, msg: "Não autorizado." }, 401);

  const tamanho = Number(req.headers.get("content-length") ?? "0");
  if (tamanho > LIMITE_BYTES) return json({ ok: false, msg: "Corpo grande demais." }, 413);
  const texto = await req.text();
  if (texto.length > LIMITE_BYTES) return json({ ok: false, msg: "Corpo grande demais." }, 413);

  let corpo: Obj;
  try {
    const p = JSON.parse(texto);
    if (!p || typeof p !== "object" || !Array.isArray((p as Obj).results)) {
      return json({ ok: false, msg: "Formato inesperado." }, 400);
    }
    corpo = p as Obj;
  } catch {
    return json({ ok: false, msg: "JSON inválido." }, 400);
  }

  try {
    const [r] = await sql`select crm.whatsapp_webhook(${sql.json(corpo as never)}) as r`;
    const res = (r?.r ?? {}) as Obj;
    // só contagens no log (nada de conteúdo)
    console.log("crm-whatsapp-webhook", JSON.stringify({
      recebidos: res.recebidos, novos: res.novos, duplicados: res.duplicados, ignorados: res.ignorados,
      processados: res.processados, erros: res.erros, ligado: res.ligado,
    }));
    return json({ ok: true });
  } catch (e) {
    console.error("crm-whatsapp-webhook: falha no banco", semSegredo(e));
    return json({ ok: false, msg: "Falha ao gravar." }, 500);
  }
});
