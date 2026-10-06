// crm-whatsapp-enviar — saída do WhatsApp oficial (Infobip) do CRM Comercial (migration 20261006b, F4).
// Quem chama: o cron `crm-whatsapp-enviar` (1/min, ops.cron_post, ADR 0001) SÓ quando crm.whatsapp_fila_tem() é true.
// Corpo: {"acao":"enviar"} (padrão) ou {"acao":"templates"} (sincroniza templates do remetente; só LEITURA na Infobip).
//
// enviar: crm.whatsapp_fila_pegar(lote) já revalidou tudo no banco (kill-switch envio_ligado, opt-out, janela de 24 h,
//   template aprovado, número ativo, validade) e travou as mensagens (status 'enviando', SKIP LOCKED). Para cada uma:
//   POST na Infobip com messageId = id da mensagem no CRM (o relatório de entrega casa mesmo se a resposta se perder) e
//   crm.whatsapp_fila_resultado(id, http, grupo, erro, reenfileirar):
//     2xx + PENDING/DELIVERED → 'enviada' (aceita; entregue/lida só pelo relatório)   · 2xx + REJECTED / 4xx → 'falhou'
//     429 → volta para a fila com espera                                              · 5xx / rede / timeout → falha incerta
//     (NUNCA reenvia o que pode ter saído; o relatório corrige)
//   O que não coube no prazo volta para a fila sem custo (não saiu).
// templates: GET /whatsapp/2/senders/{remetente}/templates → crm.whatsapp_templates_sincronizar.
//
// Segredos (Vault, nunca em código): infobip_api_key, crm_whatsapp_envio_chave — lidos por crm.whatsapp_credenciais_envio()
// (só o dono executa; conexão SUPABASE_DB_URL). Base URL vem de crm.config.infobip_base_url e é conferida aqui contra
// *.api(-xx).infobip.com (nada do corpo da requisição vira URL). Fail-closed: sem chave/remetente → 503 sem pegar fila.
import postgres from "npm:postgres@3.4.4";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const PRAZO_MS = 45_000;          // o cron chama com timeout de 60 s; sobra folga para gravar o resultado
const RQ_MAX_MS = 10_000;         // cada chamada à Infobip
const PARALELO = 4;               // mensagens em voo ao mesmo tempo (o lote vem de crm.config.envio_lote)
const BASE_OK = /^https:\/\/[a-z0-9]+\.api(-[a-z]+)?\.infobip\.com$/;

type Obj = Record<string, unknown>;
type Fila = {
  mensagem_id: string; de: string; para: string; tipo: string; texto: string;
  template_nome: string | null; template_idioma: string | null; variaveis: unknown;
};
type Cred = { api_key: string | null; chave_envio: string | null; base_url: string | null; remetente: string | null };

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

async function credenciais(): Promise<Cred> {
  const [r] = await sql`select api_key, chave_envio, base_url, remetente from crm.whatsapp_credenciais_envio()`;
  return {
    api_key: r?.api_key ?? null, chave_envio: r?.chave_envio ?? null,
    base_url: r?.base_url ?? null, remetente: r?.remetente ?? null,
  };
}

// Uma chamada à Infobip. Resposta resumida: http (0 = sem resposta), grupo do status, erro legível (sem dado pessoal).
async function infobip(cred: Cred, metodo: string, caminho: string, corpo?: Obj, ms = RQ_MAX_MS):
  Promise<{ http: number; dados: Obj | null; erro: string | null }> {
  try {
    const r = await fetch(cred.base_url + caminho, {
      method: metodo,
      headers: { Authorization: `App ${cred.api_key}`, Accept: "application/json",
                 ...(corpo ? { "Content-Type": "application/json" } : {}) },
      body: corpo ? JSON.stringify(corpo) : undefined,
      signal: AbortSignal.timeout(ms),
    });
    const dados = (await r.json().catch(() => null)) as Obj | null;
    let erro: string | null = null;
    if (!r.ok) {
      const se = ((dados?.requestError as Obj | undefined)?.serviceException as Obj | undefined);
      erro = semSegredo(`HTTP ${r.status}${se?.text ? ": " + String(se.text) : ""}`).slice(0, 280);
    }
    return { http: r.status, dados, erro };
  } catch (e) {
    return { http: 0, dados: null, erro: (e instanceof Error && e.name === "TimeoutError") ? "timeout" : "falha de rede" };
  }
}

function statusDaResposta(dados: Obj | null): { grupo: string | null; detalhe: string | null } {
  const msg = Array.isArray(dados?.messages) ? (dados!.messages as Obj[])[0] : dados;
  const st = (msg?.status ?? null) as Obj | null;
  return {
    grupo: st?.groupName ? String(st.groupName) : null,
    detalhe: st ? semSegredo(`${st.name ?? ""} ${st.description ?? ""}`.trim()).slice(0, 280) : null,
  };
}

async function enviarUma(cred: Cred, m: Fila): Promise<string> {
  const vars = Array.isArray(m.variaveis) ? (m.variaveis as unknown[]).map(String) : [];
  const r = m.tipo === "template"
    ? await infobip(cred, "POST", "/whatsapp/1/message/template", {
        messages: [{
          from: m.de, to: m.para, messageId: m.mensagem_id, callbackData: m.mensagem_id,
          content: { templateName: m.template_nome, language: m.template_idioma ?? "pt_BR",
                     templateData: { body: { placeholders: vars } } },
        }],
      })
    : await infobip(cred, "POST", "/whatsapp/1/message/text", {
        from: m.de, to: m.para, messageId: m.mensagem_id, callbackData: m.mensagem_id, content: { text: m.texto },
      });
  const st = statusDaResposta(r.dados);
  const reenfileirar = r.http === 429;
  const erro = r.erro ?? (st.grupo && !["PENDING", "DELIVERED"].includes(st.grupo.toUpperCase()) ? st.detalhe : null);
  const [x] = await sql`select crm.whatsapp_fila_resultado(${m.mensagem_id}::uuid, ${r.http}, ${st.grupo}, ${erro}, ${reenfileirar}) as x`;
  return String(x?.x ?? "?");
}

async function enviar(cred: Cred, inicio: number): Promise<Obj> {
  const fila = (await sql`select * from crm.whatsapp_fila_pegar(null)`) as unknown as Fila[];
  const cont: Record<string, number> = {};
  let i = 0;
  const trabalhador = async () => {
    while (i < fila.length) {
      const m = fila[i++];
      let res: string;
      if (Date.now() - inicio > PRAZO_MS) {
        // não saiu: volta para a fila sem marcar falha (o próximo ciclo envia)
        const [x] = await sql`select crm.whatsapp_fila_resultado(${m.mensagem_id}::uuid, ${-1}, ${null}, ${"prazo do ciclo esgotado"}, ${true}) as x`;
        res = String(x?.x ?? "?");
      } else {
        try {
          res = await enviarUma(cred, m);
        } catch (e) {
          // falha ao GRAVAR o resultado: a mensagem fica 'enviando' e o próximo ciclo marca falha incerta (não reenvia)
          console.error("crm-whatsapp-enviar: falha ao gravar resultado", semSegredo(e));
          res = "erro_gravacao";
        }
      }
      cont[res] = (cont[res] ?? 0) + 1;
    }
  };
  await Promise.all(Array.from({ length: Math.min(PARALELO, fila.length) }, trabalhador));
  return { pegas: fila.length, resultado: cont };
}

async function templates(cred: Cred): Promise<Obj> {
  const r = await infobip(cred, "GET", `/whatsapp/2/senders/${encodeURIComponent(cred.remetente!)}/templates`, undefined, 20_000);
  if (r.http < 200 || r.http > 299 || !Array.isArray(r.dados?.templates)) {
    return { ok: false, msg: r.erro ?? "Resposta sem templates." };
  }
  const [x] = await sql`select crm.whatsapp_templates_sincronizar(${cred.remetente}, ${sql.json(r.dados!.templates as never)}) as x`;
  return (x?.x ?? {}) as Obj;
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  if (req.method !== "POST") return json({ ok: false, msg: "Método não permitido." }, 405);
  let cred: Cred;
  try {
    cred = await credenciais();
  } catch (e) {
    console.error("crm-whatsapp-enviar: falha ao ler credenciais", semSegredo(e));
    return json({ ok: false, msg: "Indisponível." }, 503);
  }
  if (!cred.chave_envio) return json({ ok: false, msg: "Envio não configurado." }, 503);
  const recebida = req.headers.get("x-crm-chave") ?? "";
  if (!igual(recebida, cred.chave_envio)) return json({ ok: false, msg: "Não autorizado." }, 401);
  if (!cred.api_key || !cred.remetente) return json({ ok: false, msg: "Infobip ou número de envio não configurados." }, 503);
  if (!cred.base_url || !BASE_OK.test(cred.base_url)) return json({ ok: false, msg: "Base URL da Infobip inválida." }, 503);

  let acao = "enviar";
  try {
    const corpo = (await req.json().catch(() => ({}))) as Obj;
    if (corpo?.acao === "templates") acao = "templates";
  } catch { /* corpo vazio = enviar */ }

  try {
    const out = acao === "templates" ? await templates(cred) : await enviar(cred, inicio);
    console.log("crm-whatsapp-enviar", acao, JSON.stringify(out), `${Date.now() - inicio} ms`);
    return json({ ok: true, acao, ...out });
  } catch (e) {
    console.error("crm-whatsapp-enviar: falha", acao, semSegredo(e));
    return json({ ok: false, msg: "Falha no ciclo." }, 500);
  }
});
