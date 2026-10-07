// Remux WebM/Opus → Ogg/Opus, sem reencodar (migration 20261007s, áudio gravado no CRM).
// O WhatsApp só aceita nota de voz em audio/ogg (opus); o Chrome (e o Safari novo) gravam audio/webm;codecs=opus.
// Os pacotes Opus são os mesmos: aqui só trocamos o contêiner (RFC 7845). Regra pura: sem DOM, sem rede, testada no vitest.

const ID_SEGMENT = 0x18538067;
const ID_CLUSTER = 0x1f43b675;
const ID_TRACKS = 0x1654ae6b;
const ID_TRACK_ENTRY = 0xae;
const ID_AUDIO = 0xe1;
const ID_BLOCK_GROUP = 0xa0;
const MESTRES = new Set([ID_SEGMENT, ID_CLUSTER, ID_TRACKS, ID_TRACK_ENTRY, ID_AUDIO, ID_BLOCK_GROUP]);
const ID_TRACK_NUMBER = 0xd7;
const ID_CODEC_ID = 0x86;
const ID_CODEC_PRIVATE = 0x63a2;
const ID_CHANNELS = 0x9f;
const ID_SIMPLE_BLOCK = 0xa3;
const ID_BLOCK = 0xa1;

export class ErroAudio extends Error {}

// ── CRC da página Ogg: polinômio 0x04C11DB7, sem reflexão, início 0, sem xor final ──
const TABELA_CRC = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let r = i << 24;
    for (let j = 0; j < 8; j++) r = r & 0x80000000 ? (r << 1) ^ 0x04c11db7 : r << 1;
    t[i] = r >>> 0;
  }
  return t;
})();

export function crcOgg(dados: Uint8Array): number {
  let crc = 0;
  for (let i = 0; i < dados.length; i++) crc = ((crc << 8) ^ TABELA_CRC[((crc >>> 24) ^ dados[i]) & 0xff]) >>> 0;
  return crc >>> 0;
}

/** Amostras (a 48 kHz) de um pacote Opus, pelo byte TOC (RFC 6716 §3.1). 0 = pacote inválido. */
export function amostrasOpus(pacote: Uint8Array): number {
  if (pacote.length < 1) return 0;
  const toc = pacote[0];
  const config = toc >> 3;
  const ms = config < 12 ? [10, 20, 40, 60][config & 3] : config < 16 ? [10, 20][config & 1] : [2.5, 5, 10, 20][config & 3];
  const codigo = toc & 3;
  let quadros: number;
  if (codigo === 0) quadros = 1;
  else if (codigo === 1 || codigo === 2) quadros = 2;
  else {
    if (pacote.length < 2) return 0;
    quadros = pacote[1] & 0x3f;
  }
  const n = Math.round(ms * 48) * quadros;
  return n > 0 && n <= 5760 ? n : 0;
}

// ── EBML ──
type Vint = { valor: number; tam: number; desconhecido: boolean };

function lerId(b: Uint8Array, p: number): Vint | null {
  const x = b[p];
  if (x === undefined || x === 0) return null;
  const tam = x & 0x80 ? 1 : x & 0x40 ? 2 : x & 0x20 ? 3 : x & 0x10 ? 4 : 0;
  if (!tam || p + tam > b.length) return null;
  let v = 0;
  for (let i = 0; i < tam; i++) v = v * 256 + b[p + i];
  return { valor: v, tam, desconhecido: false };
}

function lerTamanho(b: Uint8Array, p: number): Vint | null {
  const x = b[p];
  if (x === undefined || x === 0) return null;
  let tam = 1;
  while (tam <= 8 && !(x & (0x80 >> (tam - 1)))) tam++;
  if (tam > 8 || p + tam > b.length) return null;
  let v = x & (0xff >> tam);
  let todos1 = v === 0xff >> tam;
  for (let i = 1; i < tam; i++) {
    v = v * 256 + b[p + i];
    if (b[p + i] !== 0xff) todos1 = false;
  }
  return { valor: v, tam, desconhecido: todos1 };
}

function uint(b: Uint8Array): number {
  let v = 0;
  for (const x of b) v = v * 256 + x;
  return v;
}

export type ResultadoRemux = { ogg: Uint8Array; duracaoMs: number; canais: number; pacotes: number };

/**
 * Converte o WebM do MediaRecorder (Segment e Cluster de tamanho desconhecido, SimpleBlock sem lacing) em Ogg/Opus.
 * Lança ErroAudio com mensagem para a tela quando não dá (sem faixa Opus, lacing, arquivo vazio).
 */
export function webmOpusParaOgg(webm: Uint8Array, opts: { serial?: number } = {}): ResultadoRemux {
  let faixaOpus: number | null = null;
  let faixaAtual: { numero: number | null; codec: string | null; privado: Uint8Array | null; canais: number | null } | null = null;
  let cabecalho: Uint8Array | null = null;
  let canais = 1;
  const pacotes: Uint8Array[] = [];

  const fecharFaixa = () => {
    if (faixaAtual && faixaAtual.codec === 'A_OPUS' && faixaOpus === null && faixaAtual.numero !== null) {
      faixaOpus = faixaAtual.numero;
      cabecalho = faixaAtual.privado;
      canais = faixaAtual.canais ?? 1;
    }
    faixaAtual = null;
  };

  let p = 0;
  while (p < webm.length) {
    const id = lerId(webm, p);
    if (!id) break;
    const tam = lerTamanho(webm, p + id.tam);
    if (!tam) break;
    const ini = p + id.tam + tam.tam;
    if (id.valor === ID_TRACK_ENTRY) { fecharFaixa(); faixaAtual = { numero: null, codec: null, privado: null, canais: null }; }
    else if (id.valor === ID_CLUSTER || id.valor === ID_TRACKS) fecharFaixa();
    if (MESTRES.has(id.valor)) { p = ini; continue; }   // entra no mestre (tamanho conhecido ou não): leitura linear
    if (tam.desconhecido) throw new ErroAudio('Gravação em formato inesperado.');
    const fim = ini + tam.valor;
    if (fim > webm.length) break;                       // último bloco cortado: fica de fora
    const dado = webm.subarray(ini, fim);
    switch (id.valor) {
      case ID_TRACK_NUMBER: if (faixaAtual) faixaAtual.numero = uint(dado); break;
      case ID_CODEC_ID: if (faixaAtual) faixaAtual.codec = new TextDecoder().decode(dado).replace(/\0+$/, ''); break;
      case ID_CODEC_PRIVATE: if (faixaAtual) faixaAtual.privado = dado.slice(); break;
      case ID_CHANNELS: if (faixaAtual) faixaAtual.canais = uint(dado); break;
      case ID_SIMPLE_BLOCK:
      case ID_BLOCK: {
        fecharFaixa();
        if (faixaOpus === null) throw new ErroAudio('A gravação não tem áudio Opus.');
        const faixa = lerTamanho(dado, 0);
        if (!faixa || faixa.valor !== faixaOpus) break;
        const flags = dado[faixa.tam + 2];
        if (flags === undefined) break;
        if ((flags >> 1) & 3) throw new ErroAudio('Gravação em formato inesperado (lacing).');
        const pacote = dado.slice(faixa.tam + 3);
        if (pacote.length) pacotes.push(pacote);
        break;
      }
    }
    p = fim;
  }
  fecharFaixa();
  if (faixaOpus === null) throw new ErroAudio('A gravação não tem áudio Opus.');
  if (!pacotes.length) throw new ErroAudio('A gravação ficou vazia.');

  const head = cabecalhoOpus(cabecalho, canais);
  canais = head[9] || canais;
  const r = escreverOgg(head, pacotes, opts.serial ?? 0x43524d31);
  return { ogg: r.ogg, duracaoMs: Math.round(r.amostras / 48), canais, pacotes: pacotes.length };
}

/** OpusHead do CodecPrivate (o Chrome grava); sem ele, monta um padrão (pre-skip 312, 48 kHz, família 0). */
function cabecalhoOpus(privado: Uint8Array | null, canais: number): Uint8Array {
  if (privado && privado.length >= 19 && new TextDecoder().decode(privado.subarray(0, 8)) === 'OpusHead') return privado;
  const h = new Uint8Array(19);
  h.set(new TextEncoder().encode('OpusHead'), 0);
  const v = new DataView(h.buffer);
  h[8] = 1;
  h[9] = Math.min(Math.max(canais, 1), 2);
  v.setUint16(10, 312, true);
  v.setUint32(12, 48000, true);
  v.setInt16(16, 0, true);
  h[18] = 0;
  return h;
}

function tags(): Uint8Array {
  const vendor = new TextEncoder().encode('grupoparticipa-crm');
  const t = new Uint8Array(8 + 4 + vendor.length + 4);
  t.set(new TextEncoder().encode('OpusTags'), 0);
  new DataView(t.buffer).setUint32(8, vendor.length, true);
  t.set(vendor, 12);
  return t; // 0 comentários (já zerado)
}

function lacing(n: number): number[] {
  const s: number[] = [];
  while (n >= 255) { s.push(255); n -= 255; }
  s.push(n);
  return s;
}

function pagina(pacotes: Uint8Array[], granulo: number, serial: number, seq: number, flags: number): Uint8Array {
  const segs = pacotes.flatMap((x) => lacing(x.length));
  const corpo = pacotes.reduce((s, x) => s + x.length, 0);
  const out = new Uint8Array(27 + segs.length + corpo);
  const v = new DataView(out.buffer);
  out.set([0x4f, 0x67, 0x67, 0x53], 0); // "OggS"
  out[4] = 0;
  out[5] = flags;
  v.setUint32(6, granulo % 0x100000000, true);
  v.setUint32(10, Math.floor(granulo / 0x100000000), true);
  v.setUint32(14, serial >>> 0, true);
  v.setUint32(18, seq, true);
  out[26] = segs.length;
  out.set(segs, 27);
  let p = 27 + segs.length;
  for (const x of pacotes) { out.set(x, p); p += x.length; }
  v.setUint32(22, crcOgg(out), true);
  return out;
}

const PACOTES_POR_PAGINA = 50; // ~1 s de áudio por página

function escreverOgg(head: Uint8Array, pacotes: Uint8Array[], serial: number): { ogg: Uint8Array; amostras: number } {
  const paginas: Uint8Array[] = [pagina([head], 0, serial, 0, 0x02), pagina([tags()], 0, serial, 1, 0)];
  let seq = 2;
  let amostras = 0;
  let atual: Uint8Array[] = [];
  let segs = 0;
  const fechar = (ultima: boolean) => {
    paginas.push(pagina(atual, amostras, serial, seq++, ultima ? 0x04 : 0));
    atual = [];
    segs = 0;
  };
  pacotes.forEach((x, i) => {
    const n = lacing(x.length).length;
    if (atual.length && (segs + n > 255 || atual.length >= PACOTES_POR_PAGINA)) fechar(false);
    atual.push(x);
    segs += n;
    amostras += amostrasOpus(x);
    if (i === pacotes.length - 1) fechar(true);
  });
  const total = paginas.reduce((s, x) => s + x.length, 0);
  const ogg = new Uint8Array(total);
  let p = 0;
  for (const x of paginas) { ogg.set(x, p); p += x.length; }
  return { ogg, amostras };
}
