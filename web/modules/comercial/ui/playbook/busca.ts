// Busca e destaque no texto do playbook. Puro (sem React): a tela só chama.
// Busca sem acento e sem caixa ("distribuicao" acha "Distribuição"); **negrito** não atrapalha a busca.
import type { Bloco } from './conteudo';

/** O mínimo que a busca precisa de uma seção (do playbook ou da central de ajuda). */
export interface Pesquisavel {
  id: string;
  titulo: string;
  resumo?: string;
  blocos: Bloco[];
  /** Palavras que levam à seção sem aparecer no texto (ex.: "kanban" → Funil). */
  sinonimos?: string[];
}

/** Trecho de texto pronto para desenhar. */
export interface Segmento { texto: string; negrito: boolean; destaque: boolean }

/** Tira acento e caixa, guardando de que posição do original veio cada letra. */
function normalizarComMapa(s: string): { norm: string; mapa: number[] } {
  let norm = '';
  const mapa: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const n = s[i].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
    for (const ch of n) { norm += ch; mapa.push(i); }
  }
  return { norm, mapa };
}

export function normalizar(s: string): string {
  return normalizarComMapa(s).norm;
}

/** Termo útil para buscar: sem espaços nas pontas, mínimo de 2 letras. */
export function termoValido(termo: string): string {
  const t = termo.trim();
  return t.length >= 2 ? t : '';
}

/** Posições [início, fim) do termo no texto original (sem sobreposição). */
export function acharTrechos(texto: string, termo: string): [number, number][] {
  const t = normalizar(termoValido(termo));
  if (!t) return [];
  const { norm, mapa } = normalizarComMapa(texto);
  const achados: [number, number][] = [];
  let de = 0;
  for (;;) {
    const i = norm.indexOf(t, de);
    if (i < 0) break;
    achados.push([mapa[i], mapa[i + t.length - 1] + 1]);
    de = i + t.length;
  }
  return achados;
}

/** Separa o **negrito** do texto comum. Asterisco sem par fica como texto. */
export function separarNegrito(texto: string): { texto: string; negrito: boolean }[] {
  const partes: { texto: string; negrito: boolean }[] = [];
  const re = /\*\*([^*]+)\*\*/g;
  let ultimo = 0;
  for (let m = re.exec(texto); m; m = re.exec(texto)) {
    if (m.index > ultimo) partes.push({ texto: texto.slice(ultimo, m.index), negrito: false });
    partes.push({ texto: m[1], negrito: true });
    ultimo = m.index + m[0].length;
  }
  if (ultimo < texto.length) partes.push({ texto: texto.slice(ultimo), negrito: false });
  return partes;
}

/** Texto limpo (sem os asteriscos do negrito): é o que vai para a cópia e para a busca. */
export function textoLimpo(texto: string): string {
  return separarNegrito(texto).map((p) => p.texto).join('');
}

// Palavras que não ajudam a achar nada ("como mover o negócio" busca "mover" e "negocio").
const PALAVRAS_VAZIAS = new Set([
  'a', 'o', 'as', 'os', 'ao', 'aos', 'de', 'da', 'do', 'das', 'dos', 'e', 'em', 'no', 'na', 'nos', 'nas', 'um', 'uma',
  'para', 'pra', 'por', 'com', 'que', 'como', 'eu', 'meu', 'minha', 'se', 'ou', 'sem', 'mais', 'onde', 'qual', 'quando',
]);

/** Palavras úteis da busca, sem acento e sem caixa. Se só sobrar palavra vazia, usa o que veio. */
export function palavrasDaBusca(consulta: string): string[] {
  const todas = normalizar(termoValido(consulta)).split(/[^a-z0-9%$#@+]+/).filter((w) => w.length >= 2);
  const uteis = todas.filter((w) => !PALAVRAS_VAZIAS.has(w));
  return [...new Set(uteis.length ? uteis : todas)];
}

/** Posições [início, fim) de qualquer uma das palavras no texto original, ordenadas e sem sobreposição. */
export function acharPalavras(texto: string, palavras: string[]): [number, number][] {
  if (palavras.length === 0) return [];
  const { norm, mapa } = normalizarComMapa(texto);
  const brutos: [number, number][] = [];
  for (const w of palavras) {
    for (let i = norm.indexOf(w); i >= 0; i = norm.indexOf(w, i + w.length)) brutos.push([mapa[i], mapa[i + w.length - 1] + 1]);
  }
  brutos.sort((x, y) => x[0] - y[0] || y[1] - x[1]);
  const juntos: [number, number][] = [];
  for (const [a, b] of brutos) {
    const ult = juntos[juntos.length - 1];
    if (ult && a <= ult[1]) ult[1] = Math.max(ult[1], b);
    else juntos.push([a, b]);
  }
  return juntos;
}

/** Negrito + destaque das palavras da busca, em segmentos contíguos. */
export function segmentar(texto: string, termo: string): Segmento[] {
  const saida: Segmento[] = [];
  const palavras = palavrasDaBusca(termo);
  for (const parte of separarNegrito(texto)) {
    let ultimo = 0;
    for (const [a, b] of acharPalavras(parte.texto, palavras)) {
      if (a > ultimo) saida.push({ texto: parte.texto.slice(ultimo, a), negrito: parte.negrito, destaque: false });
      saida.push({ texto: parte.texto.slice(a, b), negrito: parte.negrito, destaque: true });
      ultimo = b;
    }
    if (ultimo < parte.texto.length) saida.push({ texto: parte.texto.slice(ultimo), negrito: parte.negrito, destaque: false });
  }
  return saida;
}

/** Todos os textos de um bloco, na ordem em que aparecem na tela. */
export function textosDoBloco(b: Bloco): string[] {
  switch (b.tipo) {
    case 'paragrafo':
    case 'subtitulo':
      return [b.texto];
    case 'lista':
      return [...(b.titulo ? [b.titulo] : []), ...b.itens];
    case 'tabela':
      return [...(b.titulo ? [b.titulo] : []), ...b.colunas, ...b.linhas.flat()];
    case 'regra':
      return [b.titulo, ...(b.texto ? [b.texto] : [])];
    case 'alerta':
      return [b.texto, ...(b.quem ? [b.quem] : [])];
    case 'script':
      return [b.titulo, b.texto, ...(b.nota ? [b.nota] : [])];
    case 'passos':
    case 'dicas':
    case 'cuidados':
      return [...(b.titulo ? [b.titulo] : []), ...b.itens];
    case 'em_breve':
      return [b.titulo, b.texto];
    case 'pergunta':
      return [b.pergunta, b.resposta, ...(b.link ? [b.link.rotulo] : [])];
    case 'atalhos':
      return b.itens.flatMap((a) => [a.rotulo, a.texto]);
  }
}

export function textosDaSecao(s: Pesquisavel): string[] {
  return [s.titulo, ...(s.resumo ? [s.resumo] : []), ...s.blocos.flatMap(textosDoBloco)];
}

/** Quantas vezes o termo aparece na seção (título, resumo e blocos). */
export function ocorrencias(s: Pesquisavel, termo: string): number {
  if (!termoValido(termo)) return 0;
  return textosDaSecao(s).reduce((n, t) => n + acharTrechos(textoLimpo(t), termo).length, 0);
}

/** Seções com o termo e quantas vezes ele aparece em cada uma (só as que têm). */
export function resultadosBusca(secoes: Pesquisavel[], termo: string): Map<string, number> {
  const r = new Map<string, number>();
  if (!termoValido(termo)) return r;
  for (const s of secoes) {
    const n = ocorrencias(s, termo);
    if (n > 0) r.set(s.id, n);
  }
  return r;
}

/** Números do cabeçalho, contados do próprio conteúdo (nunca escritos à mão). */
export function resumoConteudo(secoes: Pesquisavel[]): { secoes: number; scripts: number; pendencias: number; emAberto: number } {
  const blocos = secoes.flatMap((s) => s.blocos);
  const tabelaAberto = secoes.find((s) => s.id === 'em-aberto')?.blocos.find((b) => b.tipo === 'tabela');
  return {
    secoes: secoes.length,
    scripts: blocos.filter((b) => b.tipo === 'script').length,
    pendencias: blocos.filter((b) => b.tipo === 'alerta' && b.status !== 'em_validacao').length,
    emAberto: tabelaAberto && tabelaAberto.tipo === 'tabela' ? tabelaAberto.linhas.length : 0,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Busca da central de ajuda: várias palavras, ranking e trecho de contexto
// ─────────────────────────────────────────────────────────────────────────────

export interface Achado<T extends Pesquisavel> {
  secao: T;
  /** Quanto maior, mais no topo (título vale mais que corpo). */
  pontos: number;
  /** Pedaço do texto onde a busca aparece, para mostrar no resultado (null se só bateu no título). */
  trecho: string | null;
}

const contar = (texto: string, w: string): number => {
  let n = 0;
  for (let i = texto.indexOf(w); i >= 0; i = texto.indexOf(w, i + w.length)) n++;
  return n;
};

/** Recorta ~`tamanho` letras em volta da primeira palavra achada, cortando em espaço, com reticências. */
export function recortar(texto: string, palavras: string[], tamanho = 160): string {
  const limpo = textoLimpo(texto).replace(/\s+/g, ' ').trim();
  if (limpo.length <= tamanho) return limpo;
  const primeiro = acharPalavras(limpo, palavras)[0]?.[0] ?? 0;
  let ini = Math.max(0, primeiro - Math.floor(tamanho / 3));
  if (ini > 0) { const esp = limpo.indexOf(' ', ini); ini = esp >= 0 && esp < primeiro ? esp + 1 : ini; }
  let fim = Math.min(limpo.length, ini + tamanho);
  if (fim < limpo.length) { const esp = limpo.lastIndexOf(' ', fim); fim = esp > Math.max(ini, primeiro) ? esp : fim; }
  return `${ini > 0 ? '… ' : ''}${limpo.slice(ini, fim)}${fim < limpo.length ? ' …' : ''}`;
}

/**
 * Busca em todas as seções. Toda palavra útil tem de aparecer na seção (título, resumo, corpo ou sinônimo).
 * Ordem: frase inteira no título > palavra no título > sinônimo > resumo > corpo; empate fica na ordem do conteúdo.
 */
export function buscarSecoes<T extends Pesquisavel>(secoes: T[], consulta: string): Achado<T>[] {
  const palavras = palavrasDaBusca(consulta);
  if (palavras.length === 0) return [];
  const frase = palavras.length > 1 ? normalizar(termoValido(consulta)) : '';
  const saida: (Achado<T> & { ordem: number })[] = [];
  secoes.forEach((s, ordem) => {
    const titulo = normalizar(s.titulo);
    const resumo = normalizar(s.resumo ?? '');
    const sinonimos = normalizar((s.sinonimos ?? []).join(' | '));
    const corpoOriginal = s.blocos.flatMap(textosDoBloco).map(textoLimpo);
    const corpo = corpoOriginal.map(normalizar);
    let pontos = 0;
    for (const w of palavras) {
      const noCorpo = corpo.reduce((n, t) => n + contar(t, w), 0);
      const p = contar(titulo, w) * 10 + contar(sinonimos, w) * 6 + contar(resumo, w) * 3 + Math.min(noCorpo, 8);
      if (p === 0) return; // falta uma palavra: a seção não entra
      pontos += p;
    }
    if (frase) {
      if (titulo.includes(frase)) pontos += 20;
      if (corpo.some((t) => t.includes(frase))) pontos += 6;
    }
    // Trecho: o texto do corpo com mais palavras da busca (a frase inteira ganha).
    let melhor = -1;
    let nota = 0;
    corpo.forEach((t, i) => {
      const n = palavras.filter((w) => t.includes(w)).length + (frase && t.includes(frase) ? palavras.length : 0);
      if (n > nota) { nota = n; melhor = i; }
    });
    const trecho = melhor >= 0 ? recortar(corpoOriginal[melhor], palavras) : (s.resumo ? textoLimpo(s.resumo) : null);
    saida.push({ secao: s, pontos, trecho, ordem });
  });
  return saida
    .sort((a, b) => b.pontos - a.pontos || a.ordem - b.ordem)
    .map(({ secao, pontos, trecho }) => ({ secao, pontos, trecho }));
}
