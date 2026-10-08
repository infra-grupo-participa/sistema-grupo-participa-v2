// deno test infra/supabase/functions/crm-integracao-webhook/normaliza.test.ts --allow-net --allow-env
// Importa index.ts, que chama Deno.serve no topo (sem env do Supabase só responde 500; não toca banco). Por isso --allow-net.
import { assertEquals } from "jsr:@std/assert@1";
import { activecampaign, fonteDaRota, sendflow, tipoValido, unnichat } from "./index.ts";

const form = (o: Record<string, string>) => new URLSearchParams(o);
const base = {
  type: "subscribe",
  date_time: "2026-10-06 14:30:00",
  "contact[id]": "123",
  "contact[email]": "a@exemplo.invalid",
  "contact[first_name]": "Ana",
  list: "5",
  tag: "t1",
};

Deno.test("fonteDaRota: três fontes, resto null", () => {
  assertEquals(fonteDaRota("/crm-integracao-webhook/activecampaign"), "activecampaign");
  assertEquals(fonteDaRota("/crm-integracao-webhook/unnichat/"), "unnichat");
  assertEquals(fonteDaRota("/sendflow"), "sendflow");
  assertEquals(fonteDaRota("/crm-integracao-webhook/outra"), null);
  assertEquals(fonteDaRota("/"), null);
});

Deno.test("tipoValido: normaliza e rejeita vazio", () => {
  assertEquals(tipoValido(" Subscribe "), "subscribe");
  assertEquals(tipoValido("contact tag!added"), "contact_tag_added");
  assertEquals(tipoValido(""), null);
  assertEquals(tipoValido("   "), null);
  assertEquals(tipoValido("x".repeat(100))?.length, 60);
});

Deno.test("activecampaign: id estável e idempotente", () => {
  const a = activecampaign(form(base))!;
  const b = activecampaign(form({ ...base }))!;
  assertEquals(a.id, b.id);
  assertEquals(a.id, "123:subscribe:2026-10-06 14:30:00:5:t1");
  assertEquals(activecampaign(form({ ...base, date_time: "2026-10-06 14:31:00" }))!.id === a.id, false);
  assertEquals(a.email, "a@exemplo.invalid");
  assertEquals(a.nome, "Ana");
  assertEquals(a.tipo, "subscribe");
});

Deno.test("activecampaign: fuso aplicado quando a data não tem offset", () => {
  assertEquals(activecampaign(form(base))!.ocorreuEm, "2026-10-06T14:30:00-03:00");
  assertEquals(activecampaign(form(base), "+02:00")!.ocorreuEm, "2026-10-06T14:30:00+02:00");
});

Deno.test("activecampaign: data com offset ou Z é preservada", () => {
  assertEquals(activecampaign(form({ ...base, date_time: "2026-10-06T14:30:00+05:00" }))!.ocorreuEm, "2026-10-06T14:30:00+05:00");
  assertEquals(activecampaign(form({ ...base, date_time: "2026-10-06T14:30:00Z" }))!.ocorreuEm, "2026-10-06T14:30:00Z");
});

Deno.test("activecampaign: campos ausentes viram null", () => {
  const e = activecampaign(form({ type: "bounce", "contact[id]": "9" }))!;
  assertEquals(e.ocorreuEm, null);
  assertEquals(e.email, null);
  assertEquals(e.telefone, null);
  assertEquals(e.nome, null);
  assertEquals(e.lista, null);
  assertEquals(e.tag, null);
  assertEquals(e.id, "9:bounce::: ".slice(0, 10) === e.id ? e.id : "9:bounce:::");
  assertEquals(e.id, "9:bounce:::");
});

Deno.test("activecampaign: tipo inválido ou sem contato → null", () => {
  assertEquals(activecampaign(form({ ...base, type: "" })), null);
  assertEquals(activecampaign(form({ "contact[id]": "1" })), null);
  assertEquals(activecampaign(form({ type: "subscribe" })), null);
  assertEquals(activecampaign(form({ type: "subscribe", "contact[id]": "  " })), null);
});

Deno.test("unnichat: id estável, evento da URL, ausentes → null", () => {
  const corpo = { contact: { id: "u1", name: "Bia", email: "b@exemplo.invalid", phoneNumber: "5511999990000" }, event_date: "2026-10-06T10:00:00-03:00" };
  const a = unnichat(corpo, "Template_Enviado")!;
  assertEquals(a.id, "u1:template_enviado:2026-10-06T10:00:00-03:00");
  assertEquals(unnichat(corpo, "Template_Enviado")!.id, a.id);
  assertEquals(a.ocorreuEm, "2026-10-06T10:00:00-03:00");
  assertEquals(a.telefone, "5511999990000");
  const m = unnichat({ contact: { id: "u2" } }, "workbook")!;
  assertEquals([m.ocorreuEm, m.email, m.telefone, m.nome], [null, null, null, null]);
  assertEquals(unnichat(corpo, null), null);
  assertEquals(unnichat({ contact: {} }, "workbook"), null);
  assertEquals(unnichat({ event: "x", contact: { id: "u3" } }, null)!.tipo, "x");
});

Deno.test("sendflow: entrada e saída", () => {
  const d = { number: "+55 (11) 99999-0000", groupId: "g1", groupName: "Grupo A", campaignName: "C1", createdAt: "2026-10-06T10:00:00Z" };
  const ent = sendflow({ event: "member_joined", data: d })!;
  assertEquals(ent.tipo, "entrada");
  assertEquals(ent.id, "5511999990000:g1:entrada:2026-10-06T10:00:00Z");
  assertEquals([ent.telefone, ent.lista, ent.tag, ent.email], ["+55 (11) 99999-0000", "Grupo A", "C1", null]);
  const sai = sendflow({ event: "member_left", data: d })!;
  assertEquals(sai.tipo, "saida");
  assertEquals(sai.id, "5511999990000:g1:saida:2026-10-06T10:00:00Z");
  assertEquals(sendflow({ event: "member_removed", data: d })!.tipo, "saida");
  assertEquals(sendflow({ event: "member_joined", data: d })!.id, ent.id);
});

Deno.test("sendflow: evento desconhecido ou campos ausentes → null", () => {
  const d = { number: "5511", groupId: "g1" };
  assertEquals(sendflow({ event: "ping", data: d }), null);
  assertEquals(sendflow({ event: "join", data: { groupId: "g1" } }), null);
  assertEquals(sendflow({ event: "join", data: { number: "5511" } }), null);
  assertEquals(sendflow({ event: "join", data: d })!.ocorreuEm, null);
});
