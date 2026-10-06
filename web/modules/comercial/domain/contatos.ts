// Regras puras da base de contatos: busca, duplicidade e a lista paginada com filtros, ordem e números do topo.
// O banco faz o mesmo em `crm_contatos_pagina`/`crm_contatos_resumo` (migration 20261006m); esta versão serve à
// demonstração e ao caminho antigo (RPC nova ainda não aplicada). Sem React, sem Supabase.
import { chaveTelefone } from './regras';
import type { Contato, Negocio, PerfilProfissional, PontoJornada, ProdutoKey } from './types';

export type OrdemContatos = 'criado' | 'nome' | 'dono' | 'negocios' | 'lancamentos' | 'ultima';

export interface FiltroContatos {
  /** Nome, e-mail ou telefone (a partir de 3 letras no servidor). */
  busca?: string;
  /** 'todos' (padrão) | 'sem_dono' | id do vendedor. */
  dono?: string;
  perfil?: PerfilProfissional | 'sem' | 'todos';
  /** Sigla da UF ou 'todas'. */
  uf?: string;
  /** Tem qualquer uma destas tags. */
  tags?: string[];
  optOut?: boolean;
  soAlunos?: boolean;
  ordem?: OrdemContatos;
  dir?: 'asc' | 'desc';
  limite?: number;
  offset?: number;
}

/** Negócio aberto resumido para a linha da lista. */
export interface NegocioAbertoLinha {
  id: string;
  produto: ProdutoKey;
  etapaNome: string;
}

/** Contato da lista paginada: o contato + o que a linha mostra (calculado em lote no banco). */
export interface ContatoLinha extends Contato {
  lancamentos: number;
  ultimaInteracaoEm: string | null;
  abertos: NegocioAbertoLinha[];
}

export interface PaginaContatos {
  itens: ContatoLinha[];
  /** Quantos passam nos filtros (todas as páginas). */
  total: number;
}

export interface ResumoContatos {
  total: number;
  semDono: number;
  optOut: number;
  alunos: number;
  /** Opções dos filtros (UF e tags existentes na lista visível). */
  ufs: string[];
  tags: string[];
}

export const LIMITE_PAGINA_CONTATOS = 50;
export const LIMITE_MAXIMO_PAGINA_CONTATOS = 200;

/**
 * Possíveis duplicados: contatos com a mesma chave de telefone (DDD + últimos 8 dígitos, `chaveTelefone`)
 * (mesma pessoa que comprou com outro e-mail, com/sem DDI ou com/sem o 9). Devolve id → ids dos outros.
 */
export function mapaDuplicados(contatos: Pick<Contato, 'id' | 'telefone'>[]): Map<string, string[]> {
  const porChave = new Map<string, string[]>();
  for (const c of contatos) {
    const k = chaveTelefone(c.telefone);
    if (!k) continue;
    porChave.set(k, [...(porChave.get(k) ?? []), c.id]);
  }
  const mapa = new Map<string, string[]>();
  for (const ids of porChave.values()) {
    if (ids.length < 2) continue;
    for (const id of ids) mapa.set(id, ids.filter((x) => x !== id));
  }
  return mapa;
}

/** Busca por nome, e-mail ou telefone (aceita qualquer formatação e compara pela chave DDD + últimos 8 dígitos). */
export function casaBusca(c: Pick<Contato, 'nome' | 'email' | 'telefone'>, termo: string): boolean {
  const q = termo.trim().toLowerCase();
  if (!q) return true;
  const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '');
  if (sem(`${c.nome} ${c.email ?? ''}`.toLowerCase()).includes(sem(q))) return true;
  const digitos = q.replace(/\D/g, '');
  if (digitos.length < 4) return false;
  const tel = String(c.telefone ?? '').replace(/\D/g, '');
  if (tel.includes(digitos)) return true;
  const k = chaveTelefone(digitos);
  return !!k && k === chaveTelefone(tel);
}

const max = (a: string | null, b: string | null) => (!a ? b : !b ? a : a > b ? a : b);

/**
 * Monta as linhas (abertos, lançamentos, última interação) a partir dos negócios e, se houver, dos pontos de jornada
 * já carregados. Mesmas regras da ficha: lançamentos = chaves distintas; última = o ponto ou a interação mais recente.
 */
export function linhasContatos(
  contatos: Contato[],
  negocios: Pick<Negocio, 'id' | 'contatoId' | 'status' | 'produto' | 'etapaNome' | 'criadoEm' | 'ultimaInteracaoEm'>[],
  pontos: Pick<PontoJornada, 'contatoId' | 'em' | 'lancamento'>[] = [],
): ContatoLinha[] {
  const abertos = new Map<string, NegocioAbertoLinha[]>();
  const ultima = new Map<string, string | null>();
  const lancs = new Map<string, Set<string>>();
  const ordenados = [...negocios].sort((a, b) => b.criadoEm.localeCompare(a.criadoEm) || a.id.localeCompare(b.id));
  for (const n of ordenados) {
    if (n.status === 'aberto') {
      abertos.set(n.contatoId, [...(abertos.get(n.contatoId) ?? []), { id: n.id, produto: n.produto, etapaNome: n.etapaNome }]);
    }
    ultima.set(n.contatoId, max(ultima.get(n.contatoId) ?? null, n.ultimaInteracaoEm));
  }
  for (const p of pontos) {
    ultima.set(p.contatoId, max(ultima.get(p.contatoId) ?? null, p.em));
    if (p.lancamento) lancs.set(p.contatoId, (lancs.get(p.contatoId) ?? new Set()).add(p.lancamento));
  }
  return contatos.map((c) => ({
    ...c,
    abertos: abertos.get(c.id) ?? [],
    lancamentos: lancs.get(c.id)?.size ?? 0,
    ultimaInteracaoEm: ultima.get(c.id) ?? null,
  }));
}

/** Passa nos filtros da tela (mesmos critérios de `crm_contatos_pagina`). */
export function passaFiltro(c: Contato, f: FiltroContatos): boolean {
  const dono = f.dono ?? 'todos';
  if (dono === 'sem_dono' ? !!c.donoId : dono !== 'todos' && c.donoId !== dono) return false;
  const perfil = f.perfil ?? 'todos';
  if (perfil === 'sem' ? !!c.perfil : perfil !== 'todos' && c.perfil !== perfil) return false;
  if (f.uf && f.uf !== 'todas' && c.uf !== f.uf) return false;
  if (f.tags?.length && !f.tags.some((t) => c.tags.includes(t))) return false;
  if (f.optOut && !c.optOut) return false;
  if (f.soAlunos && !c.ehAluno) return false;
  if (f.busca && !casaBusca(c, f.busca)) return false;
  return true;
}

/**
 * Filtra, ordena e pagina (demonstração e caminho antigo). Empate: criação → id; demais → nome, id.
 * Última interação vazia vai para o fim nas duas direções (igual ao banco).
 */
export function paginarContatos(
  linhas: ContatoLinha[], f: FiltroContatos, nomeDe: (id: string | null) => string = () => '',
): PaginaContatos {
  const ordem = f.ordem ?? 'criado';
  const sinal = (f.dir ?? 'desc') === 'asc' ? 1 : -1;
  const limite = Math.min(Math.max(f.limite ?? LIMITE_PAGINA_CONTATOS, 1), LIMITE_MAXIMO_PAGINA_CONTATOS);
  const offset = Math.max(f.offset ?? 0, 0);
  const col = new Intl.Collator('pt-BR', { sensitivity: 'base' });
  const nome = (a: ContatoLinha, b: ContatoLinha) => col.compare(a.nome, b.nome) || a.id.localeCompare(b.id);
  const cmp = (a: ContatoLinha, b: ContatoLinha): number => {
    switch (ordem) {
      case 'criado': return sinal * a.criadoEm.localeCompare(b.criadoEm) || a.id.localeCompare(b.id);
      case 'nome': return sinal * col.compare(a.nome, b.nome) || a.id.localeCompare(b.id);
      case 'dono': return sinal * col.compare(a.donoId ? nomeDe(a.donoId) : '', b.donoId ? nomeDe(b.donoId) : '') || nome(a, b);
      case 'negocios': return sinal * (a.abertos.length - b.abertos.length) || nome(a, b);
      case 'lancamentos': return sinal * (a.lancamentos - b.lancamentos) || nome(a, b);
      case 'ultima': {
        if (!a.ultimaInteracaoEm !== !b.ultimaInteracaoEm) return a.ultimaInteracaoEm ? -1 : 1;
        return sinal * (a.ultimaInteracaoEm ?? '').localeCompare(b.ultimaInteracaoEm ?? '') || nome(a, b);
      }
    }
  };
  const filtrados = linhas.filter((c) => passaFiltro(c, f)).sort(cmp);
  return { itens: filtrados.slice(offset, offset + limite), total: filtrados.length };
}

/** Números do topo e opções dos filtros (mesmos de `crm_contatos_resumo`). */
export function resumirContatos(contatos: Pick<Contato, 'donoId' | 'optOut' | 'ehAluno' | 'uf' | 'tags'>[]): ResumoContatos {
  const col = new Intl.Collator('pt-BR');
  return {
    total: contatos.length,
    semDono: contatos.filter((c) => !c.donoId).length,
    optOut: contatos.filter((c) => c.optOut).length,
    alunos: contatos.filter((c) => c.ehAluno).length,
    ufs: [...new Set(contatos.map((c) => c.uf).filter((x): x is string => !!x))].sort(),
    tags: [...new Set(contatos.flatMap((c) => c.tags).filter((t) => !!t))].sort(col.compare),
  };
}

/** Ids únicos, sem vazios, na ordem em que aparecem (para pedir contatos por id). */
export function idsUnicos(ids: (string | null | undefined)[]): string[] {
  return [...new Set(ids.filter((x): x is string => !!x))];
}
