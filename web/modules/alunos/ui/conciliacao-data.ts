'use client';

// TODAS as chamadas de programa, selo e conciliação da base de alunos moram aqui: se a assinatura final de uma
// RPC mudar, o ajuste é neste arquivo só. Leitura devolve dado OU erro, nunca [] no lugar de erro (a tela
// mostra o erro discreto e segue). Nada é guardado em cache de módulo, localStorage ou URL.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { bigintNum, normalizarItens, type DecisaoConciliacao, type ItemConciliacao } from '../domain/conciliacao';
import { normalizarProgramas, type ProgramaAluno, type SeloNivel } from '../domain/programa-selo';

const db = () => createBrowserSupabase();

export type Resultado<T> = { ok: true; data: T } | { ok: false; erro: string };

interface ErroRpc { code?: string; message?: string }

/**
 * Mensagem para a equipe, por sqlstate. Só 23514 (vínculo de sócio inválido) usa o texto do banco, que já é
 * escrito para gente; os demais raise trazem nome de função e vão para `porCodigo` (texto por chamada).
 */
function mensagemErro(e: ErroRpc, padrao: string, porCodigo: Record<string, string> = {}): string {
  if (e.code === '42501') return 'Sem permissão para esta ação.';
  if (e.code === '23514' && e.message) return e.message;
  if (e.code && porCodigo[e.code]) return porCodigo[e.code];
  if (e.code === 'PGRST202' || e.code === '42883') return 'Recurso ainda não disponível no banco.';
  return padrao;
}

/**
 * RPC que devolve conjunto, paginada (o PostgREST corta em 1.000 linhas). Ordem fixa pela chave, senão a
 * página 2 pode repetir ou pular linhas. ATENÇÃO: cada página reexecuta a função no banco.
 */
async function rpcPaginada(fn: string, args: Record<string, unknown>, ordem: string[], rotulo: string): Promise<Resultado<unknown[]>> {
  const PAGE = 1000;
  const out: unknown[] = [];
  for (let from = 0; ; from += PAGE) {
    let q = db().rpc(fn, args);
    for (const c of ordem) q = q.order(c, { ascending: true, nullsFirst: true });
    const { data, error } = await q.range(from, from + PAGE - 1);
    if (error) {
      logQueryError(rotulo, error);
      return { ok: false, erro: mensagemErro(error, 'Não foi possível carregar.') };
    }
    const linhas = (data as unknown[]) ?? [];
    out.push(...linhas);
    if (linhas.length < PAGE) return { ok: true, data: out };
  }
}

// ── Programa e selo (20261002d/e) — 1× por abertura da lista ──

export async function loadProgramasSafe(): Promise<Resultado<ProgramaAluno[]>> {
  const r = await rpcPaginada('fn_aluno_programas_safe', {}, ['aluno_id'], 'loadProgramasSafe');
  return r.ok ? { ok: true, data: normalizarProgramas(r.data) } : r;
}

export async function loadNivelSelo(): Promise<Resultado<SeloNivel[]>> {
  const r = await rpcPaginada('fn_aluno_nivel_selo', {}, ['aluno_id'], 'loadNivelSelo');
  return r.ok ? { ok: true, data: r.data as SeloNivel[] } : r;
}

// ── Conciliação (20261003e/f) ──

/**
 * A base inteira COM conferidos, 1× por abertura da página (segundo plano); a ficha, o contador, o resumo e o
 * filtro "Mostrar conferidos" saem desse mesmo resultado. fn_aluno_conciliacao_lista devolve UM jsonb (array com as
 * colunas de fn_aluno_conciliacao): 1 execução no banco, sem o teto de 1.000 linhas do PostgREST, sem paginar.
 */
export async function loadConciliacao(incluirConferidos = true): Promise<Resultado<ItemConciliacao[]>> {
  const { data, error } = await db().rpc('fn_aluno_conciliacao_lista', { p_incluir_conferidos: incluirConferidos });
  if (error) {
    logQueryError('loadConciliacao', error);
    return { ok: false, erro: mensagemErro(error, 'Não foi possível carregar a conciliação.') };
  }
  if (!Array.isArray(data)) {
    logQueryError('loadConciliacao', { message: `retorno não é array (${data === null ? 'null' : typeof data})` });
    return { ok: false, erro: 'A conciliação voltou num formato inesperado. Tente de novo.' };
  }
  return { ok: true, data: normalizarItens(data) };
}

/** Linha de fn_aluno_conciliacao_ref. Placa e SIP vêm sem valor. */
export interface RefConciliacao {
  fonte: string | null;
  nome: string | null;
  email: string | null;
  produto: string | null;
  /** timestamptz em ISO. */
  data: string | null;
  /** numeric: número (ou texto, conforme o servidor serializa). */
  valor: number | null;
}

/**
 * Dados de quem está fora da base (comprador, usuário do SIP, placa) — 1× por clique, sem cache.
 * Item fechado ou de outro tipo devolve 0 linhas (não é erro).
 */
export async function loadConciliacaoRef(item: string): Promise<Resultado<RefConciliacao[]>> {
  const { data, error } = await db().rpc('fn_aluno_conciliacao_ref', { p_item: item });
  if (error) {
    logQueryError('loadConciliacaoRef', error);
    return { ok: false, erro: mensagemErro(error, 'Não foi possível carregar os dados.') };
  }
  const linhas = Array.isArray(data) ? data : data ? [data] : [];
  const txt = (v: unknown) => (typeof v === 'string' && v ? v : null);
  const num = (v: unknown) => {
    const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() ? Number(v) : NaN;
    return Number.isFinite(n) ? n : null;
  };
  return {
    ok: true,
    data: linhas
      .filter((l): l is Record<string, unknown> => !!l && typeof l === 'object')
      .map((l) => ({ fonte: txt(l.fonte), nome: txt(l.nome), email: txt(l.email), produto: txt(l.produto), data: txt(l.data), valor: num(l.valor) })),
  };
}

/** Marca o item. Devolve o id da decisão (bigint → number), usado no "Desfazer". */
export async function marcarConciliacao(item: string, decisao: DecisaoConciliacao, obs: string): Promise<Resultado<number | null>> {
  const { data, error } = await db().rpc('fn_aluno_conciliacao_marcar', { p_item: item, p_decisao: decisao, p_obs: obs.trim() || null });
  if (error) {
    logQueryError('marcarConciliacao', error);
    return {
      ok: false,
      erro: mensagemErro(error, 'Não foi possível marcar o item.', {
        '22023': 'Não foi possível marcar: o item já foi decidido ou resolvido, ou a decisão não vale para este tipo. Recarregue a conciliação.',
        '23505': 'Outra pessoa acabou de decidir este item. Recarregue a conciliação.',
      }),
    };
  }
  return { ok: true, data: bigintNum(data) };
}

export async function desmarcarConciliacao(id: number): Promise<Resultado<null>> {
  const { error } = await db().rpc('fn_aluno_conciliacao_desmarcar', { p_id: id });
  if (error) {
    logQueryError('desmarcarConciliacao', error);
    return { ok: false, erro: mensagemErro(error, 'Não foi possível desfazer.', { P0002: 'Esta marcação já foi desfeita ou não existe mais.' }) };
  }
  return { ok: true, data: null };
}

/** p_titular nulo = a pessoa passa a ser titular; senão vira sócia de p_titular. O banco valida. */
export async function definirTitular(socioId: string, titularId: string | null): Promise<Resultado<null>> {
  const { error } = await db().rpc('fn_aluno_definir_titular', { p_socio: socioId, p_titular: titularId });
  if (error) {
    logQueryError('definirTitular', error);
    return {
      ok: false,
      erro: mensagemErro(error, 'Não foi possível salvar o vínculo.', {
        '22023': 'Aluno não informado.',
        P0002: 'Aluno ou titular inexistente ou cancelado.',
      }),
    };
  }
  return { ok: true, data: null };
}
