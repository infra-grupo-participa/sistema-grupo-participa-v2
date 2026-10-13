// hotmart-escritorio-webhook: regras e handler puros (sem rede, sem banco), para o teste unitário.
// O index.ts liga o handler ao Deno.serve, ao secret HOTMART_HOTTOK_ESCRITORIO e a dados.hotmart_ao_vivo_gravar
// (migration 20261013193000). Ordem: método → segredo configurado → hottok → content-type → tamanho → JSON → formato → banco.
// Nada toca o banco antes de o hottok conferir; a conta é fixa aqui, nunca lida do corpo; o log nunca leva payload.

export const CONTA = "escritorio";
export const MAX_BYTES = 64 * 1024;
export const VERSAO = "2.0.0";
// Lista fechada. PURCHASE_OUT_OF_SHOPPING_CART (dado pessoal sem venda) e CLUB_* ficam de fora de propósito.
export const EVENTOS: ReadonlySet<string> = new Set([
  "PURCHASE_APPROVED",
  "PURCHASE_COMPLETE",
  "PURCHASE_CANCELED",
  "PURCHASE_BILLET_PRINTED",
  "PURCHASE_DELAYED",
  "PURCHASE_REFUNDED",
  "PURCHASE_EXPIRED",
  "PURCHASE_PROTEST",
  "PURCHASE_CHARGEBACK",
]);
const TRANSACAO = /^[A-Za-z0-9_-]{1,64}$/;
// Faixas plausíveis (as mesmas de dados.hotmart_ao_vivo_payload_ok na migration 20261013193000). Formato real conferido
// em 2.392 eventos 2.0.0 da academy (cs.hotmart_eventos, 13/10/2026): todos esses campos vêm como number ou ausentes.
export const MS_MIN = Date.UTC(2000, 0, 1); // datas em ms desde 2000
export const UM_DIA_MS = 86_400_000; // creation_date/order_date/approved_date até agora + 1 dia
export const VALOR_MAX = 999_999_999_999.99; // cabe em numeric(14,2)
export const RECORRENCIA_MAX = 10_000;

type Obj = Record<string, unknown>;
export type Gravar = (conta: string, payload: Obj) => Promise<number>;
export type Deps = {
  hottok: () => string | undefined;
  gravar: Gravar;
  log: (mensagem: string) => void;
};

// Compara pelo SHA-256 dos dois lados: tempo constante e sem vazar o tamanho do segredo.
export async function hottokConfere(recebido: string | null, esperado: string | undefined): Promise<boolean> {
  if (!esperado || !recebido) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(recebido)),
    crypto.subtle.digest("SHA-256", enc.encode(esperado)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

const obj = (v: unknown): Obj | null => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : null);

const ausente = (v: unknown) => v === undefined || v === null;
const numero = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
// Data em ms: inteiro, de 2000 até agora + 1 dia (data futura congelaria a linha: o upsert só aceita evento mais novo).
export const msValido = (v: unknown, agora = Date.now()) =>
  numero(v) && Number.isInteger(v) && v >= MS_MIN && v <= agora + UM_DIA_MS;
const valorValido = (v: unknown, min: number) => numero(v) && v >= min && v <= VALOR_MAX;

// ok = payload aceito para gravar; motivo = por que foi ignorado (sem dado do comprador).
// Todo campo que a leitura converte (número/data) é conferido aqui: payload fora disso nunca chega ao banco.
export function validar(body: unknown, agora = Date.now()): { ok: true; payload: Obj } | { ok: false; motivo: string } {
  const b = obj(body);
  if (!b) return { ok: false, motivo: "formato" };
  if (b.version !== VERSAO) return { ok: false, motivo: "versao" };
  if (typeof b.event !== "string" || !EVENTOS.has(b.event)) return { ok: false, motivo: "evento" };
  const dados = obj(b.data);
  const compra = obj(dados?.purchase);
  const tx = compra?.transaction;
  if (typeof tx !== "string" || !TRANSACAO.test(tx.trim())) return { ok: false, motivo: "transacao" };
  if (typeof compra?.status !== "string" || compra.status.trim() === "") return { ok: false, motivo: "status" };
  if (!msValido(b.creation_date, agora)) return { ok: false, motivo: "creation_date" };
  for (const campo of ["order_date", "approved_date"] as const) {
    if (!ausente(compra[campo]) && !msValido(compra[campo], agora)) return { ok: false, motivo: campo };
  }
  const preco = compra.price;
  if (!ausente(preco) && !obj(preco)) return { ok: false, motivo: "price" };
  const valor = obj(preco)?.value;
  if (!ausente(valor) && !valorValido(valor, 0)) return { ok: false, motivo: "price.value" };
  const moeda = obj(preco)?.currency_value;
  if (!ausente(moeda) && (typeof moeda !== "string" || moeda.length > 10)) return { ok: false, motivo: "currency_value" };
  const rec = compra.recurrence_number;
  if (!ausente(rec) && !(numero(rec) && Number.isInteger(rec) && rec >= 0 && rec <= RECORRENCIA_MAX)) {
    return { ok: false, motivo: "recurrence_number" };
  }
  const comissoes = dados?.commissions;
  if (!ausente(comissoes)) {
    if (!Array.isArray(comissoes)) return { ok: false, motivo: "commissions" };
    for (const c of comissoes) {
      const co = obj(c);
      if (!co || (!ausente(co.value) && !valorValido(co.value, -VALOR_MAX))) return { ok: false, motivo: "commissions" };
    }
  }
  return { ok: true, payload: b };
}

// Content-Type tem de ser application/json (com ou sem charset).
export const ehJson = (ct: string | null) => /^application\/json\s*(;|$)/i.test(ct ?? "");

// Lê o corpo com teto real (vale também para corpo sem content-length). null = passou do teto.
export async function lerCorpo(req: Request, max = MAX_BYTES): Promise<string | null> {
  if (!req.body) return "";
  const leitor = req.body.getReader();
  const partes: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await leitor.cancel();
      return null;
    }
    partes.push(value);
  }
  const tudo = new Uint8Array(total);
  let o = 0;
  for (const p of partes) {
    tudo.set(p, o);
    o += p.byteLength;
  }
  return new TextDecoder().decode(tudo);
}

const json = (corpo: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json", ...extra } });

// Só o código do erro vai para o log (mensagem de banco pode citar valor do payload).
function codigoDoErro(e: unknown): string {
  const c = obj(e)?.code;
  return typeof c === "string" && /^[A-Za-z0-9_]{1,40}$/.test(c) ? c : "sem_codigo";
}

export function criarHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return json({ erro: "método não permitido" }, 405, { Allow: "POST" });

    const esperado = deps.hottok();
    if (!esperado) {
      deps.log("segredo HOTMART_HOTTOK_ESCRITORIO ausente: recusado (503)");
      return json({ erro: "indisponível" }, 503); // fail-closed
    }
    if (!(await hottokConfere(req.headers.get("x-hotmart-hottok"), esperado))) {
      return json({ erro: "não autorizado" }, 401);
    }

    if (!ehJson(req.headers.get("content-type"))) return json({ erro: "content-type deve ser application/json" }, 415);
    if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) return json({ erro: "corpo grande demais" }, 413);
    const texto = await lerCorpo(req);
    if (texto === null) return json({ erro: "corpo grande demais" }, 413);

    let body: unknown;
    try {
      body = JSON.parse(texto);
    } catch {
      deps.log("ignorado: json inválido (400)");
      return json({ erro: "json inválido" }, 400);
    }

    const v = validar(body);
    if (!v.ok) {
      deps.log(`ignorado: ${v.motivo}`);
      return json({ ok: true, gravado: false, ignorado: v.motivo });
    }

    try {
      const n = await deps.gravar(CONTA, v.payload); // resolve só depois do COMMIT
      return json({ ok: true, gravado: n > 0 });
    } catch (e) {
      const codigo = codigoDoErro(e);
      // 22023 = o banco recusou o payload pela mesma regra de validar() (defesa em profundidade). Reenviar não muda nada:
      // 200 "ignorado", nunca 500 (senão a Hotmart reenvia sem fim).
      if (codigo === "22023") {
        deps.log("ignorado: recusado pelo banco (22023)");
        return json({ ok: true, gravado: false, ignorado: "recusado_pelo_banco" });
      }
      deps.log(`falha ao gravar (${codigo}): 500 para a Hotmart reenviar`);
      return json({ erro: "falha interna" }, 500);
    }
  };
}
