// Normalização PURA do webhook da Evolution API v2 (migration 20261008152212). Sem Deno, sem rede: testada pelo vitest
// do web (web/modules/comercial/infrastructure/evolution-webhook.test.ts) e usada pela Edge crm-evolution-webhook.
//
// Entra o corpo que a Evolution manda ({event, instance, data, ...}); sai uma lista de eventos no formato que
// crm.evolution_webhook(canal, eventos) entende, sem dado que o banco não precisa (o base64 do arquivo fica à parte,
// por índice, para a Edge subir no Storage depois que o banco disser onde).

export type EventoMensagem = {
  evento: 'mensagem';
  id: string;
  fromMe: boolean;
  telefone: string;
  nome: string | null;
  tipo: TipoMensagem;
  texto: string | null;
  mime: string | null;
  arquivo: string | null;
  em: string | null;
  temMidia: boolean;
};
export type EventoConexao = { evento: 'conexao'; estado: 'open' | 'close' | 'connecting'; numero: string | null; codigo: number | null; motivo: string | null };
export type EventoQr = { evento: 'qr'; base64: string };
/** O contato (ou o celular) editou uma mensagem: `id` é a key da mensagem ORIGINAL (migration 20261009153515). */
export type EventoEdicao = { evento: 'edicao'; id: string; texto: string };
/** O contato (ou o celular) apagou para todos: `id` é a key da mensagem apagada. */
export type EventoRevogacao = { evento: 'revogacao'; id: string };
export type Evento = EventoMensagem | EventoConexao | EventoQr | EventoEdicao | EventoRevogacao;

export type TipoMensagem =
  | 'texto' | 'imagem' | 'documento' | 'audio' | 'video' | 'localizacao' | 'contato' | 'botao' | 'figurinha' | 'outro';

export type Normalizado = {
  instancia: string | null;
  eventos: Evento[];
  /** base64 do arquivo por índice em `eventos` (só mensagem com mídia que veio no webhook). */
  arquivos: Record<number, string>;
  /** Por que cada item ficou de fora (só contagem no log). */
  ignorados: string[];
};

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj | null => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Obj) : null);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim() : null);

/** "messages.upsert" | "MESSAGES_UPSERT" | "messages-upsert" → "messages.upsert". */
export function nomeEvento(v: unknown): string {
  return String(v ?? '').trim().toLowerCase().replace(/[_-]/g, '.');
}

export const INSTANCIA_RE = /^crm-[a-z0-9-]{3,40}$/;
const ID_RE = /^[A-Za-z0-9_-]{4,120}$/;
const BASE64_RE = /^[A-Za-z0-9+/=\s]+$/;
/** QR e arquivo: tetos antes de qualquer decodificação. */
export const QR_MAX = 60_000;

/**
 * JID → telefone (só dígitos). Só conversa individual: grupo (@g.us), status/lista de transmissão (@broadcast),
 * canal (@newsletter) e @lid sem telefone alternativo ficam de fora (null + motivo).
 */
export function telefoneDoJid(key: Obj): { telefone: string | null; motivo: string | null } {
  const candidatos = [key.remoteJid, key.remoteJidAlt, key.senderPn].map(str).filter((x): x is string => !!x);
  const principal = candidatos[0] ?? '';
  if (principal.endsWith('@g.us')) return { telefone: null, motivo: 'grupo' };
  if (principal.includes('@broadcast')) return { telefone: null, motivo: 'broadcast' };
  if (principal.endsWith('@newsletter')) return { telefone: null, motivo: 'canal' };
  const pessoal = candidatos.find((j) => /@(s\.whatsapp\.net|c\.us)$/.test(j));
  if (!pessoal) return { telefone: null, motivo: principal.endsWith('@lid') ? 'lid_sem_telefone' : 'jid_desconhecido' };
  const digitos = pessoal.split('@')[0].split(':')[0].replace(/\D/g, '');
  return /^\d{10,15}$/.test(digitos) ? { telefone: celularBr(digitos), motivo: null } : { telefone: null, motivo: 'telefone_invalido' };
}

/** Celular BR em JID antigo (12 dígitos, sem o 9) → 13 dígitos, como o resto do CRM grava. Fixo e estrangeiro: igual. */
export function celularBr(d: string): string {
  return /^55[1-9][1-9][6-9]\d{7}$/.test(d) ? `${d.slice(0, 4)}9${d.slice(4)}` : d;
}

/** Tira os invólucros (efêmera, visualização única, documento com legenda, editada) até o conteúdo real. */
export function desembrulhar(m: Obj | null): Obj | null {
  let atual = m;
  for (let i = 0; i < 5 && atual; i++) {
    const w = obj(atual.ephemeralMessage) ?? obj(atual.viewOnceMessage) ?? obj(atual.viewOnceMessageV2)
      ?? obj(atual.viewOnceMessageV2Extension) ?? obj(atual.documentWithCaptionMessage);
    const dentro = w ? obj(w.message) : null;
    if (!dentro) break;
    // base64 que a Evolution põe no nível de fora acompanha o conteúdo de dentro
    atual = atual.base64 && !dentro.base64 ? { ...dentro, base64: atual.base64 } : dentro;
  }
  return atual;
}

type Conteudo = { tipo: TipoMensagem; texto: string | null; mime: string | null; arquivo: string | null; midia: boolean } | { ignorar: string };

/** Conteúdo da mensagem → tipo do CRM. Reação, apagar/editar (protocolo) e enquete não viram mensagem. */
export function conteudo(m: Obj): Conteudo {
  const texto = str(m.conversation) ?? str(obj(m.extendedTextMessage)?.text);
  if (texto) return { tipo: 'texto', texto, mime: null, arquivo: null, midia: false };
  const midia = (k: string, tipo: TipoMensagem): Conteudo | null => {
    const x = obj(m[k]);
    if (!x) return null;
    return { tipo, texto: str(x.caption), mime: str(x.mimetype), arquivo: str(x.fileName) ?? str(x.title), midia: true };
  };
  const r = midia('imageMessage', 'imagem') ?? midia('videoMessage', 'video') ?? midia('ptvMessage', 'video')
    ?? midia('audioMessage', 'audio') ?? midia('documentMessage', 'documento');
  if (r) return r;
  if (obj(m.stickerMessage)) return { tipo: 'figurinha', texto: null, mime: null, arquivo: null, midia: false };
  if (obj(m.locationMessage) || obj(m.liveLocationMessage)) return { tipo: 'localizacao', texto: null, mime: null, arquivo: null, midia: false };
  if (obj(m.contactMessage) || obj(m.contactsArrayMessage)) return { tipo: 'contato', texto: null, mime: null, arquivo: null, midia: false };
  const botao = str(obj(m.buttonsResponseMessage)?.selectedDisplayText) ?? str(obj(m.listResponseMessage)?.title)
    ?? str(obj(m.templateButtonReplyMessage)?.selectedDisplayText)
    ?? str(obj(obj(m.interactiveResponseMessage)?.body)?.text);
  if (botao) return { tipo: 'botao', texto: botao, mime: null, arquivo: null, midia: false };
  if (obj(m.reactionMessage)) return { ignorar: 'reacao' };
  if (obj(m.protocolMessage) || obj(m.editedMessage)) return { ignorar: 'protocolo' };
  if (obj(m.pollUpdateMessage)) return { ignorar: 'voto' };
  if (obj(m.senderKeyDistributionMessage) && Object.keys(m).length <= 2) return { ignorar: 'chave' };
  return { tipo: 'outro', texto: null, mime: null, arquivo: null, midia: false };
}

function emIso(ts: unknown): string | null {
  const n = typeof ts === 'number' ? ts : typeof ts === 'string' && /^\d{9,13}$/.test(ts) ? Number(ts) : NaN;
  if (!Number.isFinite(n) || n <= 0) return null;
  const ms = n > 1e12 ? n : n * 1000;
  const d = new Date(ms);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** Uma mensagem do messages.upsert → evento (ou motivo de ignorar) + base64 do arquivo, se veio. */
export function normalizarMensagem(d: Obj): { evento: EventoMensagem; base64: string | null } | { alteracao: EventoEdicao | EventoRevogacao } | { ignorar: string } {
  const key = obj(d.key);
  if (!key) return { ignorar: 'sem_key' };
  const id = str(key.id);
  if (!id || !ID_RE.test(id)) return { ignorar: 'sem_id' };
  const { telefone, motivo } = telefoneDoJid(key);
  if (!telefone) return { ignorar: motivo ?? 'sem_telefone' };
  const m = desembrulhar(obj(d.message));
  if (!m) return { ignorar: 'sem_conteudo' };
  const p = alteracaoDoProtocolo(m);
  if (p) return { alteracao: p };
  const c = conteudo(m);
  if ('ignorar' in c) return { ignorar: c.ignorar };
  const fromMe = key.fromMe === true;
  const b64 = c.midia && typeof m.base64 === 'string' && m.base64.length > 0 && BASE64_RE.test(m.base64.slice(0, 200)) ? m.base64 : null;
  return {
    evento: {
      evento: 'mensagem', id, fromMe, telefone,
      nome: fromMe ? null : (str(d.pushName)?.slice(0, 160) ?? null),
      tipo: c.tipo, texto: c.texto ? c.texto.slice(0, 4096) : null,
      mime: c.mime ? c.mime.slice(0, 120) : null, arquivo: c.arquivo ? c.arquivo.slice(0, 200) : null,
      em: emIso(d.messageTimestamp), temMidia: !!b64,
    },
    base64: b64,
  };
}

/** Texto de uma mensagem editada (conversation, extendedTextMessage ou legenda de mídia). */
function textoEditado(m: Obj | null): string | null {
  if (!m) return null;
  return str(m.conversation) ?? str(obj(m.extendedTextMessage)?.text) ?? str(obj(m.imageMessage)?.caption)
    ?? str(obj(m.videoMessage)?.caption) ?? str(obj(m.documentMessage)?.caption);
}

/**
 * protocolMessage (dentro de messages.upsert ou o próprio corpo de messages.edited) → edição/revogação.
 * type 0/REVOKE = apagou para todos; 14/MESSAGE_EDIT = editou. Grupo fica de fora (como na mensagem).
 */
export function alteracaoDoProtocolo(m: Obj): EventoEdicao | EventoRevogacao | null {
  const pm = obj(m.protocolMessage) ?? obj(obj(obj(m.editedMessage)?.message)?.protocolMessage) ?? (obj(m.key) && 'type' in m ? m : null);
  if (!pm) return null;
  const key = obj(pm.key);
  const id = str(key?.id);
  if (!id || !ID_RE.test(id)) return null;
  if (String(key?.remoteJid ?? '').endsWith('@g.us')) return null;
  const tipo = pm.type;
  if (tipo === 0 || tipo === 'REVOKE') return { evento: 'revogacao', id };
  if (tipo === 14 || tipo === 'MESSAGE_EDIT') {
    const texto = textoEditado(obj(pm.editedMessage));
    return texto ? { evento: 'edicao', id, texto: texto.slice(0, 4096) } : null;
  }
  return null;
}

/** messages.delete → revogação (a Evolution manda a key espalhada: {id, remoteJid, fromMe, status:'DELETED'}). */
export function normalizarExclusao(d: Obj): EventoRevogacao | null {
  const k = obj(d.key) ?? d;
  const id = str(k.id) ?? str(d.keyId);
  if (!id || !ID_RE.test(id)) return null;
  if (String(k.remoteJid ?? '').endsWith('@g.us')) return null;
  return { evento: 'revogacao', id };
}

/** connection.update → estado; número do "wuid" (dono da sessão) quando abre. */
export function normalizarConexao(d: Obj): EventoConexao | null {
  const estado = str(d.state)?.toLowerCase();
  if (estado !== 'open' && estado !== 'close' && estado !== 'connecting') return null;
  const wuid = str(d.wuid);
  const numero = wuid ? wuid.split('@')[0].split(':')[0].replace(/\D/g, '') : '';
  const codigo = typeof d.statusReason === 'number' ? d.statusReason : null;
  return {
    evento: 'conexao', estado, numero: /^\d{10,15}$/.test(numero) ? celularBr(numero) : null,
    codigo: codigo === 200 ? null : codigo, motivo: null,
  };
}

/** qrcode.updated → QR (data URL PNG). "Limite de QR" vira conexão fechada com motivo. */
export function normalizarQr(d: Obj): EventoQr | EventoConexao | null {
  const q = obj(d.qrcode) ?? d;
  const b = str(q.base64);
  if (b && b.length <= QR_MAX && /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(b)) return { evento: 'qr', base64: b };
  if (str(d.message)) return { evento: 'conexao', estado: 'close', numero: null, codigo: null, motivo: 'QR expirou sem leitura. Gere outro.' };
  return null;
}

/** Corpo inteiro do webhook → eventos para o banco. */
export function normalizarWebhook(corpo: unknown): Normalizado {
  const c = obj(corpo);
  const saida: Normalizado = { instancia: null, eventos: [], arquivos: {}, ignorados: [] };
  if (!c) { saida.ignorados.push('corpo'); return saida; }
  const inst = str(c.instance) ?? str(obj(c.data)?.instance);
  saida.instancia = inst && INSTANCIA_RE.test(inst) ? inst : null;
  const ev = nomeEvento(c.event);
  const dados = c.data;
  if (ev === 'messages.upsert') {
    const lista = Array.isArray(dados) ? dados : Array.isArray(obj(dados)?.messages) ? (obj(dados)!.messages as unknown[]) : [dados];
    for (const item of lista.slice(0, 200)) {
      const o = obj(item);
      const r = o ? normalizarMensagem(o) : { ignorar: 'item' };
      if ('ignorar' in r) { saida.ignorados.push(r.ignorar); continue; }
      if ('alteracao' in r) { saida.eventos.push(r.alteracao); continue; }
      if (r.base64) saida.arquivos[saida.eventos.length] = r.base64;
      saida.eventos.push(r.evento);
    }
  } else if (ev === 'messages.edited' || ev === 'messages.update') {
    // messages.edited: o corpo é o protocolMessage (key + editedMessage). messages.update só vale se trouxer protocolo.
    const lista = Array.isArray(dados) ? dados : [dados];
    for (const item of lista.slice(0, 200)) {
      const o = obj(item);
      const r = o ? alteracaoDoProtocolo(obj(o.message) ?? o) : null;
      if (r) saida.eventos.push(r); else saida.ignorados.push(ev);
    }
  } else if (ev === 'messages.delete') {
    const lista = Array.isArray(dados) ? dados : [dados];
    for (const item of lista.slice(0, 200)) {
      const o = obj(item);
      const r = o ? normalizarExclusao(o) : null;
      if (r) saida.eventos.push(r); else saida.ignorados.push(ev);
    }
  } else if (ev === 'connection.update') {
    const r = obj(dados) ? normalizarConexao(obj(dados)!) : null;
    if (r) saida.eventos.push(r); else saida.ignorados.push('conexao');
  } else if (ev === 'qrcode.updated') {
    const r = obj(dados) ? normalizarQr(obj(dados)!) : null;
    if (r) saida.eventos.push(r); else saida.ignorados.push('qr');
  } else {
    saida.ignorados.push(`evento:${ev || '?'}`);
  }
  return saida;
}

// ── Arquivo recebido → Storage ──

const EXTENSOES: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
  'audio/ogg': 'ogg', 'audio/opus': 'opus', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/amr': 'amr',
  'video/mp4': 'mp4', 'video/3gpp': '3gp', 'video/quicktime': 'mov', 'video/webm': 'webm',
  'application/pdf': 'pdf', 'text/plain': 'txt', 'text/csv': 'csv', 'application/zip': 'zip',
  'application/msword': 'doc', 'application/vnd.ms-excel': 'xls', 'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
};

export function mimeBase(mime: string | null | undefined): string {
  return String(mime ?? '').split(';')[0].trim().toLowerCase();
}

/** Tipo com que o arquivo fica no Storage: só os conhecidos; o resto vira octet-stream (o navegador baixa). */
export function mimeSeguro(mime: string | null | undefined): string {
  const m = mimeBase(mime);
  return m in EXTENSOES ? m : 'application/octet-stream';
}

/** <conversa>/<mensagem>.<ext> — o mesmo padrão que crm.whatsapp_midia_resultado confere. */
export function caminhoArquivo(conversaId: string, mensagemId: string, mime: string | null | undefined): string {
  return `${conversaId}/${mensagemId}.${EXTENSOES[mimeBase(mime)] ?? 'bin'}`;
}

/** Tamanho em bytes de um base64 sem decodificar (para recusar antes). */
export function bytesDoBase64(b64: string): number {
  const s = b64.replace(/\s/g, '');
  const pad = s.endsWith('==') ? 2 : s.endsWith('=') ? 1 : 0;
  return Math.max(0, Math.floor((s.length * 3) / 4) - pad);
}
