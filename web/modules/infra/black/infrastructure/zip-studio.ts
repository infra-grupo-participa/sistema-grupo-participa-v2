// Lê, no navegador, o .zip que o YouTube Studio baixa e entrega só o liveViewership_*.csv (o liveEngagements_* repete
// o chat e as reações e não é lido). Nada sobe para servidor: o arquivo é aberto aqui e só as linhas viram a RPC.
//
// Leitor próprio do diretório central do zip + DecompressionStream('deflate-raw') do navegador (sem dependência nova).
// Por que não o SheetJS (XLSX.CFB): ele descompacta TODAS as entradas do zip antes de a gente escolher uma, e só o
// tamanho compactado era limitado. Um zip de 30 KB pode declarar centenas de MB (zip bomb) e travar a aba. Aqui:
//   1. antes de descompactar qualquer coisa, soma o tamanho DESCOMPACTADO declarado no diretório central de todas as
//      entradas e recusa se passar de LIMITE_DESCOMPACTADO_BYTES;
//   2. descompacta SÓ a entrada liveViewership_*.csv;
//   3. durante a descompressão confere o que realmente sai (o cabeçalho pode mentir) e aborta se passar do declarado
//      ou do limite.
// O zip real do Studio tem poucos KB (3 conferidos em 15/10/2026: dezenas de KB descompactados).
import { consertarNomeInterno } from '../domain/lives-studio';

export const LIMITE_BYTES_ZIP = 5 * 1024 * 1024;
/** Teto da soma dos tamanhos descompactados declarados no zip (todas as entradas). */
export const LIMITE_DESCOMPACTADO_BYTES = 20 * 1024 * 1024;
export const LEITOR_ZIP = 'diretório central do zip + DecompressionStream';

export interface ZipStudioLido { csv: string; nomeInterno: string; leitor: string }
export type ResultadoZip = { ok: true; lido: ZipStudioLido } | { ok: false; erro: string };

interface EntradaZip { nome: string; metodo: number; cifrado: boolean; comprimido: number; descomprimido: number; deslocamento: number }

const ERRO_ABRIR = 'Não consegui abrir o zip. Baixe de novo no Studio ou mande o liveViewership_*.csv extraído.';
const ERRO_GRANDE = `O zip declara mais de ${LIMITE_DESCOMPACTADO_BYTES / 1024 / 1024} MB descompactado. O zip do Studio tem poucos KB: confira se é o arquivo certo.`;

class ZipInvalido extends Error {}

/** Lê o diretório central. Lança ZipInvalido se a estrutura não fecha (ou se é zip64, que o Studio não gera). */
function lerDiretorio(bytes: Uint8Array): EntradaZip[] {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xffff); i--) {
    if (v.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new ZipInvalido('sem fim de diretório');
  const total = v.getUint16(eocd + 10, true);
  const tamanhoDir = v.getUint32(eocd + 12, true);
  const inicioDir = v.getUint32(eocd + 16, true);
  if (total === 0xffff || tamanhoDir === 0xffffffff || inicioDir === 0xffffffff) throw new ZipInvalido('zip64');
  if (inicioDir + tamanhoDir > bytes.length) throw new ZipInvalido('diretório fora do arquivo');
  const entradas: EntradaZip[] = [];
  let p = inicioDir;
  for (let n = 0; n < total; n++) {
    if (p + 46 > bytes.length || v.getUint32(p, true) !== 0x02014b50) throw new ZipInvalido('entrada inválida');
    const flags = v.getUint16(p + 8, true);
    const comprimido = v.getUint32(p + 20, true);
    const descomprimido = v.getUint32(p + 24, true);
    const nomeLen = v.getUint16(p + 28, true);
    const extraLen = v.getUint16(p + 30, true);
    const comentarioLen = v.getUint16(p + 32, true);
    const deslocamento = v.getUint32(p + 42, true);
    if (comprimido === 0xffffffff || descomprimido === 0xffffffff || deslocamento === 0xffffffff) throw new ZipInvalido('zip64');
    if (p + 46 + nomeLen > bytes.length) throw new ZipInvalido('nome fora do arquivo');
    // O nome fica em bytes crus (um caractere por byte): consertarNomeInterno decide se era UTF-8, como sempre fez.
    let nome = '';
    for (let k = 0; k < nomeLen; k++) nome += String.fromCharCode(bytes[p + 46 + k]);
    entradas.push({ nome, metodo: v.getUint16(p + 10, true), cifrado: (flags & 1) === 1, comprimido, descomprimido, deslocamento });
    p += 46 + nomeLen + extraLen + comentarioLen;
  }
  return entradas;
}

/** Descompacta uma entrada; aborta (null) se sair mais que `maximo` bytes. */
async function extrair(bytes: Uint8Array, e: EntradaZip, maximo: number): Promise<Uint8Array | null> {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const l = e.deslocamento;
  if (l + 30 > bytes.length || v.getUint32(l, true) !== 0x04034b50) throw new ZipInvalido('cabeçalho local inválido');
  const inicio = l + 30 + v.getUint16(l + 26, true) + v.getUint16(l + 28, true);
  if (inicio + e.comprimido > bytes.length) throw new ZipInvalido('dados fora do arquivo');
  const dados = bytes.subarray(inicio, inicio + e.comprimido);
  if (e.metodo === 0) return dados.length > maximo ? null : Uint8Array.from(dados);
  if (typeof DecompressionStream === 'undefined') throw new ZipInvalido('navegador sem DecompressionStream');
  const ds = new DecompressionStream('deflate-raw');
  const w = ds.writable.getWriter();
  w.write(dados as unknown as BufferSource).catch(() => undefined);
  w.close().catch(() => undefined);
  const r = ds.readable.getReader();
  const partes: Uint8Array[] = [];
  let soma = 0;
  for (;;) {
    const { done, value } = await r.read();
    if (done) break;
    soma += value.length;
    if (soma > maximo) { await r.cancel().catch(() => undefined); return null; }
    partes.push(value);
  }
  const saida = new Uint8Array(soma);
  let o = 0;
  for (const c of partes) { saida.set(c, o); o += c.length; }
  return saida;
}

export async function lerZipStudio(buffer: ArrayBuffer): Promise<ResultadoZip> {
  if (buffer.byteLength === 0) return { ok: false, erro: 'O arquivo está vazio.' };
  if (buffer.byteLength > LIMITE_BYTES_ZIP) return { ok: false, erro: 'O arquivo passa de 5 MB. O zip do Studio tem poucos KB: confira se é o arquivo certo.' };
  const bytes = new Uint8Array(buffer);
  // Um .csv solto também é aceito (quem já extraiu o zip): não começa com a marca "PK" do zip.
  if (!(bytes[0] === 0x50 && bytes[1] === 0x4b)) {
    try {
      return { ok: true, lido: { csv: new TextDecoder('utf-8', { fatal: true }).decode(bytes), nomeInterno: '', leitor: 'CSV direto' } };
    } catch {
      return { ok: false, erro: 'O arquivo não é um .zip do Studio nem um CSV em UTF-8.' };
    }
  }
  try {
    const entradas = lerDiretorio(bytes);
    // 1. Antes de descompactar qualquer coisa: a soma do que o zip declara.
    const declarado = entradas.reduce((s, e) => s + e.descomprimido, 0);
    if (declarado > LIMITE_DESCOMPACTADO_BYTES) return { ok: false, erro: ERRO_GRANDE };
    // 2. Só o liveViewership_*.csv.
    const achados = entradas.filter((e) => e.nome.includes('liveViewership_') && /\.csv$/i.test(e.nome));
    if (achados.length === 0) return { ok: false, erro: 'Não achei o liveViewership_*.csv dentro do zip. Baixe de novo em Studio > Análise > Transmissões ao vivo.' };
    if (achados.length > 1) return { ok: false, erro: `O zip tem ${achados.length} arquivos liveViewership_*.csv. Mande um zip por live.` };
    const [a] = achados;
    if (a.cifrado || (a.metodo !== 0 && a.metodo !== 8)) return { ok: false, erro: ERRO_ABRIR };
    // 3. O que sai da descompressão não pode passar do declarado: cabeçalho que mente é zip bomb ou arquivo corrompido.
    const saida = await extrair(bytes, a, a.descomprimido);
    if (!saida || saida.length !== a.descomprimido) return { ok: false, erro: saida === null ? ERRO_GRANDE : ERRO_ABRIR };
    return { ok: true, lido: { csv: new TextDecoder('utf-8').decode(saida), nomeInterno: consertarNomeInterno(a.nome), leitor: LEITOR_ZIP } };
  } catch {
    return { ok: false, erro: ERRO_ABRIR };
  }
}
