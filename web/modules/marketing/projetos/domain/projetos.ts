// Base compartilhada do Marketing: projetos (projeto = edição) e páginas. Domínio puro.
// Banco: mkt.projetos e mkt.paginas (migration 20261005m). Os formatos abaixo são os mesmos dos checks de lá.

/** Sigla do nome de campanha: letras maiúsculas + 2 a 4 dígitos (PB26, HT33, SEMSET26, BF26). */
export const SIGLA_RE = /^[A-Z]{2,10}[0-9]{2,4}$/;
/** Código da página no padrão da casa: 2 letras + número, sufixo opcional (ak1, bl2, jt10, ak21, ak1-b). */
export const CODIGO_PAGINA_RE = /^[a-z]{2}[0-9]{1,3}(-[a-z])?$/;
/** Etiqueta de projeto do ClickUp: minúsculas, números e hífen (seminario-conjunto-2026-11). */
export const ETIQUETA_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export const SUBAREAS = ['interno', 'aurum', 'diamante'] as const;
export type SubareaTrafego = (typeof SUBAREAS)[number];

export const FUNCOES_PAGINA = ['captura', 'obrigado', 'quase_la', 'pesquisa', 'venda', 'outra'] as const;
export type FuncaoPagina = (typeof FUNCOES_PAGINA)[number];

export const ROTULO_FUNCAO: Record<FuncaoPagina, string> = {
  captura: 'Captura',
  obrigado: 'Obrigado',
  quase_la: 'Quase lá',
  pesquisa: 'Pesquisa',
  venda: 'Venda',
  outra: 'Outra',
};

export const ROTULO_SUBAREA: Record<SubareaTrafego, string> = { interno: 'Interno', aurum: 'Aurum', diamante: 'Diamante' };
/** Desde a 20261006a a subárea é derivada de tipo e unidade (Interno; Externo Aurum; Externo Diamantes). A unidade interna
 *  (CSM ou Escritório) e o resto do cadastro do evento ficam na Central do Tráfego. */
export const ROTULO_TIPO_SUBAREA: Record<SubareaTrafego, string> = { interno: 'Interno', aurum: 'Externo · Aurum', diamante: 'Externo · Diamantes' };

export interface Projeto {
  id: number;
  sigla: string;
  nome: string;
  linha: string;
  edicao: string | null;
  ano: number | null;
  etiqueta_clickup: string | null;
  subarea_trafego: SubareaTrafego | null;
  inicio: string | null;
  fim: string | null;
  ativo: boolean;
  obs: string | null;
  paginas: number;
}

export interface Pagina {
  id: number;
  projeto_id: number;
  projeto_sigla: string;
  codigo: string | null;
  nome: string;
  dominio: string;
  caminho: string;
  url: string;
  funcao: FuncaoPagina;
  funil: string | null;
  ativa: boolean;
  obs: string | null;
}

/** Normaliza a sigla como o banco grava (maiúsculas, sem espaço). */
export const normalizarSigla = (s: string) => s.trim().toUpperCase();

/** Erro de formulário do projeto antes de chamar o banco (o banco confere de novo). */
export function validarProjeto(p: { sigla: string; nome: string; linha: string; etiqueta_clickup?: string | null; inicio?: string | null; fim?: string | null }): string | null {
  if (!SIGLA_RE.test(normalizarSigla(p.sigla))) return 'Sigla inválida: letras maiúsculas seguidas de 2 a 4 dígitos (ex.: PB26, HT33, SEMSET26).';
  if (p.nome.trim().length < 2) return 'Informe o nome do projeto.';
  if (p.linha.trim().length < 2) return 'Informe o tipo/linha (ex.: Patrimônio Brasil).';
  const etq = (p.etiqueta_clickup ?? '').trim();
  if (etq && !ETIQUETA_RE.test(etq)) return 'Etiqueta do ClickUp inválida: minúsculas, números e hífen, exatamente como no ClickUp.';
  if (p.inicio && p.fim && p.fim < p.inicio) return 'O fim não pode ser antes do início.';
  return null;
}

/** Erro de formulário da página antes de chamar o banco. Aceita código em maiúsculas (vira minúsculas). */
export function validarCodigoPagina(codigo: string): string | null {
  const c = codigo.trim().toLowerCase();
  if (c === '') return null;
  return CODIGO_PAGINA_RE.test(c) ? null : 'Código fora do padrão da casa: 2 letras + número, com sufixo opcional (ak1, bl2, ak1-b).';
}
