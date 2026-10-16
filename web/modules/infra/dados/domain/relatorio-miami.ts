// Contrato da função public.dados_miami_relatorio (docs/dashboard-presencial.md §2.12.1) e a transformação pura que a tela usa.
// Os valores são o texto formatado da planilha: "—" e "88,2%" ficam como texto. Aqui nada vira número sem regra explícita.

export type ItemKpi = { rotulo: string; valor: string | null };
export type BlocoKpi = { titulo: string; itens: ItemKpi[] };
export type BlocoTabela = { titulo: string; colunas: string[]; linhas: string[][] };
export type AvisoRelatorio = { codigo: string; texto: string };
export type ConteudoRelatorioMiami = {
  versao: 1;
  aba: string;
  avisos: AvisoRelatorio[];
  blocos: {
    dados_iniciais: BlocoKpi; time_formulario: BlocoKpi; participacao: BlocoKpi;
    camisas: BlocoTabela; presenca: BlocoTabela; diamantes: BlocoTabela; compradores: BlocoTabela;
  };
};
export type RespostaRelatorioMiami = {
  disponivel: boolean;
  md5: string | null;
  igual: boolean;
  lido_em: string | null;
  tentado_em: string | null;
  erro: string | null;
  contato_visivel: boolean;
  conteudo: ConteudoRelatorioMiami | null;
};

const ehObjeto = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const textoOuNulo = (v: unknown): string | null => typeof v === 'string' ? v : null;
const celula = (v: unknown): string => typeof v === 'string' ? v : '';

function lerKpi(bruto: unknown): BlocoKpi | null {
  if (!ehObjeto(bruto) || typeof bruto.titulo !== 'string' || !Array.isArray(bruto.itens)) return null;
  const itens: ItemKpi[] = [];
  for (const item of bruto.itens) {
    if (!ehObjeto(item) || typeof item.rotulo !== 'string') return null;
    itens.push({ rotulo: item.rotulo, valor: textoOuNulo(item.valor) });
  }
  return { titulo: bruto.titulo, itens };
}

function lerTabela(bruto: unknown): BlocoTabela | null {
  if (!ehObjeto(bruto) || typeof bruto.titulo !== 'string' || !Array.isArray(bruto.colunas) || !Array.isArray(bruto.linhas)) return null;
  if (!bruto.colunas.every((c) => typeof c === 'string')) return null;
  const colunas = bruto.colunas as string[];
  const linhas: string[][] = [];
  for (const linha of bruto.linhas) {
    if (!Array.isArray(linha)) return null;
    // Contrato: linhas[i][k] corresponde a colunas[k] e célula sem valor vem string vazia. Linha curta completa com vazio, nunca inventa valor.
    linhas.push(colunas.map((_, k) => celula(linha[k])));
  }
  return { titulo: bruto.titulo, colunas, linhas };
}

function lerConteudo(bruto: unknown): ConteudoRelatorioMiami | null {
  if (!ehObjeto(bruto) || bruto.versao !== 1 || typeof bruto.aba !== 'string' || !ehObjeto(bruto.blocos)) return null;
  const avisos: AvisoRelatorio[] = [];
  for (const aviso of Array.isArray(bruto.avisos) ? bruto.avisos : []) {
    if (ehObjeto(aviso) && typeof aviso.codigo === 'string' && typeof aviso.texto === 'string') avisos.push({ codigo: aviso.codigo, texto: aviso.texto });
  }
  const b = bruto.blocos;
  const dados_iniciais = lerKpi(b.dados_iniciais);
  const time_formulario = lerKpi(b.time_formulario);
  const participacao = lerKpi(b.participacao);
  const camisas = lerTabela(b.camisas);
  const presenca = lerTabela(b.presenca);
  const diamantes = lerTabela(b.diamantes);
  const compradores = lerTabela(b.compradores);
  if (!dados_iniciais || !time_formulario || !participacao || !camisas || !presenca || !diamantes || !compradores) return null;
  return { versao: 1, aba: bruto.aba, avisos, blocos: { dados_iniciais, time_formulario, participacao, camisas, presenca, diamantes, compradores } };
}

/** Valida a resposta do banco. Devolve null quando o formato não é o do contrato (a tela trata como falha de leitura). */
export function lerRespostaRelatorio(bruto: unknown): RespostaRelatorioMiami | null {
  const r = Array.isArray(bruto) ? bruto[0] : bruto;
  if (!ehObjeto(r) || typeof r.disponivel !== 'boolean') return null;
  const igual = r.igual === true;
  let conteudo: ConteudoRelatorioMiami | null = null;
  if (r.conteudo != null) {
    conteudo = lerConteudo(r.conteudo);
    if (!conteudo) return null;
  }
  if (r.disponivel && !igual && !conteudo) return null;
  return {
    disponivel: r.disponivel,
    md5: textoOuNulo(r.md5),
    igual,
    lido_em: textoOuNulo(r.lido_em),
    tentado_em: textoOuNulo(r.tentado_em),
    erro: textoOuNulo(r.erro),
    // O contrato fixa true hoje. Só um false explícito esconde contato: ausência não esconde nem inventa.
    contato_visivel: r.contato_visivel !== false,
    conteudo,
  };
}

// ---------- KPIs ----------

export type GrupoKpi = { titulo: string; itens: ItemKpi[] };
/** Item sem valor é cabeçalho de subgrupo (ex.: "Situação de quem respondeu"); os itens seguintes pertencem a ele. */
export function agruparItens(itens: ItemKpi[]): { soltos: ItemKpi[]; grupos: GrupoKpi[] } {
  const soltos: ItemKpi[] = [];
  const grupos: GrupoKpi[] = [];
  for (const item of itens) {
    if (item.valor === null) { grupos.push({ titulo: item.rotulo, itens: [] }); continue; }
    if (grupos.length) grupos[grupos.length - 1].itens.push(item);
    else soltos.push(item);
  }
  return { soltos, grupos };
}

/** "88,2%" → 88.2. Só percentual completo; qualquer outra coisa (inclusive "—") é null, nunca 0. */
export function percentualDe(valor: string | null | undefined): number | null {
  const m = /^(\d{1,3}(?:,\d+)?)\s*%$/.exec((valor ?? '').trim());
  if (!m) return null;
  const n = Number(m[1].replace(',', '.'));
  return n >= 0 && n <= 100 ? n : null;
}

/** "76" → 76, "1.234" → 1234. Só inteiro pt-BR; "—", "88,2%" e vazio são null. */
export function inteiroDe(valor: string | null | undefined): number | null {
  const t = (valor ?? '').trim();
  if (!/^\d{1,3}(\.\d{3})+$|^\d+$/.test(t)) return null;
  return Number(t.replace(/\./g, ''));
}

// ---------- Tabelas ----------

export type LinhaIndexada = { i: number; celulas: string[] };
export const indexar = (linhas: string[][]): LinhaIndexada[] => linhas.map((celulas, i) => ({ i, celulas }));

/** Vazio de verdade: célula sem texto ou o travessão que a planilha usa para "não se aplica". */
export const ehVazio = (valor: string): boolean => valor.trim() === '' || valor.trim() === '—';

const semAcento = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR');

export function buscar(linhas: LinhaIndexada[], termo: string): LinhaIndexada[] {
  const t = semAcento(termo.trim());
  if (!t) return linhas;
  return linhas.filter((l) => l.celulas.some((c) => semAcento(c).includes(t)));
}

export function filtrarPorValor(linhas: LinhaIndexada[], coluna: number, valor: string): LinhaIndexada[] {
  return linhas.filter((l) => l.celulas[coluna] === valor);
}

type ChaveOrdem = { tipo: 'num' | 'data' | 'texto'; n: number; s: string };
function chaveOrdem(valor: string): ChaveOrdem {
  const t = valor.trim();
  const data = /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/.exec(t);
  if (data) return { tipo: 'data', n: Date.UTC(Number(data[3]), Number(data[2]) - 1, Number(data[1]), Number(data[4] ?? 0), Number(data[5] ?? 0)), s: t };
  if (/^-?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?%?$/.test(t)) return { tipo: 'num', n: Number(t.replace('%', '').replace(/\./g, '').replace(',', '.')), s: t };
  return { tipo: 'texto', n: 0, s: t };
}

/** Ordena sem mexer na lista original. Vazio e "—" ficam sempre no fim, nos dois sentidos. Estável (empate mantém a ordem da planilha). */
export function ordenar(linhas: LinhaIndexada[], coluna: number, dir: 'asc' | 'desc'): LinhaIndexada[] {
  const sinal = dir === 'asc' ? 1 : -1;
  return [...linhas].sort((a, b) => {
    const va = a.celulas[coluna] ?? '';
    const vb = b.celulas[coluna] ?? '';
    const ea = ehVazio(va);
    const eb = ehVazio(vb);
    if (ea || eb) return ea === eb ? a.i - b.i : ea ? 1 : -1;
    const ka = chaveOrdem(va);
    const kb = chaveOrdem(vb);
    const c = ka.tipo === kb.tipo && ka.tipo !== 'texto' ? ka.n - kb.n : ka.s.localeCompare(kb.s, 'pt-BR', { numeric: true, sensitivity: 'base' });
    return c === 0 ? a.i - b.i : c * sinal;
  });
}

export type BarraRelatorio = { valor: string; rotulo: string; quantidade: number };
export type DistribuicaoColuna = { coluna: number; titulo: string; valores: string[] };

/** Valores distintos de uma coluna (strings exatas, vazios fora), em ordem de frequência. Null quando a coluna não é categórica (acima do teto) ou não tem valor. */
export function valoresCategoricos(linhas: string[][], coluna: number, maxCategorias = 12): string[] | null {
  const contagem = new Map<string, number>();
  for (const l of linhas) {
    const v = l[coluna] ?? '';
    if (!ehVazio(v)) contagem.set(v, (contagem.get(v) ?? 0) + 1);
  }
  if (contagem.size === 0 || contagem.size > maxCategorias) return null;
  return [...contagem.entries()].sort((a, b) => b[1] - a[1]).map(([v]) => v);
}

/** Contagem de linhas por valor, para as barras. `valores` fixa quais barras existem (uma barra selecionada nunca some quando o filtro zera). */
export function contarPorValor(linhas: LinhaIndexada[], coluna: number, valores: string[]): { barras: BarraRelatorio[]; semValor: number } {
  const contagem = new Map<string, number>(valores.map((v) => [v, 0]));
  let semValor = 0;
  for (const l of linhas) {
    const v = l.celulas[coluna] ?? '';
    if (ehVazio(v)) semValor++;
    else if (contagem.has(v)) contagem.set(v, (contagem.get(v) ?? 0) + 1);
  }
  return { barras: valores.map((v) => ({ valor: v, rotulo: v, quantidade: contagem.get(v) ?? 0 })), semValor };
}

/** Uma barra por linha da tabela, com o número já pronto da planilha. Célula "—" ou vazia não vira barra (não é zero). */
export function barrasDeColuna(tabela: BlocoTabela, colunaValor: string): { barras: (BarraRelatorio & { linha: number })[]; semDado: number } | null {
  const k = tabela.colunas.indexOf(colunaValor);
  if (k < 0) return null;
  const barras: (BarraRelatorio & { linha: number })[] = [];
  let semDado = 0;
  tabela.linhas.forEach((l, i) => {
    const n = inteiroDe(l[k]);
    if (n === null) semDado++;
    else barras.push({ valor: String(i), rotulo: l[0], quantidade: n, linha: i });
  });
  return barras.length ? { barras, semDado } : null;
}

/** "há 3 min", "há 2 h", "há 4 d". Null quando a data não é válida ou está no futuro. */
export function idadeCurta(iso: string | null | undefined, agora: number): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t) || t > agora + 60_000) return null;
  const min = Math.floor(Math.max(0, agora - t) / 60_000);
  if (min < 1) return 'agora há pouco';
  if (min < 60) return `há ${min} min`;
  if (min < 60 * 48) return `há ${Math.floor(min / 60)} h`;
  return `há ${Math.floor(min / 1440)} d`;
}
