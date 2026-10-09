// Regras puras do envio pela Evolution API v2 (migration 20261008152212). Sem Deno, sem rede: testadas pelo vitest do web
// (web/modules/comercial/infrastructure/evolution-envio.test.ts) e usadas pela Edge crm-evolution-enviar.

export type FilaEvolution = {
  mensagem_id: string; instancia: string; para: string; tipo: string; texto: string;
  midia_caminho: string | null; midia_nome: string | null; midia_mime: string | null; legenda: string | null;
};

/** Base da Evolution: só https, sem caminho/query (o que vem do Vault não pode virar outro destino). */
export function baseEvolution(url: string | null | undefined): string | null {
  let u: URL;
  try { u = new URL(String(url ?? "").trim()); } catch { return null; }
  if (u.protocol !== "https:" || u.username || u.password || u.search || u.hash) return null;
  if (u.pathname !== "/" && u.pathname !== "") return null;
  return `${u.protocol}//${u.host}`;
}

export const INSTANCIA_RE = /^crm-[a-z0-9-]{3,40}$/;

/** Mensagem citada (responder citando, migration 20261009153515): key.id + quem mandou + texto. */
export type Citacao = { key_id: string; from_me: boolean; texto: string | null; remote_jid?: string | null };

export const KEY_ID_RE = /^[A-Za-z0-9_-]{4,120}$/;

/**
 * JID que a própria Evolution monta para o número (espelho de createJid/formatBRNumber da v2): celular BR com DDD >= 31
 * e primeiro dígito >= 7 perde o 9 (o WhatsApp registrou esses números sem ele). Usado quando a busca do JID real falha
 * (a VPS não guarda mensagem: DATABASE_SAVE_DATA_NEW_MESSAGE=false).
 */
export function jidEvolution(telefone: string): string {
  const d = telefone.replace(/\D/g, "");
  const m = /^(55)(\d{2})9(\d{8})$/.exec(d);
  if (m && Number(m[2]) >= 31 && Number(m[3][0]) >= 7) return `${m[1]}${m[2]}${m[3]}@s.whatsapp.net`;
  return `${d}@s.whatsapp.net`;
}

/** "quoted" do sendText da Evolution v2: a key da citada e o texto (sem buscar a mensagem de novo). */
export function quotedEvolution(c: Citacao | null | undefined, para: string): Record<string, unknown> | null {
  if (!c || !KEY_ID_RE.test(c.key_id)) return null;
  const remoteJid = c.remote_jid && JID_RE.test(c.remote_jid) ? c.remote_jid : jidEvolution(para);
  return { key: { id: c.key_id, fromMe: c.from_me, remoteJid }, message: { conversation: (c.texto ?? "").slice(0, 1000) } };
}

/** Mensagem da fila → caminho + corpo da Evolution. Arquivo vai por URL assinada (a Evolution baixa). */
export function pedidoEvolution(m: FilaEvolution, urlArquivo: string | null, citacao?: Citacao | null): { caminho: string; corpo: Record<string, unknown> } | null {
  if (!INSTANCIA_RE.test(m.instancia) || !/^\d{10,15}$/.test(m.para)) return null;
  const inst = encodeURIComponent(m.instancia);
  if (m.tipo === "texto") {
    const corpo: Record<string, unknown> = { number: m.para, text: m.texto };
    const q = quotedEvolution(citacao, m.para);
    if (q) corpo.quoted = q;
    return { caminho: `/message/sendText/${inst}`, corpo };
  }
  if (!urlArquivo) return null;
  if (m.tipo === "audio") return { caminho: `/message/sendWhatsAppAudio/${inst}`, corpo: { number: m.para, audio: urlArquivo } };
  if (m.tipo === "imagem" || m.tipo === "documento") {
    const corpo: Record<string, unknown> = {
      number: m.para, mediatype: m.tipo === "imagem" ? "image" : "document", media: urlArquivo,
      mimetype: m.midia_mime ?? (m.tipo === "imagem" ? "image/jpeg" : "application/pdf"),
    };
    if (m.legenda) corpo.caption = m.legenda;
    if (m.tipo === "documento") corpo.fileName = m.midia_nome ?? "documento.pdf";
    return { caminho: `/message/sendMedia/${inst}`, corpo };
  }
  return null;
}

/** key.id da mensagem enviada (resposta da Evolution). */
export function idDaResposta(d: unknown): string | null {
  const o = d && typeof d === "object" ? (d as Record<string, unknown>) : null;
  const key = o?.key && typeof o.key === "object" ? (o.key as Record<string, unknown>) : null;
  const id = typeof key?.id === "string" ? key.id : null;
  return id && /^[A-Za-z0-9_-]{4,120}$/.test(id) ? id : null;
}

/** Erro legível (sem telefone) a partir da resposta de erro da Evolution. */
export function erroDaResposta(status: number, d: unknown): string {
  const o = d && typeof d === "object" ? (d as Record<string, unknown>) : null;
  const resp = o?.response && typeof o.response === "object" ? (o.response as Record<string, unknown>) : null;
  const msg = resp?.message;
  if (Array.isArray(msg) && msg.some((x) => x && typeof x === "object" && (x as Record<string, unknown>).exists === false)) {
    return "Este número não tem WhatsApp.";
  }
  const texto = Array.isArray(msg) ? msg.filter((x) => typeof x === "string").join("; ") : typeof msg === "string" ? msg : String(o?.error ?? "");
  if (status === 401 || status === 403) return "A Evolution recusou a chave (conferir evolution_api_key).";
  if (status === 404) return "Instância não encontrada na Evolution (reconecte o número).";
  const limpo = texto.replace(/\d[\d.\-\s]{8,}\d/g, "***").slice(0, 200);
  return `Evolution HTTP ${status}${limpo ? `: ${limpo}` : ""}`;
}

/** Classifica a resposta: o banco decide o status final (crm.evolution_fila_resultado). */
export function classificar(status: number): "ok" | "reenfileirar" | "incerta" | "falhou" {
  if (status >= 200 && status <= 299) return "ok";
  if (status === 429) return "reenfileirar";
  if (status === 0 || status >= 500) return "incerta";
  return "falhou";
}

/** Pausa entre mensagens do MESMO número (anti-ban): 1,2 s a 2,4 s. */
export function pausaMs(aleatorio: number): number {
  return 1200 + Math.floor(Math.max(0, Math.min(1, aleatorio)) * 1200);
}

// ── Editar / apagar para todos (migration 20261009153515) ──

export type AcaoEvolution = { acao_id: string; tipo: string; instancia: string; telefone: string; key_id: string; texto: string | null };

export const JID_RE = /^\d{10,15}@s\.whatsapp\.net$/;

/**
 * JID real da conversa a partir do POST /chat/findMessages (o telefone gravado no CRM tem o 9 do celular; o JID de
 * número antigo pode não ter). Aceita a resposta paginada da v2 ({messages:{records}}) ou lista direta.
 */
export function jidDaBusca(d: unknown, keyId: string): string | null {
  const o = d && typeof d === "object" ? (d as Record<string, unknown>) : null;
  const msgs = o?.messages && typeof o.messages === "object" ? (o.messages as Record<string, unknown>) : null;
  const lista = Array.isArray(d) ? d : Array.isArray(msgs?.records) ? msgs!.records as unknown[] : Array.isArray(o?.records) ? o!.records as unknown[] : [];
  for (const x of lista) {
    const key = x && typeof x === "object" ? (x as Record<string, unknown>).key : null;
    const k = key && typeof key === "object" ? (key as Record<string, unknown>) : null;
    if (k?.id === keyId && typeof k.remoteJid === "string" && JID_RE.test(k.remoteJid)) return k.remoteJid;
  }
  return null;
}

/** Corpo da busca da mensagem pela key (para achar o JID real). */
export function buscaMensagem(instancia: string, keyId: string): { caminho: string; corpo: Record<string, unknown> } | null {
  if (!INSTANCIA_RE.test(instancia) || !KEY_ID_RE.test(keyId)) return null;
  return { caminho: `/chat/findMessages/${encodeURIComponent(instancia)}`, corpo: { where: { key: { id: keyId } } } };
}

/**
 * Ação → pedido da Evolution v2. Editar: POST /chat/updateMessage {number, text, key{id, remoteJid, fromMe}}.
 * Apagar para todos: DELETE /chat/deleteMessageForEveryone {id, remoteJid, fromMe}. Só mensagem nossa (fromMe = true).
 */
export function pedidoAcao(a: AcaoEvolution, jid: string | null): { metodo: "POST" | "DELETE"; caminho: string; corpo: Record<string, unknown> } | null {
  if (!INSTANCIA_RE.test(a.instancia) || !KEY_ID_RE.test(a.key_id) || !/^\d{10,15}$/.test(a.telefone)) return null;
  const remoteJid = jid && JID_RE.test(jid) ? jid : jidEvolution(a.telefone);
  const inst = encodeURIComponent(a.instancia);
  if (a.tipo === "editar") {
    const texto = (a.texto ?? "").trim();
    if (!texto) return null;
    return { metodo: "POST", caminho: `/chat/updateMessage/${inst}`,
             corpo: { number: remoteJid.split("@")[0], text: texto, key: { id: a.key_id, remoteJid, fromMe: true } } };
  }
  if (a.tipo === "apagar") {
    return { metodo: "DELETE", caminho: `/chat/deleteMessageForEveryone/${inst}`, corpo: { id: a.key_id, remoteJid, fromMe: true } };
  }
  return null;
}
