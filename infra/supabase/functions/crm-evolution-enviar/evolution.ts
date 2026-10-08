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

/** Mensagem da fila → caminho + corpo da Evolution. Arquivo vai por URL assinada (a Evolution baixa). */
export function pedidoEvolution(m: FilaEvolution, urlArquivo: string | null): { caminho: string; corpo: Record<string, unknown> } | null {
  if (!INSTANCIA_RE.test(m.instancia) || !/^\d{10,15}$/.test(m.para)) return null;
  const inst = encodeURIComponent(m.instancia);
  if (m.tipo === "texto") return { caminho: `/message/sendText/${inst}`, corpo: { number: m.para, text: m.texto } };
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
