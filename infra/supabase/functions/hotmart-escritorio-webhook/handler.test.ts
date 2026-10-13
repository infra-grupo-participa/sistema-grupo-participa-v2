// deno test infra/supabase/functions/hotmart-escritorio-webhook/handler.test.ts
// Regras e segurança da edge, sem rede e sem banco (o "banco" é um dublê que conta as chamadas). Dados fictícios.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { CONTA, criarHandler, ehJson, EVENTOS, hottokConfere, MAX_BYTES, UM_DIA_MS, validar } from "./handler.ts";

const HOTTOK = "hottok-de-teste-0123456789";
const EMAIL = "comprador@ensaio.local";
const NOME = "Comprador Ensaio";
const FONE = "5500000000000";

function payload(extra: Record<string, unknown> = {}) {
  return {
    id: "evento-ensaio-1",
    event: "PURCHASE_APPROVED",
    version: "2.0.0",
    creation_date: 1760380000000,
    conta: "academy", // tentativa de trocar a conta pelo corpo: tem de ser ignorada
    data: {
      product: { id: 5238525 },
      buyer: { email: EMAIL, name: NOME, checkout_phone: FONE, document: "00000000000" },
      purchase: { transaction: "HP0000000001", status: "APPROVED", offer: { code: "ofertaensaio" }, price: { value: 1000 } },
    },
    ...extra,
  };
}

function montar(opts: { hottok?: string; falha?: unknown; retorno?: number } = {}) {
  const chamadas: { conta: string; payload: Record<string, unknown> }[] = [];
  const logs: string[] = [];
  const handler = criarHandler({
    hottok: () => ("hottok" in opts ? opts.hottok : HOTTOK),
    gravar: (conta, p) => {
      chamadas.push({ conta, payload: p });
      if (opts.falha) return Promise.reject(opts.falha);
      return Promise.resolve(opts.retorno ?? 1);
    },
    log: (m) => logs.push(m),
  });
  return { handler, chamadas, logs };
}

function req(corpo: unknown, headers: Record<string, string> = { "x-hotmart-hottok": HOTTOK }, method = "POST") {
  return new Request("http://local/hotmart-escritorio-webhook", {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: method === "GET" ? undefined : typeof corpo === "string" ? corpo : JSON.stringify(corpo),
  });
}

function semPii(logs: string[]) {
  for (const l of logs) {
    assert(!l.includes(EMAIL) && !l.includes(NOME) && !l.includes(FONE) && !l.includes(HOTTOK), `log com dado sensível: ${l}`);
  }
}

Deno.test("hottok: igual confere; diferente, outro tamanho, vazio ou ausente não", async () => {
  assertEquals(await hottokConfere(HOTTOK, HOTTOK), true);
  assertEquals(await hottokConfere(HOTTOK.replace("0", "1"), HOTTOK), false);
  assertEquals(await hottokConfere(HOTTOK + "x", HOTTOK), false);
  assertEquals(await hottokConfere("", HOTTOK), false);
  assertEquals(await hottokConfere(null, HOTTOK), false);
  assertEquals(await hottokConfere(HOTTOK, undefined), false);
  assertEquals(await hottokConfere(HOTTOK, ""), false);
});

Deno.test("método diferente de POST: 405 e nada gravado", async () => {
  const { handler, chamadas } = montar();
  const r = await handler(req(null, { "x-hotmart-hottok": HOTTOK }, "GET"));
  assertEquals(r.status, 405);
  assertEquals(chamadas.length, 0);
});

Deno.test("sem hottok no header: 401 e nada gravado", async () => {
  const { handler, chamadas } = montar();
  const r = await handler(req(payload(), {}));
  assertEquals(r.status, 401);
  assertEquals(chamadas.length, 0);
});

Deno.test("hottok errado: 401 e nada gravado", async () => {
  const { handler, chamadas, logs } = montar();
  const r = await handler(req(payload(), { "x-hotmart-hottok": "errado" }));
  assertEquals(r.status, 401);
  assertEquals(chamadas.length, 0);
  semPii(logs);
});

Deno.test("hottok no corpo não vale (só o header)", async () => {
  const { handler, chamadas } = montar();
  const r = await handler(req({ ...payload(), hottok: HOTTOK }, {}));
  assertEquals(r.status, 401);
  assertEquals(chamadas.length, 0);
});

Deno.test("segredo não configurado: 503 (fail-closed) mesmo com header", async () => {
  for (const vazio of [undefined, ""]) {
    const { handler, chamadas } = montar({ hottok: vazio });
    const r = await handler(req(payload(), { "x-hotmart-hottok": "" }));
    assertEquals(r.status, 503);
    assertEquals(chamadas.length, 0);
  }
});

Deno.test("corpo grande pelo content-length: 413 e nada gravado", async () => {
  const { handler, chamadas } = montar();
  const r = await handler(req(payload(), { "x-hotmart-hottok": HOTTOK, "content-length": String(MAX_BYTES + 1) }));
  assertEquals(r.status, 413);
  assertEquals(chamadas.length, 0);
});

Deno.test("corpo grande sem content-length (stream): 413 e nada gravado", async () => {
  const { handler, chamadas } = montar();
  const grande = new TextEncoder().encode(JSON.stringify({ ...payload(), lixo: "x".repeat(MAX_BYTES) }));
  const stream = new ReadableStream({
    start(c) {
      for (let i = 0; i < grande.length; i += 4096) c.enqueue(grande.slice(i, i + 4096));
      c.close();
    },
  });
  const r = await handler(
    new Request("http://local/x", {
      method: "POST",
      headers: { "x-hotmart-hottok": HOTTOK, "content-type": "application/json" },
      body: stream,
    }),
  );
  assertEquals(r.status, 413);
  assertEquals(chamadas.length, 0);
});

Deno.test("evento fora da lista: 200 ignorado e nada gravado", async () => {
  for (const event of ["PURCHASE_OUT_OF_SHOPPING_CART", "CLUB_FIRST_ACCESS", "SUBSCRIPTION_CANCELLATION", "purchase_approved"]) {
    const { handler, chamadas, logs } = montar();
    const r = await handler(req(payload({ event })));
    assertEquals(r.status, 200);
    assertEquals((await r.json()).ignorado, "evento");
    assertEquals(chamadas.length, 0);
    semPii(logs);
  }
});

Deno.test("versão errada: 200 ignorado e nada gravado", async () => {
  for (const version of ["1.0.0", "2.0", 2, undefined]) {
    const { handler, chamadas } = montar();
    const r = await handler(req(payload({ version })));
    assertEquals(r.status, 200);
    assertEquals((await r.json()).ignorado, "versao");
    assertEquals(chamadas.length, 0);
  }
});

Deno.test("sem transaction (ou fora do formato): 200 ignorado e nada gravado", async () => {
  const p = payload();
  const semTx = { ...p, data: { ...p.data, purchase: { ...p.data.purchase, transaction: undefined } } };
  const txRuim = { ...p, data: { ...p.data, purchase: { ...p.data.purchase, transaction: "x'; drop table y; --" } } };
  for (const corpo of [semTx, txRuim, { ...p, data: null }]) {
    const { handler, chamadas } = montar();
    const r = await handler(req(corpo));
    assertEquals(r.status, 200);
    assertEquals((await r.json()).ignorado, "transacao");
    assertEquals(chamadas.length, 0);
  }
});

Deno.test("sem status ou sem creation_date: 200 ignorado e nada gravado", async () => {
  const p = payload();
  const semStatus = { ...p, data: { ...p.data, purchase: { ...p.data.purchase, status: "" } } };
  assertEquals(validar(semStatus), { ok: false, motivo: "status" });
  assertEquals(validar({ ...p, creation_date: undefined }), { ok: false, motivo: "creation_date" });
  assertEquals(validar({ ...p, creation_date: "ontem" }), { ok: false, motivo: "creation_date" });
  const { handler, chamadas } = montar();
  assertEquals((await handler(req(semStatus))).status, 200);
  assertEquals(chamadas.length, 0);
});

Deno.test("JSON inválido ou corpo que não é objeto", async () => {
  const { handler, chamadas } = montar();
  assertEquals((await handler(req("{nao é json"))).status, 400);
  const r = await handler(req([1, 2, 3]));
  assertEquals(r.status, 200);
  assertEquals((await r.json()).ignorado, "formato");
  assertEquals(chamadas.length, 0);
});

Deno.test("válido: grava 1 vez, com a conta fixa do código (nunca a do corpo)", async () => {
  const { handler, chamadas, logs } = montar();
  const r = await handler(req(payload()));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { ok: true, gravado: true });
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].conta, CONTA);
  assertEquals(CONTA, "escritorio");
  semPii(logs);
});

Deno.test("reenvio igual: 200 com gravado false (o banco devolve 0)", async () => {
  const { handler } = montar({ retorno: 0 });
  const r = await handler(req(payload()));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { ok: true, gravado: false });
});

Deno.test("todos os eventos da lista são aceitos", () => {
  assertEquals(EVENTOS.size, 9);
  for (const event of EVENTOS) assert(validar(payload({ event })).ok, event);
});

Deno.test("falha no banco: 500 (Hotmart reenvia) e log só com o código, sem payload", async () => {
  const erro = Object.assign(new Error(`valor inválido para ${EMAIL} ${NOME}`), { code: "23505" });
  const { handler, logs } = montar({ falha: erro });
  const r = await handler(req(payload()));
  assertEquals(r.status, 500);
  assertEquals(await r.json(), { erro: "falha interna" });
  assert(logs.some((l) => l.includes("23505")));
  semPii(logs);
});

// ---- 2ª rodada (pentest 13/10/2026): linha envenenada não pode chegar ao banco ----

function comCompra(purchase: Record<string, unknown>, extra: Record<string, unknown> = {}) {
  const p = payload(extra);
  return { ...p, data: { ...p.data, purchase: { ...p.data.purchase, ...purchase } } };
}

Deno.test("content-type diferente de application/json: 415 e nada gravado", async () => {
  assertEquals(ehJson("application/json"), true);
  assertEquals(ehJson("application/json; charset=utf-8"), true);
  assertEquals(ehJson("Application/JSON"), true);
  for (const ct of ["text/plain", "application/x-www-form-urlencoded", "application/jsonp", ""]) {
    const { handler, chamadas } = montar();
    const r = await handler(req(payload(), { "x-hotmart-hottok": HOTTOK, "content-type": ct }));
    assertEquals(r.status, 415, ct);
    assertEquals(chamadas.length, 0);
  }
});

Deno.test("price.value inválido (string, 'NaN', gigante, notação científica, negativo, tipo errado): 200 ignorado", async () => {
  // texto cru no corpo, como chegaria pela rede: 1e400 vira Infinity no JSON.parse
  for (const value of ['"abc"', '"1000"', '"NaN"', "1e13", "1e300", "1e400", "-1", "true", '{"v":1}', "[1]"]) {
    const corpo = JSON.stringify(comCompra({ price: { value: "__V__" } })).replace('"__V__"', value);
    const { handler, chamadas, logs } = montar();
    const r = await handler(req(corpo));
    assertEquals(r.status, 200, String(value));
    assertEquals((await r.json()).ignorado, "price.value", String(value));
    assertEquals(chamadas.length, 0);
    semPii(logs);
  }
  assertEquals(validar(comCompra({ price: "1000" })), { ok: false, motivo: "price" });
  assertEquals(validar(comCompra({ price: { value: 999_999_999_999.99 } })).ok, true);
  assertEquals(validar(comCompra({ price: { value: 0 } })).ok, true);
  assertEquals(validar(comCompra({ price: undefined })).ok, true); // ausente é aceito (evento sem preço)
});

Deno.test("datas inválidas (string, decimal, negativa, antes de 2000, futura > 1 dia, gigante): 200 ignorado", async () => {
  const agora = 1_760_380_000_000;
  for (const v of ["1760380000000", 1760380000000.5, -1, 0, 946_684_799_999, agora + UM_DIA_MS + 1, 1e16, true]) {
    assertEquals(validar(comCompra({}, { creation_date: v }), agora), { ok: false, motivo: "creation_date" }, String(v));
    assertEquals(validar(comCompra({ order_date: v }, { creation_date: agora }), agora), { ok: false, motivo: "order_date" });
    assertEquals(validar(comCompra({ approved_date: v }, { creation_date: agora }), agora), {
      ok: false,
      motivo: "approved_date",
    });
  }
  assertEquals(validar(comCompra({ order_date: agora + UM_DIA_MS }, { creation_date: agora + UM_DIA_MS }), agora).ok, true);
  const futura = Date.now() + 2 * UM_DIA_MS;
  const { handler, chamadas } = montar();
  const r = await handler(req(comCompra({}, { creation_date: futura })));
  assertEquals(r.status, 200);
  assertEquals((await r.json()).ignorado, "creation_date");
  assertEquals(chamadas.length, 0);
});

Deno.test("recurrence_number inválido (string, decimal, negativo, grande): 200 ignorado", () => {
  for (const v of ["1", 1.5, -1, 10_001, 2 ** 31]) {
    assertEquals(validar(comCompra({ recurrence_number: v })), { ok: false, motivo: "recurrence_number" }, String(v));
  }
  assertEquals(validar(comCompra({ recurrence_number: 12 })).ok, true);
});

Deno.test("commissions inválidas (não lista, item não objeto, valor string/gigante): 200 ignorado", () => {
  const p = payload();
  const com = (commissions: unknown) => ({ ...p, data: { ...p.data, commissions } });
  for (const c of ["x", { source: "PRODUCER" }, [1], [{ source: "PRODUCER", value: "900" }], [{ source: "PRODUCER", value: 1e13 }]]) {
    assertEquals(validar(com(c)), { ok: false, motivo: "commissions" }, JSON.stringify(c));
  }
  assertEquals(validar(com([{ source: "PRODUCER", value: 900 }, { source: "MARKETPLACE" }])).ok, true);
});

Deno.test("currency_value fora do formato: 200 ignorado", () => {
  assertEquals(validar(comCompra({ price: { value: 1, currency_value: 1 } })), { ok: false, motivo: "currency_value" });
  assertEquals(validar(comCompra({ price: { value: 1, currency_value: "x".repeat(11) } })), {
    ok: false,
    motivo: "currency_value",
  });
});

Deno.test("banco recusa com 22023 (mesma regra): 200 ignorado, nunca 500", async () => {
  const { handler, logs } = montar({ falha: Object.assign(new Error(`recusado ${EMAIL}`), { code: "22023" }) });
  const r = await handler(req(payload()));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { ok: true, gravado: false, ignorado: "recusado_pelo_banco" });
  semPii(logs);
});
