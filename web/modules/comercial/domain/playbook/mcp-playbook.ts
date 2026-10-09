// Playbook e central de ajuda do Comercial para o MCP: índice, leitura em markdown (paginada) e busca.
// Domínio puro (sem React, sem banco). A fonte é a mesma da tela: CENTRAL (ajuda-conteudo.ts), que já traz o
// playbook inteiro (conteudo.ts). Nada de cópia: mudou o texto lá, muda aqui.
//
// Ids: a seção usa o id da central (ex.: "conversa", "modulo-claude"). Subseção = trecho entre dois subtítulos da
// seção, id "<secao>/<slug-do-subtitulo>" (ex.: "funil/as-etapas").
import { CENTRAL, PARTES, type SecaoAjuda } from './ajuda-conteudo';
import type { Bloco } from './conteudo';
import { acharPalavras, buscarSecoes, normalizar, palavrasDaBusca, textoLimpo, textosDoBloco } from './busca';

/** Teto de uma página de leitura (caracteres de markdown). Cabe folgado no contexto e no limite de resposta. */
export const LIMITE_PAGINA = 12_000;
export const URI_PLAYBOOK = 'playbook://comercial/';
const BASE_APP = 'https://grupoparticipa.app.br';

const ROTULO_PARTE = Object.fromEntries(PARTES.map((p) => [p.key, p.titulo])) as Record<SecaoAjuda['parte'], string>;

export interface Subsecao { id: string; titulo: string; blocos: Bloco[] }

export function slug(s: string): string {
  return normalizar(s).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'trecho';
}

/** Divide a seção nos subtítulos. Blocos antes do primeiro subtítulo ficam só na seção (não viram subseção). */
export function subsecoes(s: SecaoAjuda): Subsecao[] {
  const out: Subsecao[] = [];
  const usados = new Map<string, number>();
  for (const b of s.blocos) {
    if (b.tipo === 'subtitulo') {
      const base = slug(b.texto);
      const n = (usados.get(base) ?? 0) + 1;
      usados.set(base, n);
      out.push({ id: `${s.id}/${n > 1 ? `${base}-${n}` : base}`, titulo: textoLimpo(b.texto), blocos: [b] });
    } else if (out.length) {
      out[out.length - 1].blocos.push(b);
    }
  }
  return out;
}

const resumoDe = (s: SecaoAjuda): string => textoLimpo(s.resumo ?? '').replace(/\s+/g, ' ').trim();

// ─── Índice ─────────────────────────────────────────────────────────────────────────────────────────────────────────
export interface ItemIndice {
  id: string;
  titulo: string;
  parte: string;
  grupo: string | null;
  resumo: string;
  subsecoes: { id: string; titulo: string }[];
}

export function indicePlaybook(parte?: SecaoAjuda['parte'] | null): ItemIndice[] {
  return CENTRAL.filter((s) => !parte || s.parte === parte).map((s) => ({
    id: s.id,
    titulo: s.titulo,
    parte: ROTULO_PARTE[s.parte],
    grupo: s.subgrupo ?? null,
    resumo: resumoDe(s),
    subsecoes: subsecoes(s).map(({ id, titulo }) => ({ id, titulo })),
  }));
}

export const PARTES_PLAYBOOK = PARTES.map((p) => p.key);

// ─── Markdown ───────────────────────────────────────────────────────────────────────────────────────────────────────
const ROTULO_ALERTA: Record<string, string> = {
  em_validacao: 'Em validação', a_definir: 'A definir', a_validar: 'A validar', a_revisar: 'A revisar', a_escrever: 'A escrever',
};

/** Link da tela em endereço completo; âncora da central vira referência ao id da seção. */
function destino(href: string): string {
  if (href.startsWith('#')) return `seção ${href.slice(1)}`;
  return href.startsWith('/') ? `${BASE_APP}${href}` : href;
}

const celula = (t: string) => t.replace(/\|/g, '\\|').replace(/\n+/g, ' ');
const citar = (t: string) => t.split('\n').map((l) => `> ${l}`).join('\n');
const itens = (xs: string[], numerada = false) => xs.map((x, i) => `${numerada ? `${i + 1}.` : '-'} ${x}`).join('\n');

export function blocoParaMarkdown(b: Bloco): string {
  switch (b.tipo) {
    case 'paragrafo':
      return b.texto;
    case 'subtitulo':
      return `### ${b.texto}`;
    case 'lista':
      return `${b.titulo ? `**${b.titulo}**\n\n` : ''}${itens(b.itens, b.numerada)}`;
    case 'tabela':
      return `${b.titulo ? `**${b.titulo}**\n\n` : ''}| ${b.colunas.map(celula).join(' | ')} |\n| ${b.colunas.map(() => '---').join(' | ')} |\n`
        + b.linhas.map((l) => `| ${l.map(celula).join(' | ')} |`).join('\n');
    case 'regra':
      return `**Regra${b.numero ? ` ${b.numero}` : ''}: ${b.titulo}**${b.texto ? ` ${b.texto}` : ''}`;
    case 'alerta':
      return citar(`**${ROTULO_ALERTA[b.status] ?? b.status}${b.quem ? ` (quem decide: ${b.quem})` : ''}:** ${b.texto}`);
    case 'script':
      return `**Script: ${b.titulo}**\n\n${citar(b.texto)}${b.nota ? `\n\n_Nota: ${b.nota}_` : ''}`;
    case 'passos':
      return `${b.titulo ? `**${b.titulo}**\n\n` : ''}${itens(b.itens, true)}`;
    case 'dicas':
      return `**${b.titulo ?? 'Dicas'}**\n\n${itens(b.itens)}`;
    case 'cuidados':
      return `**${b.titulo ?? 'Erros comuns e cuidados'}**\n\n${itens(b.itens)}`;
    case 'em_breve':
      return `**Em breve (ainda não existe no sistema): ${b.titulo}.** ${b.texto}`;
    case 'pergunta':
      return `**P: ${b.pergunta}**\n\n${b.resposta}${b.link ? ` (${b.link.rotulo}: ${destino(b.link.href)})` : ''}`;
    case 'atalhos':
      return itens(b.itens.map((a) => `**${a.rotulo}** (${destino(a.href)}): ${a.texto}`));
  }
}

function cabecalho(s: SecaoAjuda, sub?: Subsecao): string {
  const linhas = [`# ${s.titulo}${sub ? ` › ${sub.titulo}` : ''}`, '', `_Seção \`${sub ? sub.id : s.id}\` · ${ROTULO_PARTE[s.parte]}${s.subgrupo ? ` › ${s.subgrupo}` : ''}_`];
  if (!sub && s.resumo) linhas.push('', resumoDe(s));
  if (!sub && s.ferramentas?.length) linhas.push('', `Telas: ${s.ferramentas.map((f) => `${f.rotulo} (${destino(f.href)})`).join('; ')}`);
  return linhas.join('\n');
}

/** Corta texto maior que o limite em pedaços (só para bloco gigante; o normal é quebrar entre blocos). */
function fatiar(t: string, max: number): string[] {
  if (t.length <= max) return [t];
  const out: string[] = [];
  for (let i = 0; i < t.length; i += max) out.push(t.slice(i, i + max));
  return out;
}

/** Páginas de markdown: cabeçalho na primeira, quebra só entre blocos. */
export function paginar(cab: string, blocos: Bloco[], limite = LIMITE_PAGINA): string[] {
  const partes = [cab, ...blocos.map(blocoParaMarkdown)].flatMap((t) => fatiar(t, limite));
  const paginas: string[] = [];
  let atual = '';
  for (const t of partes) {
    if (atual && atual.length + 2 + t.length > limite) { paginas.push(atual); atual = ''; }
    atual = atual ? `${atual}\n\n${t}` : t;
  }
  if (atual) paginas.push(atual);
  return paginas;
}

export function acharSecao(id: string): { secao: SecaoAjuda; sub?: Subsecao } | null {
  const [base, resto] = id.trim().toLowerCase().split('/', 2);
  const secao = CENTRAL.find((s) => s.id === base);
  if (!secao) return null;
  if (resto === undefined) return { secao };
  const sub = subsecoes(secao).find((x) => x.id === `${base}/${resto}`);
  return sub ? { secao, sub } : null;
}

/** Markdown inteiro de uma seção ou subseção (sem paginar). null = id não existe. */
export function markdownSecao(id: string): { secao: SecaoAjuda; sub?: Subsecao; markdown: string } | null {
  const a = acharSecao(id);
  if (!a) return null;
  return { ...a, markdown: paginar(cabecalho(a.secao, a.sub), a.sub ? a.sub.blocos.slice(1) : a.secao.blocos, Infinity)[0] };
}

export type Leitura =
  | { ok: true; id: string; titulo: string; parte: string; pagina: number; paginas: number; proximaPagina: number | null; markdown: string }
  | { ok: false; msg: string };

export function lerSecao(id: string, pagina = 1, limite = LIMITE_PAGINA): Leitura {
  const a = acharSecao(id);
  if (!a) return { ok: false, msg: `Seção "${id.slice(0, 80)}" não existe. Use comercial_playbook_indice ou comercial_playbook_buscar para achar o id.` };
  const paginas = paginar(cabecalho(a.secao, a.sub), a.sub ? a.sub.blocos.slice(1) : a.secao.blocos, limite);
  if (pagina > paginas.length) return { ok: false, msg: `A seção tem ${paginas.length} página(s).` };
  return {
    ok: true,
    id: a.sub ? a.sub.id : a.secao.id,
    titulo: a.sub ? `${a.secao.titulo} › ${a.sub.titulo}` : a.secao.titulo,
    parte: ROTULO_PARTE[a.secao.parte],
    pagina,
    paginas: paginas.length,
    proximaPagina: pagina < paginas.length ? pagina + 1 : null,
    markdown: paginas[pagina - 1],
  };
}

// ─── Busca ──────────────────────────────────────────────────────────────────────────────────────────────────────────
export interface AchadoPlaybook {
  id: string;
  titulo: string;
  parte: string;
  /** Subseção onde a busca mais aparece (para ler só o trecho), se houver. */
  subsecao: { id: string; titulo: string } | null;
  trecho: string | null;
  pontos: number;
}

/** Subseção com mais ocorrências das palavras da busca. */
function melhorSubsecao(s: SecaoAjuda, palavras: string[]): Subsecao | null {
  let melhor: Subsecao | null = null;
  let max = 0;
  for (const sub of subsecoes(s)) {
    const n = sub.blocos.flatMap(textosDoBloco).reduce((t, x) => t + acharPalavras(textoLimpo(x), palavras).length, 0);
    if (n > max) { max = n; melhor = sub; }
  }
  return melhor;
}

/** A mesma busca da tela (busca.ts: todas as palavras, sem acento, ranking título > sinônimo > resumo > corpo). */
export function buscarPlaybook(consulta: string, limite = 8): AchadoPlaybook[] {
  const palavras = palavrasDaBusca(consulta);
  return buscarSecoes(CENTRAL, consulta).slice(0, limite).map(({ secao, pontos, trecho }) => {
    const sub = melhorSubsecao(secao, palavras);
    return {
      id: secao.id,
      titulo: secao.titulo,
      parte: ROTULO_PARTE[secao.parte],
      subsecao: sub ? { id: sub.id, titulo: sub.titulo } : null,
      trecho,
      pontos,
    };
  });
}

// ─── Resources (resources/list e resources/read) ────────────────────────────────────────────────────────────────────
export function recursosPlaybook() {
  return CENTRAL.map((s) => ({
    uri: `${URI_PLAYBOOK}${s.id}`,
    name: s.id,
    title: `${ROTULO_PARTE[s.parte]} › ${s.titulo}`,
    description: resumoDe(s) || undefined,
    mimeType: 'text/markdown',
  }));
}

/** Conteúdo de um resource pelo URI (seção ou subseção). null = não existe. */
export function lerRecursoPlaybook(uri: unknown): { uri: string; mimeType: 'text/markdown'; text: string } | null {
  if (typeof uri !== 'string' || !uri.startsWith(URI_PLAYBOOK) || uri.length > 200) return null;
  let id: string;
  try { id = decodeURIComponent(uri.slice(URI_PLAYBOOK.length)); } catch { return null; }
  const m = markdownSecao(id);
  return m ? { uri, mimeType: 'text/markdown', text: m.markdown } : null;
}
