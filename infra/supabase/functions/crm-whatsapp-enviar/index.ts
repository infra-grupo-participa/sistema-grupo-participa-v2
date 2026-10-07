// crm-whatsapp-enviar — saída do WhatsApp oficial (Infobip) do CRM Comercial (migration 20261006b, F4).
// Quem chama: o cron `crm-whatsapp-enviar` (1/min, ops.cron_post, ADR 0001) SÓ quando crm.whatsapp_fila_tem() é true.
// Corpo: {"acao":"enviar"} (padrão), {"acao":"templates"} (sincroniza templates do remetente; só LEITURA na Infobip) ou
// {"acao":"midia"} (baixa a mídia recebida para o Storage; só GET na Infobip).
//
// enviar: crm.whatsapp_fila_pegar(lote) já revalidou tudo no banco (kill-switch envio_ligado, opt-out, janela de 24 h,
//   template aprovado, número ativo, validade) e travou as mensagens (status 'enviando', SKIP LOCKED). Para cada uma:
//   POST na Infobip com messageId = id da mensagem no CRM (o relatório de entrega casa mesmo se a resposta se perder) e
//   crm.whatsapp_fila_resultado(id, http, grupo, erro, reenfileirar):
//     2xx + PENDING/DELIVERED → 'enviada' (aceita; entregue/lida só pelo relatório)   · 2xx + REJECTED / 4xx → 'falhou'
//     429 → volta para a fila com espera                                              · 5xx / rede / timeout → falha incerta
//     (NUNCA reenvia o que pode ter saído; o relatório corrige)
//   O que não coube no prazo volta para a fila sem custo (não saiu).
//   imagem/documento (migration 20261007140044): o arquivo está no bucket privado crm-midia; a Edge assina uma URL de 1 h
//   (service role) e manda /whatsapp/1/message/image|document com mediaUrl — a Infobip baixa dali. Sem assinatura = volta
//   para a fila (não saiu). Áudio gravado no CRM (migration 20261007s): /whatsapp/1/message/audio, mesmo fluxo.
//   Envio na hora (20261007s): crm_enviar_mensagem chama crm.whatsapp_disparar_envio() → ops.cron_post para esta Edge
//   logo depois do COMMIT; o cron de 1 min continua como reserva (SKIP LOCKED: os dois nunca pegam a mesma mensagem).
// templates: GET /whatsapp/2/senders/{remetente}/templates → crm.whatsapp_templates_sincronizar.
// midia: baixa a mídia RECEBIDA (crm.whatsapp_midia_pegar → GET na Infobip com a chave, só no host configurado → Storage
//   crm-midia/<conversa>/<mensagem>.<ext> → crm.whatsapp_midia_resultado). Acima de crm.config.midia_limite_bytes não
//   baixa (grava o motivo). Quem chama: a Edge do webhook logo depois de gravar e o cron crm-whatsapp-reprocessar (*/10).
//
// Segredos (Vault, nunca em código): infobip_api_key, crm_whatsapp_envio_chave — lidos por crm.whatsapp_credenciais_envio()
// (só o dono executa; conexão SUPABASE_DB_URL). Base URL vem de crm.config.infobip_base_url e é conferida aqui contra
// *.api(-xx).infobip.com (nada do corpo da requisição vira URL). Fail-closed: sem chave/remetente → 503 sem pegar fila.
import postgres from "npm:postgres@3.4.4";
import { caminhoRecebido, mb, mimeBase, mimeSeguro, nomeDoContentDisposition, pedidoMidiaInfobip, saidaComArquivo, urlDownloadInfobip } from "./midia.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false, idle_timeout: 20 });
const PRAZO_MS = 45_000;          // o cron chama com timeout de 60 s; sobra folga para gravar o resultado
const RQ_MAX_MS = 10_000;         // cada chamada à Infobip
const PARALELO = 4;               // mensagens em voo ao mesmo tempo (o lote vem de crm.config.envio_lote)
const BASE_OK = /^https:\/\/[a-z0-9]+\.api(-[a-z]+)?\.infobip\.com$/;
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "crm-midia";
const ASSINATURA_ENVIO_S = 3600;   // a Infobip baixa o anexo logo após o POST; 1 h cobre reentrega
const DOWNLOAD_MAX_MS = 25_000;    // cada arquivo recebido

type Obj = Record<string, unknown>;
type Fila = {
  mensagem_id: string; de: string; para: string; tipo: string; texto: string;
  template_nome: string | null; template_idioma: string | null; variaveis: unknown;
  midia_caminho: string | null; midia_nome: string | null; midia_mime: string | null; legenda: string | null;
};
type Pendente = {
  mensagem_id: string; conversa_id: string; url: string | null; tipo: string; mime: string | null; nome: string | null;
  limite_bytes: number | string;
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

// ── Storage (service role; nunca exposto) ──
function caminhoUrl(caminho: string): string {
  return caminho.split("/").map(encodeURIComponent).join("/");
}

async function assinar(caminho: string, segundos: number): Promise<string | null> {
  if (!SUPABASE_URL || !SERVICE_ROLE) return null;
  try {
    const r = await fetch(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET}/${caminhoUrl(caminho)}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE, "Content-Type": "application/json" },
      body: JSON.stringify({ expiresIn: segundos }),
      signal: AbortSignal.timeout(RQ_MAX_MS),
    });
    if (!r.ok) return null;
    const d = (await r.json().catch(() => null)) as Obj | null;
    const rel = String(d?.signedURL ?? d?.signedUrl ?? "");
    return rel ? `${SUPABASE_URL}/storage/v1${rel.startsWith("/") ? "" : "/"}${rel}` : null;
  } catch {
    return null;
  }
}

async function subir(caminho: string, mime: string, dados: Uint8Array): Promise<string | null> {
  if (!SUPABASE_URL || !SERVICE_ROLE) return "Storage não configurado na Edge.";
  try {
    const r = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}/${caminhoUrl(caminho)}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SERVICE_ROLE}`, apikey: SERVICE_ROLE, "Content-Type": mime, "x-upsert": "true",
                 "cache-control": "3600" },
      body: new Blob([dados as BlobPart], { type: mime }),
      signal: AbortSignal.timeout(DOWNLOAD_MAX_MS),
    });
    return r.ok ? null : `Storage HTTP ${r.status}`;
  } catch (e) {
    return (e instanceof Error && e.name === "TimeoutError") ? "Storage: timeout" : "Storage: falha de rede";
  }
}

async function enviarUma(cred: Cred, m: Fila): Promise<string> {
  const vars = Array.isArray(m.variaveis) ? (m.variaveis as unknown[]).map(String) : [];
  if (saidaComArquivo(m.tipo)) {
    const url = m.midia_caminho ? await assinar(m.midia_caminho, ASSINATURA_ENVIO_S) : null;
    if (!url) {
      // não saiu: volta para a fila (até 5 tentativas; o banco conta)
      const [x] = await sql`select crm.whatsapp_fila_resultado(${m.mensagem_id}::uuid, ${-1}, ${null}, ${"Não foi possível preparar o anexo."}, ${true}) as x`;
      return String(x?.x ?? "?");
    }
    const p = pedidoMidiaInfobip(m, url);
    const rm = await infobip(cred, "POST", p.caminho, p.corpo);
    const stm = statusDaResposta(rm.dados);
    const errom = rm.erro ?? (stm.grupo && !["PENDING", "DELIVERED"].includes(stm.grupo.toUpperCase()) ? stm.detalhe : null);
    const [x] = await sql`select crm.whatsapp_fila_resultado(${m.mensagem_id}::uuid, ${rm.http}, ${stm.grupo}, ${errom}, ${rm.http === 429}) as x`;
    return String(x?.x ?? "?");
  }
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

// ── Mídia recebida: Infobip → Storage ──
type Baixado = { ok: true; dados: Uint8Array; mime: string; nome: string | null } | { ok: false; resultado: string; erro: string; mime?: string; tamanho?: number };

async function baixar(cred: Cred, p: Pendente, limite: number): Promise<Baixado> {
  const url = urlDownloadInfobip(p.url, cred.base_url!);
  if (!url) return { ok: false, resultado: "falhou", erro: "Endereço do arquivo fora da Infobip." };
  let r: Response;
  try {
    r = await fetch(url, { headers: { Authorization: `App ${cred.api_key}` }, signal: AbortSignal.timeout(DOWNLOAD_MAX_MS) });
  } catch (e) {
    return { ok: false, resultado: "tentar", erro: (e instanceof Error && e.name === "TimeoutError") ? "Infobip: timeout" : "Infobip: falha de rede" };
  }
  const ct = mimeBase(r.headers.get("content-type"));
  const mime = ct && ct !== "application/octet-stream" ? ct : (mimeBase(p.mime) || ct);
  if (!r.ok) {
    await r.body?.cancel().catch(() => {});
    // 404/410: o arquivo não existe mais (a Infobip guarda 7 dias) — não adianta tentar de novo
    return { ok: false, resultado: r.status === 404 || r.status === 410 ? "falhou" : "tentar", erro: `Infobip HTTP ${r.status}` };
  }
  const declarado = Number(r.headers.get("content-length") ?? "0");
  if (declarado > limite) {
    await r.body?.cancel().catch(() => {});
    return { ok: false, resultado: "grande_demais", erro: `Arquivo de ${mb(declarado)} acima do limite de ${mb(limite)}.`, mime, tamanho: declarado };
  }
  // lê contando (Content-Length pode faltar ou mentir)
  const partes: Uint8Array[] = [];
  let total = 0;
  const leitor = r.body?.getReader();
  if (!leitor) return { ok: false, resultado: "tentar", erro: "Infobip: resposta sem corpo" };
  try {
    while (true) {
      const { done, value } = await leitor.read();
      if (done) break;
      total += value.byteLength;
      if (total > limite) {
        await leitor.cancel().catch(() => {});
        return { ok: false, resultado: "grande_demais", erro: `Arquivo acima do limite de ${mb(limite)}.`, mime, tamanho: total };
      }
      partes.push(value);
    }
  } catch {
    return { ok: false, resultado: "tentar", erro: "Infobip: download interrompido" };
  }
  if (total === 0) return { ok: false, resultado: "tentar", erro: "Infobip: arquivo vazio" };
  const dados = new Uint8Array(total);
  let pos = 0;
  for (const c of partes) { dados.set(c, pos); pos += c.byteLength; }
  return { ok: true, dados, mime, nome: nomeDoContentDisposition(r.headers.get("content-disposition")) };
}

async function baixarUma(cred: Cred, p: Pendente): Promise<string> {
  const limite = Number(p.limite_bytes) || 26_214_400;
  const b = await baixar(cred, p, limite);
  if (!b.ok) {
    const [x] = await sql`select crm.whatsapp_midia_resultado(${p.mensagem_id}::uuid, ${b.resultado}, ${null}, ${b.mime ?? null},
                                 ${b.tamanho ?? null}, ${null}, ${semSegredo(b.erro).slice(0, 280)}) as x`;
    return String(x?.x ?? "?");
  }
  const mime = mimeSeguro(b.mime);
  const caminho = caminhoRecebido(p.conversa_id, p.mensagem_id, mime);
  const erroUp = await subir(caminho, mime, b.dados);
  if (erroUp) {
    const [x] = await sql`select crm.whatsapp_midia_resultado(${p.mensagem_id}::uuid, ${"tentar"}, ${null}, ${null}, ${null}, ${null}, ${erroUp}) as x`;
    return String(x?.x ?? "?");
  }
  const [x] = await sql`select crm.whatsapp_midia_resultado(${p.mensagem_id}::uuid, ${"ok"}, ${caminho}, ${b.mime || mime},
                               ${b.dados.byteLength}, ${b.nome}, ${null}) as x`;
  return String(x?.x ?? "?");
}

async function midia(cred: Cred, inicio: number): Promise<Obj> {
  const cont: Record<string, number> = {};
  let pegas = 0;
  // lotes pequenos (arquivo de até 25 MB em memória); para antes do prazo do ciclo. O que sobrar o cron pega.
  while (Date.now() - inicio < PRAZO_MS - DOWNLOAD_MAX_MS) {
    const lote = (await sql`select * from crm.whatsapp_midia_pegar(2)`) as unknown as Pendente[];
    if (lote.length === 0) break;
    pegas += lote.length;
    const res = await Promise.all(lote.map((p) => baixarUma(cred, p).catch((e) => {
      // falha ao gravar: o arrendamento de 10 min devolve a mensagem para a fila
      console.error("crm-whatsapp-enviar: falha na mídia", semSegredo(e));
      return "erro_gravacao";
    })));
    for (const r of res) cont[r] = (cont[r] ?? 0) + 1;
  }
  return { pegas, resultado: cont };
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
    else if (corpo?.acao === "midia") acao = "midia";
  } catch { /* corpo vazio = enviar */ }

  try {
    const out = acao === "templates" ? await templates(cred) : acao === "midia" ? await midia(cred, inicio) : await enviar(cred, inicio);
    console.log("crm-whatsapp-enviar", acao, JSON.stringify(out), `${Date.now() - inicio} ms`);
    return json({ ok: true, acao, ...out });
  } catch (e) {
    console.error("crm-whatsapp-enviar: falha", acao, semSegredo(e));
    return json({ ok: false, msg: "Falha no ciclo." }, 500);
  }
});
