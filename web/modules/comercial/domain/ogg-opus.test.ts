import { describe, expect, it } from 'vitest';
import { ErroAudio, amostrasOpus, crcOgg, webmOpusParaOgg } from './ogg-opus';

// ── WebM mínimo, no formato do MediaRecorder (Segment e Cluster com tamanho desconhecido, SimpleBlock sem lacing) ──
function idBytes(id: number): number[] {
  const b: number[] = [];
  let x = id;
  while (x > 0) { b.unshift(x & 0xff); x = Math.floor(x / 256); }
  return b;
}
function tamanho(n: number): number[] {
  if (n < 0x7f) return [0x80 | n];
  if (n < 0x3fff) return [0x40 | (n >> 8), n & 0xff];
  return [0x20 | (n >> 16), (n >> 8) & 0xff, n & 0xff];
}
const el = (id: number, dado: number[]) => [...idBytes(id), ...tamanho(dado.length), ...dado];
const desconhecido = (id: number) => [...idBytes(id), 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff];
const txt = (s: string) => Array.from(new TextEncoder().encode(s));

function opusHead(canais: number): number[] {
  return [...txt('OpusHead'), 1, canais, 0x38, 0x01, 0x80, 0xbb, 0, 0, 0, 0, 0];
}
function bloco(faixa: number, pacote: number[], lacing = 0): number[] {
  return el(0xa3, [0x80 | faixa, 0, 0, 0x80 | (lacing << 1), ...pacote]);
}
function webm(pacotes: number[][], o: { codec?: string; head?: boolean; lacing?: number; faixa?: number } = {}): Uint8Array {
  const faixa = o.faixa ?? 1;
  const entrada = el(0xae, [
    ...el(0xd7, [faixa]),
    ...el(0x86, txt(o.codec ?? 'A_OPUS')),
    ...(o.head === false ? [] : el(0x63a2, opusHead(1))),
    ...el(0xe1, [...el(0x9f, [1])]),
  ]);
  return new Uint8Array([
    ...el(0x1a45dfa3, el(0x4282, txt('webm'))),
    ...desconhecido(0x18538067),
    ...el(0x1549a966, el(0x2ad7b1, [0x0f, 0x42, 0x40])),
    ...el(0x1654ae6b, entrada),
    ...desconhecido(0x1f43b675),
    ...el(0xe7, [0]),
    ...pacotes.flatMap((p) => bloco(faixa, p, o.lacing ?? 0)),
  ]);
}

// ── leitor de Ogg para conferir a saída ──
type Pagina = { flags: number; granulo: number; serial: number; seq: number; pacotes: Uint8Array[]; crcOk: boolean };
function lerOgg(b: Uint8Array): Pagina[] {
  const out: Pagina[] = [];
  let p = 0;
  while (p < b.length) {
    expect(new TextDecoder().decode(b.subarray(p, p + 4))).toBe('OggS');
    const v = new DataView(b.buffer, b.byteOffset + p);
    const nsegs = b[p + 26];
    const segs = Array.from(b.subarray(p + 27, p + 27 + nsegs));
    const corpo = segs.reduce((s, x) => s + x, 0);
    const fim = p + 27 + nsegs + corpo;
    const copia = b.slice(p, fim);
    const crc = new DataView(copia.buffer).getUint32(22, true);
    copia.fill(0, 22, 26);
    const pacotes: Uint8Array[] = [];
    let q = p + 27 + nsegs;
    let atual: number[] = [];
    for (const s of segs) {
      atual.push(...b.subarray(q, q + s));
      q += s;
      if (s < 255) { pacotes.push(new Uint8Array(atual)); atual = []; }
    }
    out.push({
      flags: b[p + 5], granulo: v.getUint32(6, true) + v.getUint32(10, true) * 2 ** 32, serial: v.getUint32(14, true),
      seq: v.getUint32(18, true), pacotes, crcOk: crcOgg(copia) === crc,
    });
    p = fim;
  }
  return out;
}

describe('crcOgg', () => {
  it('é o CRC-32 do Ogg (poli 0x04C11DB7, início 0, sem xor final)', () => {
    expect(crcOgg(new TextEncoder().encode('123456789'))).toBe(0x89a1897f);
    expect(crcOgg(new Uint8Array())).toBe(0);
  });
});

describe('amostrasOpus', () => {
  it('lê a duração pelo TOC', () => {
    expect(amostrasOpus(new Uint8Array([0xf8]))).toBe(960);       // CELT 20 ms, 1 quadro
    expect(amostrasOpus(new Uint8Array([0xfb, 0x03]))).toBe(2880); // CELT 20 ms, código 3 com 3 quadros
    expect(amostrasOpus(new Uint8Array([0x09]))).toBe(1920);       // SILK 20 ms, código 1 (2 quadros de 20 ms)
    expect(amostrasOpus(new Uint8Array([0x18]))).toBe(2880);       // SILK 60 ms
    expect(amostrasOpus(new Uint8Array([0x70]))).toBe(480);        // híbrido 10 ms
    expect(amostrasOpus(new Uint8Array([0x80]))).toBe(120);        // CELT 2,5 ms
    expect(amostrasOpus(new Uint8Array([]))).toBe(0);
    expect(amostrasOpus(new Uint8Array([0xfb]))).toBe(0);          // código 3 sem contagem
  });
});

describe('webmOpusParaOgg', () => {
  const pacotes = Array.from({ length: 120 }, (_, i) => [0xf8, i & 0xff, 1, 2, 3]);

  it('troca o contêiner sem mexer nos pacotes (OpusHead, OpusTags, granule, BOS/EOS, CRC)', () => {
    const r = webmOpusParaOgg(webm(pacotes), { serial: 7 });
    expect(r.pacotes).toBe(120);
    expect(r.canais).toBe(1);
    expect(r.duracaoMs).toBe(2400); // 120 × 20 ms
    const pg = lerOgg(r.ogg);
    expect(pg.every((x) => x.crcOk && x.serial === 7)).toBe(true);
    expect(pg.map((x) => x.seq)).toEqual(pg.map((_, i) => i));
    expect(pg[0].flags).toBe(0x02);
    expect(new TextDecoder().decode(pg[0].pacotes[0].subarray(0, 8))).toBe('OpusHead');
    expect(pg[0].pacotes[0][9]).toBe(1);
    expect(new TextDecoder().decode(pg[1].pacotes[0].subarray(0, 8))).toBe('OpusTags');
    expect(pg[0].granulo).toBe(0);
    expect(pg[1].granulo).toBe(0);
    const audio = pg.slice(2);
    expect(audio.at(-1)!.flags).toBe(0x04);
    expect(audio.slice(0, -1).every((x) => x.flags === 0)).toBe(true);
    expect(audio.at(-1)!.granulo).toBe(120 * 960);
    // granule cresce página a página e os pacotes saem iguais, na ordem
    const gs = audio.map((x) => x.granulo);
    expect([...gs].sort((a, b) => a - b)).toEqual(gs);
    expect(audio.flatMap((x) => x.pacotes.map((p) => Array.from(p)))).toEqual(pacotes);
  });

  it('pacote maior que 255 bytes atravessa a tabela de lacing', () => {
    const grande = [0xf8, ...Array.from({ length: 600 }, (_, i) => i & 0xff)];
    const r = webmOpusParaOgg(webm([grande, [0xf8, 9]]));
    const audio = lerOgg(r.ogg).slice(2);
    expect(audio.flatMap((x) => x.pacotes.map((p) => p.length))).toEqual([601, 2]);
  });

  it('sem CodecPrivate monta o OpusHead padrão', () => {
    const r = webmOpusParaOgg(webm([[0xf8, 1]], { head: false }));
    const head = lerOgg(r.ogg)[0].pacotes[0];
    expect(head.length).toBe(19);
    expect(new DataView(head.buffer, head.byteOffset).getUint32(12, true)).toBe(48000);
  });

  it('recusa o que não dá para remuxar', () => {
    expect(() => webmOpusParaOgg(webm(pacotes, { codec: 'A_VORBIS' }))).toThrow(ErroAudio);
    expect(() => webmOpusParaOgg(webm(pacotes, { lacing: 1 }))).toThrow(/lacing/);
    expect(() => webmOpusParaOgg(webm([]))).toThrow(/vazia/);
    expect(() => webmOpusParaOgg(new Uint8Array([1, 2, 3]))).toThrow(ErroAudio);
  });

  it('ignora o último bloco cortado (gravação interrompida)', () => {
    const b = webm([[0xf8, 1], [0xf8, 2, 3, 4, 5, 6]]);
    const r = webmOpusParaOgg(b.subarray(0, b.length - 3));
    expect(r.pacotes).toBe(1);
  });
});
