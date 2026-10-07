// Regras puras de arquivo do WhatsApp do CRM (migration 20261007140044). Sem Deno, sem rede: testadas pelo vitest do web
// (web/modules/comercial/infrastructure/midia-edge.test.ts) e usadas pela Edge crm-whatsapp-enviar.

/** Extensão gravada no Storage (<conversa>/<mensagem>.<ext>). Desconhecido = "bin". */
const EXTENSOES: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
  "audio/ogg": "ogg", "audio/opus": "opus", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/amr": "amr",
  "audio/webm": "weba", "audio/wav": "wav", "audio/x-wav": "wav",
  "video/mp4": "mp4", "video/3gpp": "3gp", "video/quicktime": "mov", "video/webm": "webm",
  "application/pdf": "pdf", "text/plain": "txt", "text/csv": "csv", "application/zip": "zip",
  "application/msword": "doc", "application/vnd.ms-excel": "xls", "application/vnd.ms-powerpoint": "ppt",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
};

/** "audio/ogg; codecs=opus" → "audio/ogg" (minúsculo, sem parâmetros). */
export function mimeBase(mime: string | null | undefined): string {
  return String(mime ?? "").split(";")[0].trim().toLowerCase();
}

export function extensaoDoMime(mime: string | null | undefined): string {
  return EXTENSOES[mimeBase(mime)] ?? "bin";
}

/**
 * Content-Type com que o arquivo fica no Storage (e é servido pela URL assinada). Só tipos conhecidos e inofensivos;
 * o resto (HTML, SVG, executável…) vira application/octet-stream — o navegador baixa em vez de interpretar.
 */
export function mimeSeguro(mime: string | null | undefined): string {
  const m = mimeBase(mime);
  return m in EXTENSOES ? m : "application/octet-stream";
}

/**
 * URL de download da mídia recebida. A chave da Infobip só vai para o host configurado (crm.config.infobip_base_url):
 * da URL que veio no webhook aproveitamos só caminho e query sob /whatsapp/. Fora disso (outro host, ..) = null.
 */
export function urlDownloadInfobip(url: string | null | undefined, baseUrl: string): string | null {
  let u: URL;
  try { u = new URL(String(url ?? "")); } catch { return null; }
  if (u.protocol !== "https:" || !/(^|\.)infobip\.com$/i.test(u.hostname)) return null;
  // formato documentado: /whatsapp/1/senders/<num>/media/<id>; aceita outra versão da API, mas só sob /whatsapp/
  if (!/^\/whatsapp\/[A-Za-z0-9._~%/-]{1,400}$/.test(u.pathname) || u.pathname.includes("..")) return null;
  return baseUrl.replace(/\/+$/, "") + u.pathname + u.search;
}

/** Nome do arquivo no Content-Disposition (filename* RFC 5987 ou filename). Sem barra nem caractere de controle. */
export function nomeDoContentDisposition(h: string | null | undefined): string | null {
  const s = String(h ?? "");
  let nome: string | null = null;
  const estrela = /filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)/.exec(s);
  if (estrela) {
    try { nome = decodeURIComponent(estrela[1].trim()); } catch { nome = null; }
  }
  if (!nome) {
    const simples = /filename\s*=\s*"([^"]*)"|filename\s*=\s*([^;]+)/.exec(s);
    nome = simples ? (simples[1] ?? simples[2] ?? "").trim() : null;
  }
  // deno-lint-ignore no-control-regex
  const limpo = (nome ?? "").replace(/[\\/\u0000-\u001f\u007f]/g, "_").trim().slice(0, 200);
  return limpo || null;
}

/** Caminho no bucket crm-midia: <conversa>/<mensagem>.<ext> (o banco confere o mesmo padrão). */
export function caminhoRecebido(conversaId: string, mensagemId: string, mime: string | null | undefined): string {
  return `${conversaId}/${mensagemId}.${extensaoDoMime(mime)}`;
}

/** Tamanho legível para o motivo de "grande demais" (pt-BR). */
export function mb(bytes: number): string {
  return `${(bytes / 1048576).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} MB`;
}

export type SaidaMidia = { tipo: string; de: string; para: string; mensagem_id: string; legenda: string | null; midia_nome: string | null };

/** Chamada da Infobip para imagem/documento: caminho da API e corpo (mediaUrl = URL assinada do Storage). */
export function pedidoMidiaInfobip(m: SaidaMidia, mediaUrl: string): { caminho: string; corpo: Record<string, unknown> } {
  const legenda = m.legenda?.trim() ? m.legenda.trim().slice(0, 1024) : undefined;
  const base = { from: m.de, to: m.para, messageId: m.mensagem_id, callbackData: m.mensagem_id };
  if (m.tipo === "imagem") {
    return { caminho: "/whatsapp/1/message/image", corpo: { ...base, content: { mediaUrl, ...(legenda ? { caption: legenda } : {}) } } };
  }
  return {
    caminho: "/whatsapp/1/message/document",
    corpo: { ...base, content: { mediaUrl, filename: (m.midia_nome || "documento.pdf").slice(0, 240), ...(legenda ? { caption: legenda } : {}) } },
  };
}
