// Mapeamento PURO das RPCs das Estratégias (migration 20261007150701): jsonb camelCase → domínio, e argumentos.
// Formato fora do contrato vira exceção (nunca lista vazia calada).
import {
  limparFiltros,
  type AcessoEstrategias, type Estrategia, type FiltrosPublico, type HistoricoEstrategia, type ModeloPublico, type NovaSolicitacao,
  type OpcoesFiltro, type PlacarAcao, type PreviaPublico, type PrioridadeEstrategia, type SituacaoEstrategia, type TipoAcao,
} from '../domain/estrategias';
import type { ProdutoKey } from '../domain/types';
import { FormatoInesperado } from './mapeamento-supabase';

type Obj = Record<string, unknown>;

function obj(v: unknown, rpc: string, onde = 'item'): Obj {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) throw new FormatoInesperado(rpc, `${onde} não é objeto`);
  return v as Obj;
}
function lista(v: unknown, rpc: string, onde: string): unknown[] {
  if (!Array.isArray(v)) throw new FormatoInesperado(rpc, `${onde}: esperava lista`);
  return v;
}
const str = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const strOuNull = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));
const num = (v: unknown): number => { const n = typeof v === 'number' ? v : Number(v); return Number.isFinite(n) ? n : 0; };
const textos = (v: unknown): string[] => (Array.isArray(v) ? v.map(str).filter(Boolean) : []);

const SITUACOES: readonly SituacaoEstrategia[] = ['solicitada', 'em_analise', 'em_execucao', 'concluida', 'recusada'];
const PRIORIDADES: readonly PrioridadeEstrategia[] = ['baixa', 'media', 'alta', 'urgente'];

function situacao(v: unknown, rpc: string): SituacaoEstrategia {
  if (!(SITUACOES as readonly string[]).includes(String(v))) throw new FormatoInesperado(rpc, `situação desconhecida (${String(v)})`);
  return v as SituacaoEstrategia;
}

export function mapAcesso(d: unknown): AcessoEstrategias {
  const o = obj(d, 'crm_estrategia_acesso', 'acesso');
  return { solicitar: o.solicitar === true, gestor: o.gestor === true, leitor: o.leitor === true };
}

/** Filtros do banco → domínio (descarta chave desconhecida em vez de quebrar a tela). */
export function mapFiltros(v: unknown): FiltrosPublico {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) return {};
  const o = v as Obj;
  const bloco = (b: unknown, chaves: string[]) => {
    if (!b || typeof b !== 'object') return undefined;
    const out: Record<string, string[]> = {};
    for (const k of chaves) { const t = textos((b as Obj)[k]); if (t.length) out[k] = t; }
    return Object.keys(out).length ? out : undefined;
  };
  const f: FiltrosPublico = {};
  if (o.base === 'alunos' || o.base === 'contatos' || o.base === 'compradores') f.base = o.base;
  const al = bloco(o.alunos, ['niveis', 'turmas', 'tiposTurma', 'planos', 'statusAcesso']); if (al) f.alunos = al;
  const co = bloco(o.comprou, ['produtos', 'linhas']); if (co) f.comprou = co;
  const nc = bloco(o.naoComprou, ['produtos', 'linhas']); if (nc) f.naoComprou = nc;
  const ca = bloco(o.catalogacao, ['projetos', 'canais']); if (ca) f.catalogacao = ca;
  const regras = Array.isArray((o.respondi as Obj | undefined)?.regras) ? ((o.respondi as Obj).regras as unknown[]) : [];
  const rs = regras.map((r) => {
    const x = (r ?? {}) as Obj;
    const forms = textos(x.forms);
    return { perguntas: textos(x.perguntas), contem: textos(x.contem), ...(forms.length ? { forms } : {}) };
  }).filter((r) => r.perguntas.length && r.contem.length);
  if (rs.length) f.respondi = { regras: rs };
  if (o.excluir && typeof o.excluir === 'object') {
    const e = o.excluir as Obj;
    f.excluir = { emNegociacao: e.emNegociacao !== false, outraAcao: e.outraAcao !== false };
  }
  return f;
}

function mapPlacar(v: unknown): PlacarAcao | null {
  if (v === null || v === undefined) return null;
  const o = obj(v, 'crm_estrategias', 'placar');
  return { naLista: num(o.naLista), abordadas: num(o.abordadas), emConversa: num(o.emConversa), vendas: num(o.vendas), receita: num(o.receita) };
}

function mapHistorico(v: unknown, rpc: string): HistoricoEstrategia {
  const o = obj(v, rpc, 'histórico');
  return { de: o.de ? situacao(o.de, rpc) : null, para: situacao(o.para, rpc), porNome: strOuNull(o.porNome), nota: strOuNull(o.nota), em: str(o.em) };
}

export function mapEstrategia(v: unknown, rpc = 'crm_estrategias'): Estrategia {
  const o = obj(v, rpc, 'pedido');
  const prio = (PRIORIDADES as readonly string[]).includes(String(o.prioridade)) ? (o.prioridade as PrioridadeEstrategia) : 'media';
  const tipo = o.acaoTipo === 'fila' || o.acaoTipo === 'funil' ? (o.acaoTipo as TipoAcao) : null;
  const e: Estrategia = {
    id: str(o.id), titulo: str(o.titulo), objetivo: str(o.objetivo), publico: str(o.publico), filtros: mapFiltros(o.filtros),
    modelo: strOuNull(o.modelo), linha: strOuNull(o.linha) as ProdutoKey | null, oferta: strOuNull(o.oferta),
    prazo: strOuNull(o.prazo), prioridade: prio, observacoes: str(o.observacoes),
    solicitanteId: str(o.solicitanteId), solicitanteNome: str(o.solicitanteNome) || 'Sem nome',
    situacao: situacao(o.situacao, rpc), motivoRecusa: strOuNull(o.motivoRecusa),
    responsavelId: strOuNull(o.responsavelId), responsavelNome: strOuNull(o.responsavelNome),
    acaoTipo: tipo, filaId: strOuNull(o.filaId), funilId: strOuNull(o.funilId), acaoCriadaEm: strOuNull(o.acaoCriadaEm),
    acaoPessoas: o.acaoPessoas === null || o.acaoPessoas === undefined ? null : num(o.acaoPessoas),
    criadoEm: str(o.criadoEm), atualizadoEm: str(o.atualizadoEm), placar: mapPlacar(o.placar),
  };
  if (o.historico !== undefined) e.historico = lista(o.historico, rpc, 'historico').map((h) => mapHistorico(h, rpc));
  return e;
}

export function mapEstrategias(d: unknown): Estrategia[] {
  return lista(d, 'crm_estrategias', 'lista').map((x) => mapEstrategia(x));
}

export function mapModelos(d: unknown): ModeloPublico[] {
  return lista(d, 'crm_estrategia_modelos', 'lista').map((x) => {
    const o = obj(x, 'crm_estrategia_modelos', 'modelo');
    return { chave: str(o.chave), nome: str(o.nome), descricao: str(o.descricao), filtros: mapFiltros(o.filtros) };
  });
}

export function mapOpcoes(d: unknown): OpcoesFiltro {
  const rpc = 'crm_estrategia_opcoes';
  const o = obj(d, rpc, 'opções');
  const objs = (k: string) => lista(o[k] ?? [], rpc, k).map((x) => obj(x, rpc, k));
  return {
    niveis: textos(o.niveis),
    turmas: objs('turmas').map((t) => ({ codigo: str(t.codigo), tipo: str(t.tipo) })),
    planos: textos(o.planos),
    statusAcesso: textos(o.statusAcesso),
    linhas: objs('linhas').map((l) => ({ chave: str(l.chave) as ProdutoKey, nome: str(l.nome), escada: str(l.escada) })),
    produtos: objs('produtos').map((p) => ({ id: str(p.id), nome: str(p.nome) })),
    projetos: textos(o.projetos),
    canais: textos(o.canais),
    perguntas: objs('perguntas').map((p) => ({ pergunta: str(p.pergunta), formularios: num(p.formularios) })),
  };
}

export function mapPrevia(d: unknown): { ok: boolean; msg?: string; previa?: PreviaPublico } {
  const rpc = 'crm_estrategia_previa';
  const o = obj(d, rpc, 'prévia');
  if (o.ok !== true) return { ok: false, msg: str(o.msg) || 'Não foi possível calcular o público.' };
  const ex = obj(o.excluidos ?? {}, rpc, 'excluidos');
  return {
    ok: true,
    previa: {
      total: num(o.total),
      excluidos: { optOut: num(ex.optOut), jaComprou: num(ex.jaComprou), emNegociacao: num(ex.emNegociacao), outraAcao: num(ex.outraAcao) },
      amostra: lista(o.amostra ?? [], rpc, 'amostra').map((x) => {
        const a = obj(x, rpc, 'amostra');
        return { nome: str(a.nome), email: strOuNull(a.email), nivel: strOuNull(a.nivel), turma: strOuNull(a.turma) };
      }),
    },
  };
}

/** Argumento de crm_estrategia_salvar (filtros limpos: só o que filtra de verdade). */
export function argsSalvar(s: NovaSolicitacao): { p: Record<string, unknown> } {
  return {
    p: {
      ...(s.id ? { id: s.id } : {}),
      titulo: s.titulo.trim(), objetivo: s.objetivo.trim(), publico: s.publico.trim(), filtros: limparFiltros(s.filtros),
      modelo: s.modelo, linha: s.linha, oferta: s.oferta.trim(), prazo: s.prazo || null, prioridade: s.prioridade,
      observacoes: s.observacoes.trim(),
    },
  };
}
