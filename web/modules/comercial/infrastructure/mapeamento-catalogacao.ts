// Mapeamento PURO das RPCs da catalogação de origem (migration 20261007141044): crm_catalogo, crm_contato_origem e os
// argumentos de crm_catalogo_regra_salvar. Formato fora do contrato vira exceção (nunca painel zerado).
import {
  ORDEM_CAMPOS,
  type CampoRegra, type DetalheOrigem, type MotivoProjeto, type OperadorRegra, type OrigemDetalhada, type PainelCatalogo,
  type RegraCatalogo,
} from '../domain/catalogacao';
import { FormatoInesperado, canalEntrada } from './mapeamento-supabase';

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

const OPERADORES: readonly OperadorRegra[] = ['igual', 'comeca', 'contem'];
const MOTIVOS: readonly MotivoProjeto[] = ['regra', 'utm', 'sck', 'funil', 'manual', 'regra_sem_projeto', 'sem_regra', 'sem_dado'];

function campo(v: unknown, rpc: string): CampoRegra {
  if (!(ORDEM_CAMPOS as readonly string[]).includes(String(v))) throw new FormatoInesperado(rpc, `campo de regra desconhecido (${String(v)})`);
  return v as CampoRegra;
}
function operador(v: unknown, rpc: string): OperadorRegra {
  if (!(OPERADORES as readonly string[]).includes(String(v))) throw new FormatoInesperado(rpc, `operador desconhecido (${String(v)})`);
  return v as OperadorRegra;
}

function mapRegra(x: unknown): RegraCatalogo {
  const rpc = 'crm_catalogo';
  const o = obj(x, rpc, 'regra');
  return {
    id: num(o.id), tipo: o.tipo === 'mql' ? 'mql' : 'projeto', campo: campo(o.campo, rpc), operador: operador(o.operador, rpc), padrao: str(o.padrao),
    projeto: strOuNull(o.projeto), projetoNome: strOuNull(o.projetoNome), valeDe: strOuNull(o.valeDe), valeAte: strOuNull(o.valeAte),
    prioridade: num(o.prioridade), ativo: o.ativo === true, nota: strOuNull(o.nota), contatos: num(o.contatos),
  };
}

export function mapPainelCatalogo(d: unknown): PainelCatalogo {
  const rpc = 'crm_catalogo';
  const o = obj(d, rpc);
  const r = obj(o.resumo, rpc, 'resumo');
  const motivos = r.motivos && typeof r.motivos === 'object' ? (r.motivos as Obj) : {};
  return {
    podeEditar: o.podeEditar === true,
    podeClassificar: o.podeClassificar === true || o.podeEditar === true,
    regras: lista(o.regras, rpc, 'regras').map(mapRegra),
    listasAc: lista(o.listasAc, rpc, 'listasAc').map((x) => { const l = obj(x, rpc, 'lista'); return { id: str(l.id), nome: str(l.nome) }; }),
    projetos: lista(o.projetos, rpc, 'projetos').map((x) => {
      const p = obj(x, rpc, 'projeto');
      return { chave: str(p.chave), nome: strOuNull(p.nome), contatos: num(p.contatos) };
    }),
    resumo: {
      total: num(r.total), comProjeto: num(r.comProjeto), mql: num(r.mql), produtoSemProjeto: num(r.produtoSemProjeto), semNada: num(r.semNada),
      motivos: { regra_sem_projeto: num(motivos.regra_sem_projeto), sem_regra: num(motivos.sem_regra), sem_dado: num(motivos.sem_dado) },
      porCanal: (Array.isArray(r.porCanal) ? r.porCanal : []).map((x) => {
        const c = obj(x, rpc, 'canal');
        return { canal: canalEntrada(c.canal), total: num(c.total), comProjeto: num(c.comProjeto) };
      }),
      semProjetoPorLinha: (Array.isArray(r.semProjetoPorLinha) ? r.semProjetoPorLinha : []).map((x) => {
        const l = obj(x, rpc, 'linha');
        return { linha: str(l.linha), total: num(l.total) };
      }),
    },
    pendencias: lista(o.pendencias, rpc, 'pendencias').map((x) => {
      const p = obj(x, rpc, 'pendência');
      return { campo: campo(p.campo, rpc), valor: str(p.valor), nome: strOuNull(p.nome), contatos: num(p.contatos) };
    }),
  };
}

/** crm_contato_origem: null = contato sem origem registrada (anterior à catalogação). */
export function mapOrigemDetalhada(d: unknown): OrigemDetalhada | null {
  const rpc = 'crm_contato_origem';
  if (d === null || d === undefined) return null;
  const o = obj(d, rpc);
  const motivo = (MOTIVOS as readonly string[]).includes(String(o.motivo)) ? (o.motivo as MotivoProjeto) : 'sem_dado';
  const g = o.regra && typeof o.regra === 'object' ? (o.regra as Obj) : null;
  return {
    canal: canalEntrada(o.canal), entrouEm: str(o.entrouEm), projeto: strOuNull(o.projeto), projetoNome: strOuNull(o.projetoNome),
    mqlDesde: strOuNull(o.mqlDesde),
    linha: strOuNull(o.linha), motivo, manual: o.manual === true, podeDefinir: o.podeDefinir === true,
    detalhe: (o.detalhe && typeof o.detalhe === 'object' && !Array.isArray(o.detalhe) ? o.detalhe : {}) as DetalheOrigem,
    mqlProjeto: strOuNull(o.mqlProjeto), mqlProjetoNome: strOuNull(o.mqlProjetoNome),
    regra: g ? { id: num(g.id), campo: campo(g.campo, rpc), operador: operador(g.operador, rpc), padrao: str(g.padrao) } : null,
  };
}

/** Argumento de crm_catalogo_regra_salvar (p jsonb). */
export function argsRegra(r: RegraCatalogo): { p: Record<string, unknown> } {
  return {
    p: {
      id: r.id, tipo: r.tipo ?? 'projeto', campo: r.campo, operador: r.operador, padrao: r.padrao, projeto: r.projeto, valeDe: r.valeDe, valeAte: r.valeAte,
      prioridade: r.prioridade, ativo: r.ativo, nota: r.nota,
    },
  };
}
