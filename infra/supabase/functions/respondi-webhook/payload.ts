// Payload do webhook do Respondi → respondente no formato da API (answers/form) que normaliza.resposta() já entende.
// Formato conferido em 21 payloads reais guardados em cs.formularios (08/10/2026):
//   { form: { form_id: <slug>, form_name }, respondent: { respondent_id: <uuid>, date: 'AAAA-MM-DD HH:MM:SS' (UTC),
//     status, score, answers: { <pergunta>: <valor> }, raw_answers: [{ question: { question_id, question_type,
//     question_title }, answer }] } }   (telefone: answer = { country, phone })
// Puro: sem rede, sem banco.
type Obj = Record<string, any>;

const SLUG = /^[A-Za-z0-9]{4,32}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATA = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}$/;
export const MAX_RESPOSTAS = 300;

export type Lido = { slug: string; uuid: string; respondente: Obj };

// null = payload fora do formato (vira 'invalida' no log, sem gravar nada).
export function ler(body: unknown): Lido | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const b = body as Obj;
  const slug = b.form?.form_id;
  const r = b.respondent;
  const uuid = r?.respondent_id;
  const raw = r?.raw_answers;
  if (typeof slug !== "string" || !SLUG.test(slug)) return null;
  if (typeof uuid !== "string" || !UUID.test(uuid)) return null;
  if (!Array.isArray(raw) || raw.length > MAX_RESPOSTAS) return null;
  // data fora do formato ou mais de 1 dia no futuro: não confia (a Edge usa a hora do recebimento)
  let data = typeof r.date === "string" && DATA.test(r.date) ? r.date.replace(" ", "T") + "Z" : null;
  if (data && !(Date.parse(data) <= Date.now() + 86_400_000)) data = null;
  const answers = raw
    .filter((a: unknown) => a && typeof a === "object" && (a as Obj).question && typeof (a as Obj).question === "object")
    .map((a: Obj) => ({
      field_slug: String(a.question.question_id ?? ""),
      field_type: String(a.question.question_type ?? ""),
      field_title: String(a.question.question_title ?? ""),
      value: valor(a.answer),
    }));
  return {
    slug,
    uuid: uuid.toLowerCase(),
    // created_at/updated_at: a API do Respondi devolve o mesmo relógio (UTC, sem fuso), e o sync grava assim.
    respondente: { uuid: uuid.toLowerCase(), created_at: data, updated_at: data, answers },
  };
}

// Telefone vem como { country, phone }: vira '+<país> <número>' (a API devolve texto; normaliza tira o que não é dígito).
function valor(v: unknown): unknown {
  if (v && typeof v === "object" && !Array.isArray(v)) {
    const o = v as Obj;
    if ("phone" in o && Object.keys(o).every((k) => k === "phone" || k === "country")) {
      return `+${String(o.country ?? "").replace(/\D/g, "")} ${String(o.phone ?? "")}`.trim();
    }
  }
  return v;
}
