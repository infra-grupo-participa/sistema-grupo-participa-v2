// Estratégias do Comercial (ex-"Recuperação", 07/10/2026). Domínio puro: tipos, situações, regras do pedido e textos.
// Banco: migration 20261007150701 (crm.estrategia + RPCs crm_estrategia_*). As regras de permissão moram no banco;
// aqui ficam espelhadas só para a tela não oferecer o que o banco vai recusar.
import type { ProdutoKey } from './types';

export type SituacaoEstrategia = 'solicitada' | 'em_analise' | 'em_execucao' | 'concluida' | 'recusada';
export type PrioridadeEstrategia = 'baixa' | 'media' | 'alta' | 'urgente';
export type TipoAcao = 'fila' | 'funil';
export type BasePublico = 'alunos' | 'contatos' | 'compradores';

/** Regra de pesquisa do Respondi: casa quem respondeu UMA das perguntas (texto exato) com resposta que CONTÉM um dos trechos. */
export interface RegraPesquisa {
  perguntas: string[];
  contem: string[];
  /** Formulários (slug) a que a regra se limita; vazio = todos. */
  forms?: string[];
}

/** Filtros estruturados do público (mesmo formato do jsonb `crm.estrategia.filtros`). Tudo opcional. */
export interface FiltrosPublico {
  base?: BasePublico;
  alunos?: { niveis?: string[]; turmas?: string[]; tiposTurma?: string[]; planos?: string[]; statusAcesso?: string[] };
  comprou?: { produtos?: string[]; linhas?: string[] };
  naoComprou?: { produtos?: string[]; linhas?: string[] };
  respondi?: { regras: RegraPesquisa[] };
  catalogacao?: { projetos?: string[]; canais?: string[] };
  /** Opt-out sai sempre. Estes dois saem por padrão (true). */
  excluir?: { emNegociacao?: boolean; outraAcao?: boolean };
}

export interface PlacarAcao {
  naLista: number;
  abordadas: number;
  emConversa: number;
  vendas: number;
  receita: number;
}

export interface HistoricoEstrategia {
  de: SituacaoEstrategia | null;
  para: SituacaoEstrategia;
  porNome: string | null;
  nota: string | null;
  em: string;
}

export interface Estrategia {
  id: string;
  titulo: string;
  objetivo: string;
  publico: string;
  filtros: FiltrosPublico;
  modelo: string | null;
  linha: ProdutoKey | null;
  oferta: string | null;
  prazo: string | null;
  prioridade: PrioridadeEstrategia;
  observacoes: string;
  solicitanteId: string;
  solicitanteNome: string;
  situacao: SituacaoEstrategia;
  motivoRecusa: string | null;
  responsavelId: string | null;
  responsavelNome: string | null;
  acaoTipo: TipoAcao | null;
  filaId: string | null;
  funilId: string | null;
  acaoCriadaEm: string | null;
  acaoPessoas: number | null;
  criadoEm: string;
  atualizadoEm: string;
  placar: PlacarAcao | null;
  /** Só no detalhe. */
  historico?: HistoricoEstrategia[];
}

export interface ModeloPublico {
  chave: string;
  nome: string;
  descricao: string;
  filtros: FiltrosPublico;
}

export interface OpcoesFiltro {
  niveis: string[];
  turmas: { codigo: string; tipo: string }[];
  planos: string[];
  statusAcesso: string[];
  linhas: { chave: ProdutoKey; nome: string; escada: string }[];
  produtos: { id: string; nome: string }[];
  projetos: string[];
  canais: string[];
  perguntas: { pergunta: string; formularios: number }[];
}

export interface AmostraPessoa {
  nome: string;
  email: string | null;
  nivel: string | null;
  turma: string | null;
}

export interface PreviaPublico {
  total: number;
  excluidos: { optOut: number; jaComprou: number; emNegociacao: number; outraAcao: number };
  /** Só para o gestor; nome curto e e-mail mascarado. */
  amostra: AmostraPessoa[];
}

export interface AcessoEstrategias {
  solicitar: boolean;
  gestor: boolean;
}

export interface NovaSolicitacao {
  id?: string;
  titulo: string;
  objetivo: string;
  publico: string;
  filtros: FiltrosPublico;
  modelo: string | null;
  linha: ProdutoKey | null;
  oferta: string;
  prazo: string | null;
  prioridade: PrioridadeEstrategia;
  observacoes: string;
}

// ── Textos ──

export const ROTULO_SITUACAO: Record<SituacaoEstrategia, string> = {
  solicitada: 'Solicitada',
  em_analise: 'Em análise',
  em_execucao: 'Em execução',
  concluida: 'Concluída',
  recusada: 'Recusada',
};

export const TOM_SITUACAO: Record<SituacaoEstrategia, 'neutral' | 'info' | 'warning' | 'success' | 'danger'> = {
  solicitada: 'neutral',
  em_analise: 'info',
  em_execucao: 'warning',
  concluida: 'success',
  recusada: 'danger',
};

export const ROTULO_PRIORIDADE: Record<PrioridadeEstrategia, string> = {
  baixa: 'Baixa',
  media: 'Média',
  alta: 'Alta',
  urgente: 'Urgente',
};

export const ROTULO_TIPO_ACAO: Record<TipoAcao, string> = {
  fila: 'Fila de recuperação',
  funil: 'Funil próprio',
};

export const ROTULO_BASE: Record<BasePublico, string> = {
  alunos: 'Alunos',
  contatos: 'Contatos do CRM',
  compradores: 'Compradores (Hotmart)',
};

/** Teto do funil próprio (o banco recusa acima disto; fila vai até 5.000). */
export const LIMITE_FUNIL = 300;
export const LIMITE_FILA = 5000;

// ── Regras ──

/** Para onde o gestor pode levar o pedido (mesma tabela da RPC crm_estrategia_situacao). em_execucao também nasce de "Transformar em ação". */
export const TRANSICOES: Record<SituacaoEstrategia, SituacaoEstrategia[]> = {
  solicitada: ['em_analise', 'recusada'],
  em_analise: ['em_execucao', 'recusada'],
  em_execucao: ['concluida'],
  concluida: [],
  recusada: [],
};

export function proximasSituacoes(s: SituacaoEstrategia): SituacaoEstrategia[] {
  return TRANSICOES[s];
}

/** Pode virar ação: ainda não virou e não foi encerrado. */
export function podeTransformar(e: Pick<Estrategia, 'situacao' | 'acaoTipo'>): boolean {
  return !e.acaoTipo && (e.situacao === 'solicitada' || e.situacao === 'em_analise');
}

/** O solicitante só edita enquanto o Comercial não pegou o pedido. */
export function podeEditarPedido(e: Pick<Estrategia, 'situacao'>): boolean {
  return e.situacao === 'solicitada';
}

/** Filtros vazios = sem público estruturado (só o texto livre). */
export function filtrosVazios(f: FiltrosPublico | null | undefined): boolean {
  if (!f) return true;
  return Object.keys(limparFiltros(f)).length === 0;
}

/** Tira listas vazias e blocos sem conteúdo (o banco recebe só o que filtra de verdade). */
export function limparFiltros(f: FiltrosPublico): FiltrosPublico {
  const lista = (a?: string[]) => (a ?? []).map((x) => x.trim()).filter(Boolean);
  const bloco = <T extends Record<string, string[] | undefined>>(b?: T): Partial<T> | undefined => {
    if (!b) return undefined;
    const out: Record<string, string[]> = {};
    for (const [k, v] of Object.entries(b)) {
      const l = lista(v);
      if (l.length) out[k] = l;
    }
    return Object.keys(out).length ? (out as Partial<T>) : undefined;
  };
  const r: FiltrosPublico = {};
  const alunos = bloco(f.alunos);
  const comprou = bloco(f.comprou);
  const naoComprou = bloco(f.naoComprou);
  const catalogacao = bloco(f.catalogacao);
  const regras = (f.respondi?.regras ?? [])
    .map((g) => ({ ...g, perguntas: lista(g.perguntas), contem: lista(g.contem), ...(g.forms?.length ? { forms: lista(g.forms) } : {}) }))
    .filter((g) => g.perguntas.length && g.contem.length);
  if (alunos) r.alunos = alunos;
  if (comprou) r.comprou = comprou;
  if (naoComprou) r.naoComprou = naoComprou;
  if (catalogacao) r.catalogacao = catalogacao;
  if (regras.length) r.respondi = { regras };
  const temAlgo = Object.keys(r).length > 0;
  if (temAlgo || (f.base && f.base !== 'alunos')) r.base = f.base ?? 'alunos';
  if (temAlgo && f.excluir && (f.excluir.emNegociacao === false || f.excluir.outraAcao === false)) {
    r.excluir = { emNegociacao: f.excluir.emNegociacao !== false, outraAcao: f.excluir.outraAcao !== false };
  }
  return r;
}

/** Mesmas regras de formato da RPC (crm.estrategia_validar_filtros). null = ok. */
export function validarFiltros(f: FiltrosPublico): string | null {
  const base = f.base ?? 'alunos';
  if (base === 'compradores' && !(f.comprou?.produtos?.length || f.comprou?.linhas?.length)) {
    return 'Base de compradores precisa do filtro "comprou".';
  }
  const regras = f.respondi?.regras ?? [];
  if (regras.length > 20) return 'No máximo 20 regras de pesquisa.';
  for (const g of regras) {
    if (!g.perguntas.some((x) => x.trim()) || !g.contem.some((x) => x.trim())) return 'Cada regra de pesquisa precisa de pergunta e resposta.';
    if (g.contem.some((x) => x.trim() && x.trim().length < 3)) return 'Resposta da regra de pesquisa com menos de 3 letras.';
  }
  return null;
}

/** Valida o pedido antes de mandar (mesmas mensagens da RPC crm_estrategia_salvar). */
export function validarSolicitacao(s: NovaSolicitacao, hoje: Date): string | null {
  if (s.titulo.trim().length < 3) return 'Dê um título ao pedido.';
  if (s.titulo.trim().length > 120) return 'Título com mais de 120 letras.';
  if (s.objetivo.trim().length < 3) return 'Descreva o objetivo.';
  if (s.prazo) {
    const d = s.prazo.slice(0, 10);
    const h = `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}-${String(hoje.getDate()).padStart(2, '0')}`;
    if (d < h) return 'Prazo no passado.';
  }
  return filtrosVazios(s.filtros) ? null : validarFiltros(s.filtros);
}

/** Taxas do placar (0 quando a lista está vazia; nunca NaN). */
export function taxasPlacar(p: PlacarAcao | null): { abordagem: number; conversa: number; conversao: number } {
  if (!p || p.naLista <= 0) return { abordagem: 0, conversa: 0, conversao: 0 };
  const pct = (n: number) => Math.round((n / p.naLista) * 1000) / 10;
  return { abordagem: pct(p.abordadas), conversa: pct(p.emConversa), conversao: pct(p.vendas) };
}

/** Frases curtas do público, para o cartão do pedido e a ficha (sem dado pessoal). */
export function resumoFiltros(f: FiltrosPublico, nomeProduto: (id: string) => string = (id) => id): string[] {
  const l = limparFiltros(f);
  const out: string[] = [];
  if (filtrosVazios(l)) return out;
  out.push(`Base: ${ROTULO_BASE[l.base ?? 'alunos']}`);
  const a = l.alunos;
  if (a?.tiposTurma?.length) out.push(`Turma: ${a.tiposTurma.map((t) => t.toUpperCase()).join(', ')}`);
  if (a?.turmas?.length) out.push(`Turmas: ${a.turmas.join(', ')}`);
  if (a?.niveis?.length) out.push(`Nível: ${a.niveis.join(', ')}`);
  if (a?.planos?.length) out.push(`Plano: ${a.planos.join(', ')}`);
  if (a?.statusAcesso?.length) out.push(`Acesso: ${a.statusAcesso.join(', ')}`);
  const prod = (b?: { produtos?: string[]; linhas?: string[] }) =>
    [...(b?.linhas ?? []).map((x) => x.toUpperCase()), ...(b?.produtos ?? []).map(nomeProduto)];
  if (l.comprou) out.push(`Comprou: ${[...new Set(prod(l.comprou))].join(', ')}`);
  if (l.naoComprou) out.push(`Não comprou: ${[...new Set(prod(l.naoComprou))].join(', ')}`);
  const n = l.respondi?.regras.length ?? 0;
  if (n) out.push(`Pesquisas: ${n} regra${n > 1 ? 's' : ''} de resposta`);
  if (l.catalogacao?.projetos?.length) out.push(`Projeto: ${l.catalogacao.projetos.join(', ')}`);
  if (l.catalogacao?.canais?.length) out.push(`Canal: ${l.catalogacao.canais.join(', ')}`);
  const fora = ['opt-out'];
  if (l.excluir?.emNegociacao !== false) fora.push('em negociação');
  if (l.excluir?.outraAcao !== false) fora.push('em outra ação');
  out.push(`Saem: ${fora.join(', ')}`);
  return out;
}

/** Ordem da lista: abertos primeiro (urgente → baixa, prazo mais perto), depois encerrados (mais recente primeiro). */
const PESO_PRIORIDADE: Record<PrioridadeEstrategia, number> = { urgente: 0, alta: 1, media: 2, baixa: 3 };
export function ordenarPedidos(lista: Estrategia[]): Estrategia[] {
  const aberto = (e: Estrategia) => e.situacao !== 'concluida' && e.situacao !== 'recusada';
  return [...lista].sort((x, y) => {
    if (aberto(x) !== aberto(y)) return aberto(x) ? -1 : 1;
    if (aberto(x)) {
      const p = PESO_PRIORIDADE[x.prioridade] - PESO_PRIORIDADE[y.prioridade];
      if (p) return p;
      const px = x.prazo ?? '9999', py = y.prazo ?? '9999';
      if (px !== py) return px < py ? -1 : 1;
    }
    return y.criadoEm.localeCompare(x.criadoEm);
  });
}
