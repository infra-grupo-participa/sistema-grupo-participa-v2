// respondi-webhook — recebe em tempo real as respostas dos formulários do Respondi ligados a um dashboard
// (dados.dashboard_formularios) e grava em respondi.respostas (migration 20261009190000). Mesmo uuid e mesma
// normalização do respondi-sync (normaliza.ts): o sync diário reconcilia sem duplicar.
// Autentica pelo segredo na URL (?k=, Vault respondi_webhook_chave), fail-closed: o Respondi não manda header próprio.
// Idempotente: on conflict (uuid) em respondi.respostas. Formulário fora da lista: 202 e nada gravado.
// Log em respondi.webhook_log SEM dado pessoal (formulário, uuid da resposta, resultado).
import postgres from "npm:postgres@3.4.4";
import { resposta } from "../respondi-sync/normaliza.ts";
import { ler } from "./payload.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const MAX_BYTES = 256 * 1024;
const CHAVE_TTL_MS = 600_000;
type Obj = Record<string, any>;

// Saída de erro passa por aqui: sem token, e-mail ou sequência longa de dígitos.
function semSegredo(v: unknown): string {
  return String(v)
    .replace(/\b(Bearer)\s+[A-Za-z0-9._~+\/=-]+/gi, "$1 ***")
    .replace(/[^\s"'<>@]+@[^\s"'<>@]+/g, "***@***")
    .replace(/\d[\d.\-\s]{8,}\d/g, "***")
    .slice(0, 300);
}

let chaveCache: { chave: string | null; ate: number } | null = null;
async function chave(): Promise<string | null> {
  if (chaveCache && chaveCache.ate > Date.now()) return chaveCache.chave;
  const [r] = await sql`select respondi.webhook_chave() as c`;
  chaveCache = { chave: r?.c ?? null, ate: Date.now() + CHAVE_TTL_MS };
  return chaveCache.chave;
}
function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
// Lê o corpo com teto real (vale também para corpo chunked, sem content-length). null = passou do teto.
async function lerCorpo(req: Request): Promise<string | null> {
  if (!req.body) return "";
  const leitor = req.body.getReader();
  const partes: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BYTES) { await leitor.cancel(); return null; }
    partes.push(value);
  }
  const tudo = new Uint8Array(total);
  let o = 0;
  for (const p of partes) { tudo.set(p, o); o += p.byteLength; }
  return new TextDecoder().decode(tudo);
}
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
const registrar = (slug: string | null, uuid: string | null, resultado: string, detalhe: string | null = null) =>
  sql`insert into respondi.webhook_log (form_slug, resposta_uuid, resultado, detalhe)
      values (${slug}, ${uuid}, ${resultado}, ${detalhe})`;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "método não permitido" }, 405);
  let slug: string | null = null;
  let uuid: string | null = null;
  try {
    const c = await chave();
    const k = new URL(req.url).searchParams.get("k") ?? "";
    if (!c || !igual(k, c)) return json({ erro: "não autorizado" }, 401);

    if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) return json({ erro: "corpo grande demais" }, 413);
    const texto = await lerCorpo(req);
    if (texto === null) return json({ erro: "corpo grande demais" }, 413);
    let body: unknown;
    try { body = JSON.parse(texto); } catch {
      await registrar(null, null, "invalida", "json");
      return json({ erro: "json inválido" }, 400);
    }

    const lido = ler(body);
    if (!lido) {
      await registrar(null, null, "invalida", "formato");
      return json({ erro: "formato inválido" }, 422);
    }
    slug = lido.slug;
    uuid = lido.uuid;

    const [f] = await sql`
      select f.familia, f.turma_codigo, f.campos
        from respondi.formularios f
       where f.slug = ${slug}
         and exists (select 1 from dados.dashboard_formularios d join dados.dashboards b on b.chave = d.chave
                      where d.form_slug = f.slug and b.ativo)`;
    if (!f) {
      await registrar(slug, uuid, "ignorada_formulario");
      return json({ ok: true, gravada: false }, 202);
    }

    const flds = new Map<string, Obj>((f.campos ?? []).map((x: Obj) => [x.slug, { slug: x.slug, type: x.tipo, q: x.pergunta }]));
    const r = lido.respondente;
    if (!r.updated_at) r.updated_at = r.created_at = new Date().toISOString();
    const linha = resposta(r, slug, flds, f.familia, f.turma_codigo);
    if (!linha) {
      await registrar(slug, uuid, "invalida", "sem respostas");
      return json({ erro: "sem respostas" }, 422);
    }

    // fn_respondi_carga (20261009190100) não toca resposta de outro formulário com o mesmo uuid: conta 0
    const gravou = await sql.begin(async (tx) => {
      const [c] = await tx`select public.fn_respondi_carga('[]'::jsonb, ${tx.json([linha])}::jsonb) as v`;
      if (Number(c?.v?.respostas ?? 0) < 1) return false;
      await tx`insert into respondi.webhook_log (form_slug, resposta_uuid, resultado) values (${slug}, ${uuid}, 'gravada')`;
      return true;
    });
    if (!gravou) {
      await registrar(slug, uuid, "invalida", "uuid de outro formulário");
      return json({ erro: "resposta de outro formulário" }, 409);
    }
    return json({ ok: true, gravada: true });
  } catch (e) {
    const m = semSegredo(e);
    console.error("respondi-webhook", m);
    try { await registrar(slug, uuid, "erro", m); } catch { /* sem banco: só o console */ }
    return json({ erro: "falha interna" }, 500); // 5xx: o Respondi pode reenviar, e a gravação é idempotente
  }
});
