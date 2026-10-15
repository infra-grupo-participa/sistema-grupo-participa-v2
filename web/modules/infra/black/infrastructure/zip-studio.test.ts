import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { deflateRawSync } from 'node:zlib';
import { describe, expect, it } from 'vitest';
import { marcosDaCurva, type MinutoLive } from '../domain/lives';
import { lerCsvStudio, tituloCombina, tituloDoNomeInterno } from '../domain/lives-studio';
import { LIMITE_DESCOMPACTADO_BYTES, lerZipStudio } from './zip-studio';

const PASTA = join(__dirname, '__fixtures__', 'lives-studio');
const abrir = (nome: string) => { const b = readFileSync(join(PASTA, nome)); return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer; };

// Os três zips reais do Studio (consultoria de 06/10, Primeiro Pilar de 08/10, consultoria de 13/10): só contagens por minuto,
// sem dado pessoal. Números de referência medidos em 15/10/2026 (DESENHO-ABA-LIVES.md).
const CASOS = [
  { arquivo: 'consultoria-06-10.zip', titulo: 'Consultoria ao Vivo com Vitor Negrão e Márcia Cristina - 06/10',
    linhas: 96, pico: 363, picoMin: 48, cheiaMin: 18, ultimo: 245, chat: 291, reacoes: 48, duracao: 5760, queda: [68, 70, 345, 302] },
  { arquivo: 'primeiro-pilar-08-10.zip', titulo: 'Método Perfeito - Primeiro Pilar - 0 que você precisa dominar antes do primeiro cliente',
    linhas: 81, pico: 125, picoMin: 59, cheiaMin: 50, ultimo: 41, chat: 102, reacoes: 2, duracao: 4860, queda: [70, 72, 107, 59] },
  { arquivo: 'consultoria-13-10.zip', titulo: 'Consultoria ao vivo com Joyce Nunes e Naírio Augusto - 13/10',
    linhas: 121, pico: 342, picoMin: 58, cheiaMin: 18, ultimo: 52, chat: 242, reacoes: 61, duracao: 7260, queda: [110, 112, 220, 98] },
] as const;

describe('zip do Studio (arquivos reais)', () => {
  for (const c of CASOS) {
    it(`${c.arquivo}: lê o zip e bate com os números medidos`, async () => {
      const zip = await lerZipStudio(abrir(c.arquivo));
      expect(zip.ok).toBe(true);
      if (!zip.ok) return;
      expect(zip.lido.leitor).toContain('DecompressionStream');
      expect(tituloCombina(tituloDoNomeInterno(zip.lido.nomeInterno), c.titulo)).toBe(true);
      const leitura = lerCsvStudio(zip.lido.csv);
      expect(leitura.erros).toEqual([]);
      expect(leitura.resumo).toMatchObject({
        linhas: c.linhas, pico: c.pico, picoSeg: c.picoMin * 60, ultimo: c.ultimo, chat: c.chat, reacoes: c.reacoes, duracaoSeg: c.duracao,
      });
      const minutos: MinutoLive[] = leitura.linhas.map((l) => ({ seg: l.seg, espectadores: l.espectadores, chat: l.chat ?? null, reacoes: l.reacoes ?? null, origem: 'studio' }));
      const marcos = marcosDaCurva(minutos);
      expect(marcos.pico).toMatchObject({ minuto: c.picoMin, espectadores: c.pico });
      expect(marcos.salaCheia?.minuto).toBe(c.cheiaMin);
      const [deMin, ateMin, de, ate] = c.queda;
      expect(marcos.quedas.find((q) => q.deMinuto === deMin)).toMatchObject({ ateMinuto: ateMin, de, ate });
      expect(marcos.quedas.length).toBeLessThanOrEqual(2);
    });
  }

  it('título de outra live não combina', async () => {
    const zip = await lerZipStudio(abrir('consultoria-06-10.zip'));
    if (!zip.ok) throw new Error(zip.erro);
    expect(tituloCombina(tituloDoNomeInterno(zip.lido.nomeInterno), CASOS[2].titulo)).toBe(false);
    expect(tituloCombina(tituloDoNomeInterno(zip.lido.nomeInterno), null)).toBeNull();
  });

  it('recusa arquivo que não é zip nem CSV', async () => {
    const r = await lerZipStudio(Uint8Array.from([0xff, 0xfe, 0x00]).buffer);
    expect(r.ok).toBe(false);
  });

  it('recusa zip sem o liveViewership', async () => {
    const r = await lerZipStudio(Uint8Array.from([0x50, 0x4b, 0x01, 0x02]).buffer);
    expect(r.ok).toBe(false);
  });
});

// Monta um zip na mão para provar o limite: `declarado` é o tamanho descompactado que o cabeçalho afirma (pode mentir).
interface EntradaTeste { nome: string; dados: Buffer; declarado?: number; metodo?: number; cru?: boolean }
function montarZip(entradas: EntradaTeste[]): ArrayBuffer {
  const locais: Buffer[] = []; const centrais: Buffer[] = []; let deslocamento = 0;
  for (const e of entradas) {
    const nome = Buffer.from(e.nome, 'latin1');
    const metodo = e.metodo ?? 8;
    const comp = e.cru ? e.dados : metodo === 8 ? deflateRawSync(e.dados) : e.dados;
    const declarado = e.declarado ?? e.dados.length;
    const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(metodo, 8);
    local.writeUInt32LE(comp.length, 18); local.writeUInt32LE(declarado, 22); local.writeUInt16LE(nome.length, 26);
    const central = Buffer.alloc(46); central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(metodo, 10); central.writeUInt32LE(comp.length, 20); central.writeUInt32LE(declarado, 24);
    central.writeUInt16LE(nome.length, 28); central.writeUInt32LE(deslocamento, 42);
    locais.push(local, nome, comp); centrais.push(central, nome);
    deslocamento += 30 + nome.length + comp.length;
  }
  const dir = Buffer.concat(centrais);
  const fim = Buffer.alloc(22); fim.writeUInt32LE(0x06054b50, 0); fim.writeUInt16LE(entradas.length, 8); fim.writeUInt16LE(entradas.length, 10);
  fim.writeUInt32LE(dir.length, 12); fim.writeUInt32LE(deslocamento, 16);
  const b = Buffer.concat([...locais, dir, fim]);
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer;
}
const CSV = Buffer.from('Posição na transmissão ao vivo (segundos),Espectadores simultâneos na transmissão\n0,12\n60,20\n', 'utf-8');
const MB = 1024 * 1024;

describe('zip do Studio: proteção contra zip bomb', () => {
  it('zip montado na mão com o CSV certo abre e devolve o texto exato', async () => {
    const r = await lerZipStudio(montarZip([{ nome: 'liveViewership_Transmissões ao vivo Teste.csv', dados: CSV }]));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.lido.csv).toBe(CSV.toString('utf-8'));
  });

  it('zip inflado (25 MB de zeros em ~25 KB) é recusado pelo tamanho declarado, sem descompactar', async () => {
    const zeros = Buffer.alloc(25 * MB);
    const zip = montarZip([{ nome: 'liveViewership_x.csv', dados: zeros }]);
    expect(zip.byteLength).toBeLessThan(100 * 1024);
    expect(25 * MB).toBeGreaterThan(LIMITE_DESCOMPACTADO_BYTES);
    const r = await lerZipStudio(zip);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.erro).toContain('20 MB');
  });

  it('a soma conta todas as entradas: o CSV é pequeno, mas outra entrada declara 25 MB', async () => {
    const r = await lerZipStudio(montarZip([
      { nome: 'liveViewership_x.csv', dados: CSV },
      { nome: 'outro.bin', dados: Buffer.from('x'), declarado: 25 * MB },
    ]));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.erro).toContain('20 MB');
  });

  it('cabeçalho que mente (declara 100 bytes, o conteúdo real é 25 MB) é abortado durante a descompressão', async () => {
    const r = await lerZipStudio(montarZip([{ nome: 'liveViewership_x.csv', dados: Buffer.alloc(25 * MB), declarado: 100 }]));
    expect(r.ok).toBe(false);
  });

  it('só o liveViewership é descompactado: outra entrada com dados inválidos não derruba a leitura', async () => {
    const r = await lerZipStudio(montarZip([
      { nome: 'liveEngagements_x.csv', dados: Buffer.from([0xff, 0xff, 0xff, 0xff]), cru: true },
      { nome: 'liveViewership_x.csv', dados: CSV },
    ]));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.lido.csv).toBe(CSV.toString('utf-8'));
  });

  it('entrada com método de compressão desconhecido é recusada', async () => {
    const r = await lerZipStudio(montarZip([{ nome: 'liveViewership_x.csv', dados: CSV, metodo: 12 }]));
    expect(r.ok).toBe(false);
  });
});
