// Leitura do CSV "liveViewership_*.csv" do YouTube Studio (Análise > Transmissões ao vivo > Baixar). Puro: recebe o
// texto, devolve as linhas ou os erros. Quem lê o .zip no navegador é infrastructure/zip-studio.ts.
//
// Colunas do arquivo (texto exato do cabeçalho):
//   Posição na transmissão ao vivo (segundos), Espectadores simultâneos na transmissão, Mensagens do chat ao vivo,
//   Média de espectadores simultâneos, Envolvimentos ao vivo, Reações
// Só entram seg, espectadores, chat e reações. "Média de espectadores" (média dentro do minuto) e "Envolvimentos"
// (= chat + reações, uma soma) ficam de fora de propósito.
import type { Valor } from './tipos';

export const COLUNAS_STUDIO = {
  seg: 'Posição na transmissão ao vivo (segundos)',
  espectadores: 'Espectadores simultâneos na transmissão',
  chat: 'Mensagens do chat ao vivo',
  reacoes: 'Reações',
} as const;

export interface LinhaStudio { seg: number; espectadores: number; chat?: number; reacoes?: number }

export interface ResumoStudio {
  linhas: number; pico: number; picoSeg: number; duracaoSeg: number;
  /** Espectadores no último minuto do arquivo. */
  ultimo: number;
  chat: Valor; reacoes: Valor;
}

export interface LeituraStudio {
  linhas: LinhaStudio[];
  /** Erros que impedem de importar (arquivo vazio, coluna ausente, linha inválida, segundo repetido). */
  erros: string[];
  /** Avisos que não impedem (ex.: linha sem chat fica em branco no banco, sem dado). */
  avisos: string[];
  resumo: ResumoStudio | null;
}

export const LIMITE_LINHAS_STUDIO = 2000;

/** Divide uma linha de CSV respeitando aspas. O Studio usa vírgula. */
function campos(linha: string): string[] {
  const out: string[] = []; let atual = ''; let aspas = false;
  for (let i = 0; i < linha.length; i++) {
    const c = linha[i];
    if (aspas) {
      if (c === '"' && linha[i + 1] === '"') { atual += '"'; i++; } else if (c === '"') aspas = false; else atual += c;
    } else if (c === '"') aspas = true;
    else if (c === ',') { out.push(atual); atual = ''; } else atual += c;
  }
  out.push(atual);
  return out.map((x) => x.trim());
}

const INTEIRO = /^\d{1,7}$/;

export function lerCsvStudio(texto: string): LeituraStudio {
  const erros: string[] = []; const avisos: string[] = [];
  const bruto = texto.replace(/^﻿/, '').split(/\r\n|\n|\r/).filter((l) => l.trim() !== '');
  if (bruto.length < 2) return { linhas: [], erros: ['O arquivo não tem linhas de dados abaixo do cabeçalho.'], avisos, resumo: null };
  const cab = campos(bruto[0]);
  const col = (nome: string) => cab.findIndex((c) => c === nome);
  const iSeg = col(COLUNAS_STUDIO.seg); const iEsp = col(COLUNAS_STUDIO.espectadores);
  const iChat = col(COLUNAS_STUDIO.chat); const iRea = col(COLUNAS_STUDIO.reacoes);
  if (iSeg < 0) erros.push(`Falta a coluna "${COLUNAS_STUDIO.seg}".`);
  if (iEsp < 0) erros.push(`Falta a coluna "${COLUNAS_STUDIO.espectadores}".`);
  if (iChat < 0) avisos.push(`Sem a coluna "${COLUNAS_STUDIO.chat}": o chat fica em branco (sem dado) em todos os minutos.`);
  if (iRea < 0) avisos.push(`Sem a coluna "${COLUNAS_STUDIO.reacoes}": as reações ficam em branco (sem dado) em todos os minutos.`);
  if (erros.length) return { linhas: [], erros, avisos, resumo: null };

  const linhas: LinhaStudio[] = []; const vistos = new Set<number>();
  let semChat = 0; let semReacao = 0; let invalidas = 0; let repetidas = 0;
  for (let n = 1; n < bruto.length; n++) {
    const c = campos(bruto[n]);
    const seg = c[iSeg] ?? ''; const esp = c[iEsp] ?? '';
    if (!INTEIRO.test(seg) || !INTEIRO.test(esp)) { invalidas++; continue; }
    const s = Number(seg);
    if (vistos.has(s)) { repetidas++; continue; }
    vistos.add(s);
    const linha: LinhaStudio = { seg: s, espectadores: Number(esp) };
    if (iChat >= 0) { if (INTEIRO.test(c[iChat] ?? '')) linha.chat = Number(c[iChat]); else semChat++; }
    if (iRea >= 0) { if (INTEIRO.test(c[iRea] ?? '')) linha.reacoes = Number(c[iRea]); else semReacao++; }
    linhas.push(linha);
  }
  if (invalidas) erros.push(`${invalidas} linha(s) com posição ou espectadores que não são números inteiros.`);
  if (repetidas) erros.push(`${repetidas} linha(s) repetem uma posição (segundo) já lida.`);
  if (linhas.length === 0 && !erros.length) erros.push('Nenhuma linha válida no arquivo.');
  if (linhas.length > LIMITE_LINHAS_STUDIO) erros.push(`O arquivo tem ${linhas.length} linhas e o limite é ${LIMITE_LINHAS_STUDIO}.`);
  if (semChat) avisos.push(`${semChat} linha(s) sem número de chat: o chat fica em branco (sem dado) nelas.`);
  if (semReacao) avisos.push(`${semReacao} linha(s) sem número de reações: as reações ficam em branco (sem dado) nelas.`);
  if (erros.length) return { linhas: [], erros, avisos, resumo: null };
  linhas.sort((a, b) => a.seg - b.seg);
  return { linhas, erros, avisos, resumo: resumirStudio(linhas, iChat >= 0, iRea >= 0) };
}

export function resumirStudio(linhas: readonly LinhaStudio[], temChat = true, temReacoes = true): ResumoStudio | null {
  if (linhas.length === 0) return null;
  let pico = linhas[0];
  for (const l of linhas) if (l.espectadores > pico.espectadores) pico = l;
  const ultima = linhas[linhas.length - 1];
  // Minuto sem o número fica fora da soma; se nenhum minuto tem o número, o total é null (igual ao banco, que grava NULL).
  const soma = (f: (l: LinhaStudio) => number | undefined): Valor => {
    let total: number | null = null;
    for (const l of linhas) { const v = f(l); if (v !== undefined) total = (total ?? 0) + v; }
    return total;
  };
  return {
    linhas: linhas.length, pico: pico.espectadores, picoSeg: pico.seg, duracaoSeg: ultima.seg + 60, ultimo: ultima.espectadores,
    chat: temChat ? soma((l) => l.chat) : null, reacoes: temReacoes ? soma((l) => l.reacoes) : null,
  };
}

// ─── Título do arquivo ─────────────────────────────────────────────────────────────────────────────────────────

/**
 * O nome interno do .zip do Studio vem em UTF-8 sem o aviso de codificação, e o leitor entrega cada byte como um
 * caractere ("ã" vira "Ã£"). Se todos os caracteres cabem em um byte e o resultado é UTF-8 válido, devolve o texto
 * certo; senão devolve o nome como veio.
 */
export function consertarNomeInterno(nome: string): string {
  if ([...nome].some((c) => c.charCodeAt(0) > 255)) return nome;
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(nome, (c) => c.charCodeAt(0)));
  } catch {
    return nome;
  }
}

/** "liveViewership_Transmissões ao vivo <título>.csv" -> "<título>". Sem esse padrão, null. */
export function tituloDoNomeInterno(nome: string): string | null {
  const base = consertarNomeInterno(nome).split(/[\\/]/).pop() ?? '';
  const m = /^liveViewership_(?:Transmiss\S+ ao vivo )?(.+)\.csv$/i.exec(base);
  // O "/" do título (ex.: "06/10") quebra o nome em pastas; por isso a busca abaixo usa o caminho inteiro.
  if (m) return m[1].trim();
  const inteiro = consertarNomeInterno(nome);
  const i = inteiro.indexOf('liveViewership_');
  if (i < 0) return null;
  const resto = inteiro.slice(i + 'liveViewership_'.length).replace(/\.csv$/i, '');
  return resto.replace(/^Transmiss\S+ ao vivo /i, '').trim() || null;
}

/** Minúsculas, sem acento, só letras e números: para comparar títulos sem brigar com pontuação. */
export const normalizarTitulo = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '');

/**
 * O título do arquivo bate com o título da live? Aceita igual ou um contendo o outro (o Studio pode encurtar o nome do
 * arquivo). Título da live desconhecido (null) = não dá para conferir: devolve null, e a tela avisa em vez de travar.
 */
export function tituloCombina(tituloArquivo: string | null, tituloLive: string | null): boolean | null {
  if (!tituloLive) return null;
  if (!tituloArquivo) return false;
  const a = normalizarTitulo(tituloArquivo); const b = normalizarTitulo(tituloLive);
  if (a.length < 8 || b.length < 8) return a === b;
  return a.includes(b) || b.includes(a);
}
