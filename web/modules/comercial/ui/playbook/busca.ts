// Busca e destaque no texto do playbook. Puro (sem React): a tela só chama.
// Busca sem acento e sem caixa ("distribuicao" acha "Distribuição"); **negrito** não atrapalha a busca.
import type { Bloco, Secao } from './conteudo';

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

/** Negrito + destaque do termo, em segmentos contíguos. */
export function segmentar(texto: string, termo: string): Segmento[] {
  const saida: Segmento[] = [];
  for (const parte of separarNegrito(texto)) {
    let ultimo = 0;
    for (const [a, b] of acharTrechos(parte.texto, termo)) {
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
  }
}

export function textosDaSecao(s: Secao): string[] {
  return [s.titulo, ...(s.resumo ? [s.resumo] : []), ...s.blocos.flatMap(textosDoBloco)];
}

/** Quantas vezes o termo aparece na seção (título, resumo e blocos). */
export function ocorrencias(s: Secao, termo: string): number {
  if (!termoValido(termo)) return 0;
  return textosDaSecao(s).reduce((n, t) => n + acharTrechos(textoLimpo(t), termo).length, 0);
}

/** Seções com o termo e quantas vezes ele aparece em cada uma (só as que têm). */
export function resultadosBusca(secoes: Secao[], termo: string): Map<string, number> {
  const r = new Map<string, number>();
  if (!termoValido(termo)) return r;
  for (const s of secoes) {
    const n = ocorrencias(s, termo);
    if (n > 0) r.set(s.id, n);
  }
  return r;
}

/** Números do cabeçalho, contados do próprio conteúdo (nunca escritos à mão). */
export function resumoConteudo(secoes: Secao[]): { secoes: number; scripts: number; pendencias: number; emAberto: number } {
  const blocos = secoes.flatMap((s) => s.blocos);
  const tabelaAberto = secoes.find((s) => s.id === 'em-aberto')?.blocos.find((b) => b.tipo === 'tabela');
  return {
    secoes: secoes.length,
    scripts: blocos.filter((b) => b.tipo === 'script').length,
    pendencias: blocos.filter((b) => b.tipo === 'alerta' && b.status !== 'em_validacao').length,
    emAberto: tabelaAberto && tabelaAberto.tipo === 'tabela' ? tabelaAberto.linhas.length : 0,
  };
}
