// Paginação feita AQUI, e não pelo motor do @react-pdf.
//
// Medido em 28/09 (Node 24, dataset de 1.000 linhas, .research/pdf-viabilidade):
// deixar o react-pdf quebrar uma <Page> com 1.000 linhas levou 9,4–14,5 s, e 2.000
// linhas levaram 41 s — o custo cresce com o quadrado (cada quebra refaz o layout do
// resto). Com as linhas já distribuídas em várias <Page> de uma folha cada, as mesmas
// 1.000 linhas levaram ~3,4 s e 2.000 linhas 6,6–12,6 s (linear).
//
// A altura de cada linha é ESTIMADA pelo número de caracteres × largura da coluna,
// com folga para cima. Se a estimativa errar para baixo, a <Page> ainda tem wrap e o
// react-pdf empurra o excesso para uma folha extra: nenhuma linha se perde, só sobra
// uma folha curta. "Página X de Y" vem do motor (render prop), então continua certo.
import type { KpiPdf, LinhaPdf, SecaoPdf } from './modelo';
import { ALTURA_UTIL_PDF, LARGURA_UTIL_PDF, MEDIDA_PDF } from './tema-pdf';

/** Largura média de caractere do Inter em fração do corpo (folgada para cima). */
const LARGURA_CARACTERE = 0.56;
const ALTURA_TITULO_SECAO = 24;
const ALTURA_KPIS = 46;
const ALTURA_VAZIO = 20;
const ESPACO_ENTRE_SECOES = 14;
/** Tabela de resumo (poucas colunas) não se estica na folha inteira: fica legível. */
const FRACAO_RESUMO = 0.62;

export type BlocoPagina =
  | { tipo: 'kpis'; kpis: KpiPdf[] }
  | { tipo: 'secao'; secao: SecaoPdf; continuacao: boolean; linhas: { linha: LinhaPdf; indice: number }[]; comTotal: boolean };

export function larguraTabela(secao: Pick<SecaoPdf, 'tipo'>): number {
  return secao.tipo === 'resumo' ? LARGURA_UTIL_PDF * FRACAO_RESUMO : LARGURA_UTIL_PDF;
}

export function larguraColunas(secao: Pick<SecaoPdf, 'tipo' | 'colunas'>): number[] {
  const total = larguraTabela(secao);
  const soma = secao.colunas.reduce((s, c) => s + (c.peso ?? 1), 0) || 1;
  return secao.colunas.map((c) => (total * (c.peso ?? 1)) / soma);
}

/**
 * Corpo da tabela: 7,5 pt até 12 colunas; acima disso diminui até 6 pt (a Carteira do
 * board deixa marcar 25 colunas). Mesmo com 6 pt, 25 colunas numa folha A4 quebram
 * valores em 2 linhas — legível, mas apertado.
 */
export function corpoDaSecao(secao: Pick<SecaoPdf, 'colunas'>): number {
  const n = secao.colunas.length;
  return n <= 12 ? MEDIDA_PDF.corpo : Math.max(6, (MEDIDA_PDF.corpo * 12) / n);
}

/** Caracteres que cabem numa linha da célula (estimativa conservadora). */
export function caracteresPorLinha(larguraPt: number, corpo: number = MEDIDA_PDF.corpo): number {
  const util = Math.max(larguraPt - 2 * MEDIDA_PDF.celulaPadX, 10);
  return Math.max(Math.floor(util / (corpo * LARGURA_CARACTERE)), 4);
}

const NL = '\n';

/**
 * Token sem espaço maior que a coluna (e-mail, sck, código) ganha quebra de linha
 * explícita — depois de @, senão de . _ - /, senão no limite. O react-pdf não quebra
 * palavra sem hifenizar, e hífen inventado dentro de e-mail mente (hífen é válido em e-mail).
 */
export function quebrarTokens(texto: string, max: number): string {
  return texto.split(NL).map((linha) => linha.replace(/\S+/g, (token) => {
    const partes: string[] = [];
    let resto = token;
    while (resto.length > max) {
      const janela = resto.slice(0, max);
      const arroba = janela.lastIndexOf('@');
      const sep = Math.max(janela.lastIndexOf('.'), janela.lastIndexOf('_'), janela.lastIndexOf('-'), janela.lastIndexOf('/'));
      const corte = arroba > 0 ? arroba + 1 : sep > 0 ? sep + 1 : max;
      partes.push(resto.slice(0, corte));
      resto = resto.slice(corte);
    }
    partes.push(resto);
    return partes.join(NL);
  })).join(NL);
}

/** Linhas que o texto ocupa: quebra de palavra gulosa sobre o texto já com tokens quebrados. */
function linhasDoTexto(texto: string, max: number): number {
  return quebrarTokens(texto, max).split(NL).reduce((n, linha) => {
    let linhas = 1;
    let usado = 0;
    for (const palavra of linha.split(/\s+/).filter(Boolean)) {
      const w = palavra.length;
      if (usado === 0) usado = w;
      else if (usado + 1 + w <= max) usado += 1 + w;
      else { linhas += 1; usado = w; }
    }
    return n + linhas;
  }, 0);
}

/** Altura estimada de uma linha da tabela, em pontos. */
export function alturaLinha(celulas: Record<string, string>, secao: Pick<SecaoPdf, 'tipo' | 'colunas'>, corpo: number = corpoDaSecao(secao)): number {
  const larguras = larguraColunas(secao);
  const maxLinhas = secao.colunas.reduce(
    (m, c, i) => Math.max(m, linhasDoTexto(celulas[c.chave] ?? '', caracteresPorLinha(larguras[i], corpo))), 1);
  return maxLinhas * corpo * MEDIDA_PDF.alturaLinhaTexto + 2 * MEDIDA_PDF.celulaPadY + 0.5;
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
    const cabecalho = alturaLinha(Object.fromEntries(secao.colunas.map((c) => [c.chave, c.rotulo])), secao);
    const alturas = secao.linhas.map((l) => alturaLinha(l.celulas, secao));
    const alturaTotal = secao.total ? alturaLinha(secao.total, secao) : 0;
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
