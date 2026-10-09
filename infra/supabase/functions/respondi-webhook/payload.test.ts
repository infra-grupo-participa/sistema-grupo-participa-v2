// deno test infra/supabase/functions/respondi-webhook/payload.test.ts
// Payload no formato do webhook do Respondi (dados fictícios) → mesma linha que o sync gravaria.
import { assertEquals } from "jsr:@std/assert@1";
import { resposta } from "../respondi-sync/normaliza.ts";
import { ler } from "./payload.ts";

const UUID = "00000000-0000-4000-8000-000000000001";
const payload = {
  form: { form_id: "AbCd1234", form_name: "[TESTE] Formulário fictício" },
  respondent: {
    respondent_id: UUID, date: "2026-10-09 12:34:56", status: "completed", score: null,
    answers: {},
    raw_answers: [
      { question: { question_id: "q1", question_type: "name", question_title: "Nome completo" }, answer: "Fulano de Tal" },
      { question: { question_id: "q2", question_type: "email", question_title: "E-mail" }, answer: " Fulano@Exemplo.com " },
      { question: { question_id: "q3", question_type: "phone", question_title: "Telefone (WhatsApp)" },
        answer: { country: "55", phone: "(11) 90000-0000" } },
      { question: { question_id: "q4", question_type: "radio", question_title: "Você estará acompanhado(a) na viagem?" },
        answer: "Não, irei sozinho(a)" },
    ],
  },
};

Deno.test("payload do webhook vira a linha de respondi.respostas", () => {
  const l = ler(payload)!;
  assertEquals(l.slug, "AbCd1234");
  assertEquals(l.uuid, UUID);
  const linha = resposta(l.respondente, l.slug, new Map(), "cadastro", null)!;
  assertEquals(linha.uuid, UUID);
  assertEquals(linha.respondido_em, "2026-10-09T12:34:56Z");
  assertEquals(linha.email, "fulano@exemplo.com");
  assertEquals(linha.telefone, "5511900000000");
  assertEquals(linha.respostas.length, 4);
  assertEquals(linha.respostas[3], { p: "Você estará acompanhado(a) na viagem?", v: "Não, irei sozinho(a)" });
});

Deno.test("payload fora do formato é recusado", () => {
  assertEquals(ler(null), null);
  assertEquals(ler([]), null);
  assertEquals(ler({ ...payload, form: { form_id: "x';drop" } }), null);
  assertEquals(ler({ ...payload, respondent: { ...payload.respondent, respondent_id: "1" } }), null);
  assertEquals(ler({ ...payload, respondent: { ...payload.respondent, raw_answers: new Array(301).fill({}) } }), null);
});

Deno.test("data fora do formato não é inventada", () => {
  const l = ler({ ...payload, respondent: { ...payload.respondent, date: "ontem" } })!;
  assertEquals(l.respondente.updated_at, null);
});

Deno.test("data no futuro não é aceita", () => {
  const l = ler({ ...payload, respondent: { ...payload.respondent, date: "2099-01-01 00:00:00" } })!;
  assertEquals(l.respondente.updated_at, null);
});
