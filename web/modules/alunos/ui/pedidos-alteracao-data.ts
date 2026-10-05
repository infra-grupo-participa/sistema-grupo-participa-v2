'use client';

// Adapter Supabase dos Pedidos de alteração: único lugar que chama as funções pa_* do banco.
// As tabelas pa_* são fechadas; a trava (quem pede, quem aprova, máscara de documento) mora em cada função.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { AlunoResumo, PapelPedidos, PedidoLinha, SocioNovo, TipoPedido } from '../domain/pedidos-alteracao';

const db = () => createBrowserSupabase();

export interface Resultado { ok: boolean; msg: string; numero?: number; conflito?: boolean; agora?: string | null; ra_caso_id?: string | null }
const ERRO_REDE: Resultado = { ok: false, msg: 'Não foi possível salvar (erro de rede). Tente de novo.' };

export async function meuPapelPedidos(): Promise<PapelPedidos | null> {
  const { data, error } = await db().rpc('pa_meu_papel');
  logQueryError('pa_meu_papel', error);
  return error ? null : (data as PapelPedidos);
}

export interface FiltrosBusca { instrucoes?: string[]; espacos?: string[]; papel?: 'titular' | 'socio' | null }

export async function buscarAlunos(termo: string, f: FiltrosBusca = {}): Promise<AlunoResumo[]> {
  const { data, error } = await db().rpc('pa_buscar_alunos', {
    p_termo: termo,
    p_instrucoes: f.instrucoes?.length ? f.instrucoes : null,
    p_espacos: f.espacos?.length ? f.espacos : null,
    p_papel: f.papel ?? null,
    p_limite: 15,
  });
  logQueryError('pa_buscar_alunos', error);
  return (data as AlunoResumo[] | null) ?? [];
}

export async function sociosDoTitular(titularId: string): Promise<AlunoResumo[]> {
  const { data, error } = await db().rpc('pa_socios_do_titular', { p_titular: titularId });
  logQueryError('pa_socios_do_titular', error);
  return (data as AlunoResumo[] | null) ?? [];
}

export async function valorAtual(alunoId: string, campo: string): Promise<{ valor: unknown; exibicao: string | null } | null> {
  const { data, error } = await db().rpc('pa_valor_atual', { p_aluno: alunoId, p_campo: campo });
  logQueryError('pa_valor_atual', error);
  return error ? null : (data as { valor: unknown; exibicao: string | null } | null);
}

export async function turmasPedido(): Promise<{ id: number; codigo: string }[]> {
  const { data, error } = await db().rpc('pa_turmas');
  logQueryError('pa_turmas', error);
  return (data as { id: number; codigo: string }[] | null) ?? [];
}

export interface NovoPedido {
  tipo: TipoPedido;
  aluno_id: string;
  campo?: string;
  valor_novo?: unknown;
  socio_sai_id?: string;
  socio_entra_id?: string;
  socio_entra_novo?: SocioNovo;
  descricao?: string;
  motivo: string;
  evidencia?: string;
}

export async function criarPedido(p: NovoPedido): Promise<Resultado> {
  const { data, error } = await db().rpc('pa_criar', { p });
  logQueryError('pa_criar', error);
  return error ? ERRO_REDE : (data as Resultado);
}

export async function meusPedidos(): Promise<PedidoLinha[]> {
  const { data, error } = await db().rpc('pa_meus_pedidos');
  logQueryError('pa_meus_pedidos', error);
  if (error) throw new Error('Não foi possível carregar seus pedidos.');
  return (data as PedidoLinha[] | null) ?? [];
}

export async function filaPedidos(todos: boolean): Promise<PedidoLinha[]> {
  const { data, error } = await db().rpc('pa_fila', { p_todos: todos });
  logQueryError('pa_fila', error);
  if (error) throw new Error('Não foi possível carregar os pedidos.');
  return (data as PedidoLinha[] | null) ?? [];
}

export async function decidirPedido(id: number, decisao: 'aprovar' | 'recusar', opts: {
  motivoRecusa?: string; valorAjustado?: unknown; confirmarConflito?: boolean;
} = {}): Promise<Resultado> {
  const { data, error } = await db().rpc('pa_decidir', {
    p_pedido: id,
    p_decisao: decisao,
    p_motivo_recusa: opts.motivoRecusa ?? null,
    p_valor_ajustado: opts.valorAjustado === undefined ? null : opts.valorAjustado,
    p_confirmar_conflito: opts.confirmarConflito ?? false,
  });
  logQueryError('pa_decidir', error);
  return error ? ERRO_REDE : (data as Resultado);
}

export async function marcarAplicado(id: number, obs: string): Promise<Resultado> {
  const { data, error } = await db().rpc('pa_marcar_aplicado', { p_pedido: id, p_obs: obs || null });
  logQueryError('pa_marcar_aplicado', error);
  return error ? ERRO_REDE : (data as Resultado);
}
