// Paginação feita AQUI, e não pelo motor do @react-pdf.
//
// Medido em 28/09 (Node 24, dataset sintético de 1.000 linhas): deixar o react-pdf
// quebrar uma <Page> com 1.000 linhas levou 9,4–14,5 s, e 2.000 linhas levaram 41 s —
// o custo cresce com o quadrado (cada quebra refaz o layout do resto). Com as linhas já
// distribuídas em várias <Page> de uma folha cada, as mesmas 1.000 linhas levaram
// ~3,4 s e 2.000 linhas 6,6–12,6 s (linear).
//
// O texto de cada célula é MEDIDO com a largura real dos glifos do Inter (metrica-inter.ts)
// e quebrado AQUI em linhas explícitas: entre palavras quando a soma passa da largura; a
// palavra só se parte quando ela sozinha não cabe. O react-pdf recebe linhas que já cabem
// e não quebra nada por conta própria — a altura estimada é a desenhada. Se ainda assim a
// estimativa errar para baixo, a <Page> tem wrap e o excesso vai para uma folha extra:
// nenhuma linha se perde. "Página X de Y" vem do motor (render prop).
//
// Largura da coluna (layoutTabela): o peso de cada coluna reparte a folha, mas nenhuma
// coluna fica mais estreita que o seu conteúdo inquebrável — valor em R$, data, número e
// palavra do cabeçalho. Quando isso não cabe na folha (Carteira com 25 colunas), a tabela
// aperta nesta ordem, parando no primeiro arranjo que cabe:
//   1. corpo cai de 0,25 em 0,25 pt até CORPO_MINIMO, primeiro com o espaçamento normal
//      entre colunas e depois com o espaçamento denso;
//   2. o valor em R$ pode ir em duas linhas: "R$" em cima, o número inteiro embaixo;
//   3. palavra de coluna de texto (nome, canal) se parte na largura da coluna;
//   4. último recurso: as colunas encolhem na proporção e qualquer palavra se parte.
// Em nenhum caso um texto passa da largura da sua coluna.
import type { ColunaPdf, KpiPdf, LinhaPdf, SecaoPdf } from './modelo';
import { AVANCO_INTER, CARACTERES_INTER, LARGURA_DESCONHECIDA } from './metrica-inter';
import { ALTURA_UTIL_PDF, LARGURA_UTIL_PDF, MEDIDA_PDF } from './tema-pdf';

const ALTURA_TITULO_SECAO = 24;
const ALTURA_KPIS = 46;
const ALTURA_VAZIO = 20;
const ESPACO_ENTRE_SECOES = 14;
/** Tabela de resumo (poucas colunas) não se estica na folha inteira: fica legível. */
const FRACAO_RESUMO = 0.62;
/**
 * Menor corpo de tabela (pt). Medido na Carteira com as 25 colunas: com cabeçalho sem
 * palavra partida e valor sem vazar, o arranjo só cabe em 5 pt (5,5 pt ainda partia
 * "Vencimento" e "Parcelamento"). Abaixo de 5 pt o papel impresso deixa de ser lido.
 */
export const CORPO_MINIMO = 5;
const PASSO_CORPO = 0.25;
/** Espaçamento lateral da célula quando a tabela aperta (o normal é MEDIDA_PDF.celulaPadX). */
const PAD_X_DENSO = 2;
/** Folga por linha (pt): arredondamento do motor. */
const FOLGA_LINHA = 0.5;
/**
 * Em coluna de TEXTO, palavra mais longa que isto (em "em") não alarga a coluna — é
 * partida (e-mail depois de @, código depois de . _ - /). Nome e rótulo comuns cabem.
 */
const PALAVRA_LONGA_EM = 7.5;
const PALAVRA_LONGA_EM_DENSO = 5;

export type PesoFonte = 400 | 600;

export type BlocoPagina =
  | { tipo: 'kpis'; kpis: KpiPdf[] }
  | { tipo: 'secao'; secao: SecaoPdf; continuacao: boolean; linhas: { linha: LinhaPdf; indice: number }[]; comTotal: boolean };

type SecaoMedida = Pick<SecaoPdf, 'tipo' | 'colunas' | 'linhas' | 'total'>;

// ─── Medida do texto ──────────────────────────────────────────────────────────

const INDICE = new Map<string, number>(Array.from(CARACTERES_INTER, (c, i) => [c, i]));

/** Largura do texto desenhado em Inter, em pt. */
export function larguraTexto(texto: string, corpo: number, peso: PesoFonte = 400): number {
  const tabela = AVANCO_INTER[peso];
  let milesimos = 0;
  for (const c of texto) {
    const i = INDICE.get(c);
    milesimos += i === undefined ? LARGURA_DESCONHECIDA : tabela[i];
  }
  return (milesimos * corpo) / 1000;
}

const NL = '\n';
const RIGIDO = ' ';
/** Só espaço comum separa palavra. Espaço rígido (U+00A0, o de "R$ 300,00") não quebra. */
const palavras = (paragrafo: string) => paragrafo.split(/[ \t]+/).filter(Boolean);
const inquebravel = (tipo: ColunaPdf['tipo']) => tipo !== 'texto';

/**
 * Parte UMA palavra que sozinha não cabe em `util` pt. Corte preferido: no espaço rígido
 * ("R$" numa linha, o número na outra), depois de @, depois de . _ - /, e só então no
 * último caractere que cabe. Nunca inventa hífen (hífen é válido em e-mail).
 */
function partirPalavra(palavra: string, util: number, corpo: number, peso: PesoFonte): string[] {
  const partes: string[] = [];
  let resto = palavra;
  while (resto && larguraTexto(resto, corpo, peso) > util) {
    const chars = Array.from(resto);
    let cabe = 0;
    let w = 0;
    while (cabe < chars.length) {
      const cw = larguraTexto(chars[cabe], corpo, peso);
      if (w + cw > util) break;
      w += cw;
      cabe += 1;
    }
    const janela = chars.slice(0, Math.max(cabe, 1)).join('');
    const rigido = janela.lastIndexOf(RIGIDO);
    if (rigido > 0) {
      partes.push(janela.slice(0, rigido));
      resto = resto.slice(rigido + 1);
      continue;
    }
    const arroba = janela.lastIndexOf('@');
    const sep = Math.max(janela.lastIndexOf('.'), janela.lastIndexOf('_'), janela.lastIndexOf('-'), janela.lastIndexOf('/'));
    const corte = arroba > 0 ? arroba + 1 : sep > 0 ? sep + 1 : janela.length;
    partes.push(resto.slice(0, corte));
    resto = resto.slice(corte);
  }
  if (resto) partes.push(resto);
  return partes;
}

/**
 * Quebra o texto em linhas de no máximo `util` pt (largura da coluna SEM o padding):
 * gulosa entre palavras; palavra que sozinha não cabe é partida (partirPalavra).
 */
export function quebrarTexto(texto: string, util: number, corpo: number, peso: PesoFonte = 400): string[] {
  const espaco = larguraTexto(' ', corpo, peso);
  const linhas: string[] = [];
  for (const paragrafo of texto.split(NL)) {
    let atual = '';
    let usado = 0;
    for (const palavra of palavras(paragrafo)) {
      const w = larguraTexto(palavra, corpo, peso);
      if (atual && usado + espaco + w <= util) {
        atual += ` ${palavra}`;
        usado += espaco + w;
        continue;
      }
      if (atual) linhas.push(atual);
      const partes = w <= util ? [palavra] : partirPalavra(palavra, util, corpo, peso);
      linhas.push(...partes.slice(0, -1));
      atual = partes[partes.length - 1];
      usado = larguraTexto(atual, corpo, peso);
    }
    linhas.push(atual);
  }
  return linhas;
}

// ─── Largura das colunas ──────────────────────────────────────────────────────

export interface LayoutTabela {
  /** Largura de cada coluna (pt, com o padding), na ordem de secao.colunas. */
  larguras: number[];
  /** Corpo das células (pt). */
  corpo: number;
  /** Corpo do cabeçalho (pt). */
  corpoTh: number;
  /** Espaçamento lateral da célula (pt). */
  padX: number;
}

export function larguraTabela(secao: Pick<SecaoPdf, 'tipo'>): number {
  return secao.tipo === 'resumo' ? LARGURA_UTIL_PDF * FRACAO_RESUMO : LARGURA_UTIL_PDF;
}

/** Corpo inicial: 7,5 pt até 12 colunas; acima disso diminui até 6 pt. layoutTabela() pode descer mais. */
export function corpoDaSecao(secao: Pick<SecaoPdf, 'colunas'>): number {
  const n = secao.colunas.length;
  return n <= 12 ? MEDIDA_PDF.corpo : Math.max(6, (MEDIDA_PDF.corpo * 12) / n);
}

const corpoThDe = (corpo: number) => Math.min(corpo, MEDIDA_PDF.rotulo + 0.5);

/** Célula como o PDF escreve: vazio vira travessão; no total, vazio fica vazio e a 1ª coluna diz "Total". */
export function textoCelula(valores: Record<string, string>, coluna: ColunaPdf, i: number, total = false): string {
  return total ? (valores[coluna.chave] || (i === 0 ? 'Total' : '')) : (valores[coluna.chave] || '—');
}

/**
 * Largura útil (sem padding) da coluna `i`, onde o texto é quebrado. O milésimo de ponto
 * absorve o arredondamento de ponto flutuante: sem ele, o valor que DEFINE a largura mínima
 * da coluna media 57,443 contra 57,442 de útil e ia para duas linhas (total da Pessoas, 9.228 linhas).
 */
export function larguraUtil(layout: LayoutTabela, i: number): number {
  return Math.max(layout.larguras[i] - 2 * layout.padX - FOLGA_LINHA + 0.001, 1);
}

/** Linhas da célula como o PDF vai desenhar. */
export function linhasCelula(layout: LayoutTabela, i: number, texto: string, peso: PesoFonte = 400): string[] {
  return quebrarTexto(texto, larguraUtil(layout, i), layout.corpo, peso);
}

/** Linhas do cabeçalho da coluna `i`. */
export function linhasCabecalho(layout: LayoutTabela, i: number, rotulo: string): string[] {
  return quebrarTexto(rotulo, larguraUtil(layout, i), layout.corpoTh, 600);
}

interface Arranjo { corpo: number; padX: number; partirMoeda: boolean; textoLivre?: boolean }

/** Menor largura (pt, com padding) que a coluna aceita no arranjo sem partir o que não se parte. */
function larguraMinima(secao: SecaoMedida, coluna: ColunaPdf, i: number, a: Arranjo): number {
  const teto = inquebravel(coluna.tipo) ? Infinity
    : a.textoLivre ? 0 : (a.padX === PAD_X_DENSO ? PALAVRA_LONGA_EM_DENSO : PALAVRA_LONGA_EM) * a.corpo;
  let maior = 0;
  const medir = (texto: string, c: number, peso: PesoFonte, limite: number, partir: boolean) => {
    for (const p of texto.split(NL)) {
      for (const palavra of palavras(p)) {
        for (const parte of partir ? palavra.split(RIGIDO) : [palavra]) {
          maior = Math.max(maior, Math.min(larguraTexto(parte, c, peso), limite));
        }
      }
    }
  };
  medir(coluna.rotulo, corpoThDe(a.corpo), 600, Infinity, false); // palavra do cabeçalho nunca se parte
  const partir = a.partirMoeda && coluna.tipo === 'moeda';
  for (const l of secao.linhas) medir(textoCelula(l.celulas, coluna, i), a.corpo, 400, teto, partir);
  if (secao.total) medir(textoCelula(secao.total, coluna, i, true), a.corpo, 600, teto, partir);
  return maior + 2 * a.padX + FOLGA_LINHA;
}

/** Reparte `total` pelos pesos sem deixar coluna abaixo do mínimo (quem bate no mínimo fica nele). */
function repartir(total: number, pesos: number[], minimos: number[]): number[] {
  const fixo = pesos.map(() => false);
  for (;;) {
    const livre = total - minimos.reduce((s, m, i) => s + (fixo[i] ? m : 0), 0);
    const pesoLivre = pesos.reduce((s, p, i) => s + (fixo[i] ? 0 : p), 0);
    let mudou = false;
    pesos.forEach((p, i) => {
      if (!fixo[i] && (livre * p) / pesoLivre < minimos[i]) { fixo[i] = true; mudou = true; }
    });
    if (!mudou || fixo.every(Boolean)) {
      return pesos.map((p, i) => (fixo[i] ? minimos[i] : (livre * p) / pesoLivre));
    }
  }
}

/** Arranjos em ordem de legibilidade (ver o topo do arquivo). */
function arranjos(corpoInicial: number): Arranjo[] {
  const corpos: number[] = [];
  for (let c = corpoInicial; c >= CORPO_MINIMO - 1e-9; c -= PASSO_CORPO) corpos.push(c);
  const normal = MEDIDA_PDF.celulaPadX;
  return [
    ...corpos.flatMap((corpo) => [{ corpo, padX: normal, partirMoeda: false }, { corpo, padX: PAD_X_DENSO, partirMoeda: false }]),
    ...corpos.map((corpo) => ({ corpo, padX: PAD_X_DENSO, partirMoeda: true })),
    // palavra de coluna de TEXTO (nome, canal) se parte na largura; cabeçalho e valor continuam inteiros
    { corpo: CORPO_MINIMO, padX: PAD_X_DENSO, partirMoeda: true, textoLivre: true },
  ];
}

const cacheLayout = new WeakMap<object, LayoutTabela>();

export function layoutTabela(secao: SecaoMedida): LayoutTabela {
  const guardado = cacheLayout.get(secao);
  if (guardado) return guardado;
  const total = larguraTabela(secao);
  const pesos = secao.colunas.map((c) => c.peso ?? 1);
  const opcoes = arranjos(corpoDaSecao(secao));
  let layout: LayoutTabela | null = null;
  let minimos: number[] = [];
  for (const a of opcoes) {
    minimos = secao.colunas.map((c, i) => larguraMinima(secao, c, i, a));
    if (minimos.reduce((s, m) => s + m, 0) <= total) {
      layout = { larguras: repartir(total, pesos, minimos), corpo: a.corpo, corpoTh: corpoThDe(a.corpo), padX: a.padX };
      break;
    }
  }
  if (!layout) {
    // Último recurso: nem o arranjo mais apertado cabe. Encolhe os mínimos na proporção;
    // a palavra se parte na largura, mas nunca invade a coluna vizinha.
    const soma = minimos.reduce((s, m) => s + m, 0);
    const a = opcoes[opcoes.length - 1];
    layout = { larguras: minimos.map((m) => (m * total) / soma), corpo: a.corpo, corpoTh: corpoThDe(a.corpo), padX: a.padX };
  }
  cacheLayout.set(secao, layout);
  return layout;
}

// ─── Altura e paginação ───────────────────────────────────────────────────────

const alturaDeLinhas = (n: number, corpo: number) => n * corpo * MEDIDA_PDF.alturaLinhaTexto + 2 * MEDIDA_PDF.celulaPadY + 0.5;

function alturaCabecalho(secao: SecaoMedida): number {
  const layout = layoutTabela(secao);
  const n = secao.colunas.reduce((m, c, i) => Math.max(m, linhasCabecalho(layout, i, c.rotulo).length), 1);
  return alturaDeLinhas(n, layout.corpoTh);
}

/** Altura de uma linha da tabela (pt). `total` = linha de total (SemiBold). */
export function alturaLinha(celulas: Record<string, string>, secao: SecaoMedida, total = false): number {
  const layout = layoutTabela(secao);
  const n = secao.colunas.reduce(
    (m, c, i) => Math.max(m, linhasCelula(layout, i, textoCelula(celulas, c, i, total), total ? 600 : 400).length), 1);
  return alturaDeLinhas(n, layout.corpo);
}

/** Distribui KPIs e seções em folhas. Cabeçalho da tabela se repete em cada folha. */
export function paginar(kpis: KpiPdf[] | undefined, secoes: SecaoPdf[], alturaUtil: number = ALTURA_UTIL_PDF): BlocoPagina[][] {
  const paginas: BlocoPagina[][] = [];
  let atual: BlocoPagina[] = [];
  let usado = 0;
  const novaPagina = () => {
    if (atual.length) paginas.push(atual);
    atual = [];
    usado = 0;
  };

  if (kpis?.length) {
    atual.push({ tipo: 'kpis', kpis });
    usado += ALTURA_KPIS + ESPACO_ENTRE_SECOES;
  }

  for (const secao of secoes) {
    const cabecalho = alturaCabecalho(secao);
    const alturas = secao.linhas.map((l) => alturaLinha(l.celulas, secao));
    const alturaTotal = secao.total ? alturaLinha(secao.total, secao, true) : 0;
    const primeira = secao.linhas.length ? alturas[0] : ALTURA_VAZIO;
    // título + cabeçalho + 1ª linha precisam caber juntos (sem título órfão no pé da folha)
    if (usado > 0 && usado + ALTURA_TITULO_SECAO + cabecalho + primeira > alturaUtil) novaPagina();

    let bloco: Extract<BlocoPagina, { tipo: 'secao' }> = { tipo: 'secao', secao, continuacao: false, linhas: [], comTotal: false };
    usado += ALTURA_TITULO_SECAO + cabecalho;
    if (!secao.linhas.length) usado += ALTURA_VAZIO;

    secao.linhas.forEach((linha, indice) => {
      if (usado + alturas[indice] > alturaUtil && bloco.linhas.length) {
        atual.push(bloco);
        novaPagina();
        bloco = { tipo: 'secao', secao, continuacao: true, linhas: [], comTotal: false };
        usado = ALTURA_TITULO_SECAO + cabecalho;
      }
      bloco.linhas.push({ linha, indice });
      usado += alturas[indice];
    });

    if (secao.total) {
      if (usado + alturaTotal > alturaUtil && bloco.linhas.length > 1) {
        // total nunca sozinho: leva a última linha junto para a folha seguinte
        const ultima = bloco.linhas.pop()!;
        atual.push(bloco);
        novaPagina();
        bloco = { tipo: 'secao', secao, continuacao: true, linhas: [ultima], comTotal: false };
        usado = ALTURA_TITULO_SECAO + cabecalho + alturas[ultima.indice];
      }
      bloco.comTotal = true;
      usado += alturaTotal;
    }
    atual.push(bloco);
    usado += ESPACO_ENTRE_SECOES;
  }
  novaPagina();
  return paginas.length ? paginas : [[]];
}
