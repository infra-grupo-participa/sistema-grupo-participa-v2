// Mapeamento PURO da Ativação (migration 20261007135415): jsonb de `crm_ativacao_painel` → domínio, e edição → payload de
// `crm_ativacao_salvar`. Formato fora do contrato é erro (nunca painel zerado).
import type { CargaAtivacao, EdicaoAtivacao, PainelAtivacao, ProjetoAtivacao } from '../domain/ativacao';
import type { ProdutoKey } from '../domain/types';
import { FormatoInesperado } from './mapeamento-supabase';

type Obj = Record<string, unknown>;
const RPC = 'crm_ativacao_painel';

const obj = (v: unknown, onde: string): Obj => {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) throw new FormatoInesperado(RPC, `${onde} não é objeto`);
  return v as Obj;
};
const lista = (v: unknown, onde: string): unknown[] => {
  if (!Array.isArray(v)) throw new FormatoInesperado(RPC, `${onde} não é lista`);
  return v;
};
const str = (v: unknown) => (v === null || v === undefined ? '' : String(v));
const strOuNull = (v: unknown) => (v === null || v === undefined || v === '' ? null : String(v));
const num = (v: unknown) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x) => x !== null && x !== undefined).map(String) : []);

function mapProjeto(x: unknown): ProjetoAtivacao {
  const o = obj(x, 'projeto');
  if (!o.projeto || !o.funilId) throw new FormatoInesperado(RPC, 'projeto sem chave ou funil');
  const porEtapa: Record<string, number> = {};
  if (o.porEtapa && typeof o.porEtapa === 'object' && !Array.isArray(o.porEtapa)) {
    for (const [k, v] of Object.entries(o.porEtapa as Obj)) porEtapa[k] = num(v);
  }
  return {
    projeto: str(o.projeto), nome: str(o.nome), funilId: str(o.funilId), produto: str(o.produto) as ProdutoKey,
    eventoInicio: strOuNull(o.eventoInicio), eventoFim: strOuNull(o.eventoFim), eventoHora: strOuNull(o.eventoHora),
    carrinhoFim: strOuNull(o.carrinhoFim), fimAtivacao: strOuNull(o.fimAtivacao), datasDoMarketing: o.datasDoMarketing === true,
    hotmartOferta: strs(o.hotmartOferta), ligado: o.ligado !== false, encerradoEm: strOuNull(o.encerradoEm),
    filaId: strOuNull(o.filaId), porEtapa, entradasHoje: num(o.entradasHoje), mqls: num(o.mqls), mensageriaHoje: num(o.mensageriaHoje),
  };
}

function mapCarga(x: unknown): CargaAtivacao {
  const o = obj(x, 'carga');
  return { vendedorId: str(o.vendedorId), novasHoje: num(o.novasHoje), toquesHoje: num(o.toquesHoje) };
}

export function mapPainelAtivacao(d: unknown): PainelAtivacao {
  const o = obj(d, 'painel');
  return {
    projetos: lista(o.projetos, 'projetos').map(mapProjeto),
    carga: lista(o.carga, 'carga').map(mapCarga),
    totalNovasHoje: num(o.totalNovasHoje),
    ligada: o.ligada === true,
    semAtivacao: strs(o.semAtivacao),
  };
}

export function argsSalvarAtivacao(e: EdicaoAtivacao): { p: Obj } {
  return {
    p: {
      projeto: e.projeto, eventoInicio: e.eventoInicio ?? '', eventoFim: e.eventoFim ?? '', eventoHora: e.eventoHora ?? '',
      carrinhoFim: e.carrinhoFim ?? '',
      hotmartOferta: e.hotmartOferta, ligado: e.ligado,
    },
  };
}
