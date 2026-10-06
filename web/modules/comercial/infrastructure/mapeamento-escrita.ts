// Mapeamento PURO das RPCs de ESCRITA `public.crm_*` (migration 20261005t, F2): argumentos do port → parâmetros
// da RPC, e o jsonb `{ok, msg?, …ids}` → `Resultado`. Sem Supabase, sem React.
// Regra violada volta como `{ok:false, msg}` (mesmas mensagens do mock); erro de transporte/banco vira `ok:false`
// com mensagem clara (a tela mostra o toast), nunca exceção solta nem sucesso falso.
import type { NovaAtividade, Resultado } from '../application/ports';
import type {
  CampoKey, Dashboard, Funil, MotivoPerda, MotivoPerdaConfig, OfertaHotmart, PainelPessoa, PreferenciasNotificacao,
  ProdutoHotmart, ProdutoKey, TipoProjeto,
} from '../domain/types';
import { FormatoInesperado, type ErroRpc } from './mapeamento-supabase';

type Obj = Record<string, unknown>;

/** `{ok, msg?}` da RPC → `Resultado`. Formato fora do contrato é erro (nunca "ok" presumido). */
export function mapResultado(rpc: string, d: unknown): Resultado {
  if (d === null || typeof d !== 'object' || Array.isArray(d)) throw new FormatoInesperado(rpc, 'resultado não é objeto');
  const o = d as Obj;
  if (typeof o.ok !== 'boolean') throw new FormatoInesperado(rpc, 'resultado sem "ok"');
  const r: Resultado = { ok: o.ok };
  if (typeof o.msg === 'string' && o.msg) r.msg = o.msg;
  return r;
}

/** Resultado + um id devolvido pela RPC (ex.: funilId). Id só vale com ok=true. */
export function mapResultadoComId<K extends string>(rpc: string, d: unknown, chave: K): Resultado & Partial<Record<K, string>> {
  const r = mapResultado(rpc, d) as Resultado & Partial<Record<K, string>>;
  const v = (d as Obj)[chave];
  if (r.ok && typeof v === 'string' && v) (r as Record<string, unknown>)[chave] = v;
  return r;
}

/** criarNegocio: negocioId + donoId (null = ficou sem dono: ninguém ativo na distribuição). */
export function mapResultadoNegocio(d: unknown): Resultado & { negocioId?: string; donoId?: string | null } {
  const r: Resultado & { negocioId?: string; donoId?: string | null } = mapResultadoComId('crm_criar_negocio', d, 'negocioId');
  if (r.ok) {
    const dono = (d as Obj).donoId;
    r.donoId = typeof dono === 'string' && dono ? dono : null;
  }
  return r;
}

/** criarProjeto: lista de funis criados. */
export function mapResultadoProjeto(d: unknown): Resultado & { funilIds?: string[] } {
  const r: Resultado & { funilIds?: string[] } = mapResultado('crm_criar_projeto', d);
  const ids = (d as Obj).funilIds;
  if (r.ok && Array.isArray(ids)) r.funilIds = ids.filter((x): x is string => typeof x === 'string');
  return r;
}

/** Erro de chamada (rede, função ausente, permissão) → mensagem para a tela. */
export function mensagemErroEscrita(rpc: string, e: ErroRpc): string {
  if (e.code === '42501') return e.message || 'Sem acesso ao Comercial.';
  if (e.code === 'PGRST202' || e.code === '42883') {
    return `O banco ainda não tem a função ${rpc} (migration da Fase 2 do CRM não aplicada).`;
  }
  return `Não foi possível salvar no banco (${rpc})${e.message ? `: ${e.message}` : ''}.`;
}

/** Método do port sem tabela no banco ainda: resposta honesta, sem fingir que gravou. */
export function semTabela(oQue: string, fase: string): Resultado {
  return { ok: false, msg: `${oQue} ainda não está no banco (entra na ${fase} do CRM).` };
}

// ── Argumentos de cada RPC (nomes p_* = assinatura da migration 20261005t) ──

export const argsEscrita = {
  moverEtapa: (negocioId: string, etapaId: string) => ({ p_negocio: negocioId, p_etapa: etapaId }),
  salvarCampos: (negocioId: string, campos: Partial<Record<CampoKey, string>>) => ({ p_negocio: negocioId, p_campos: campos }),
  marcarPerdido: (negocioId: string, motivo: MotivoPerda, nota: string) => ({ p_negocio: negocioId, p_motivo: motivo, p_nota: nota }),
  transferirDono: (negocioId: string, novoDonoId: string, motivo: string) => ({ p_negocio: negocioId, p_dono: novoDonoId, p_motivo: motivo }),
  criarNegocio: (contatoId: string, funilId: string, campanhaId?: string | null) => ({ p_pessoa: contatoId, p_funil: funilId, p_campanha: campanhaId ?? null }),
  atribuirContato: (contatoId: string, donoId: string, motivo: string) => ({ p_pessoa: contatoId, p_dono: donoId, p_motivo: motivo }),
  criarAtividade: (a: NovaAtividade) => ({
    p_negocio: a.negocioId ?? null, p_pessoa: a.contatoId, p_tipo: a.tipo, p_titulo: a.titulo, p_vence_em: a.venceEm,
  }),
  concluirAtividade: (atividadeId: string, resultado: string) => ({ p_atividade: atividadeId, p_resultado: resultado }),
  adicionarNota: (contatoId: string, negocioId: string | null, texto: string) => ({ p_pessoa: contatoId, p_negocio: negocioId ?? null, p_texto: texto }),
  salvarFunil: (f: Funil) => ({ p_funil: f }),
  arquivarFunil: (funilId: string) => ({ p_funil: funilId }),
  criarAgrupador: (nome: string, produto: ProdutoKey | null) => ({ p_nome: nome, p_linha: produto ?? null }),
  criarProjeto: (tipo: TipoProjeto, nome: string, agrupadorId: string, produto: ProdutoKey) => ({
    p_tipo: tipo, p_nome: nome, p_agrupador: agrupadorId, p_linha: produto,
  }),
  salvarMotivoPerda: (m: MotivoPerdaConfig) => ({ p_motivo: m }),
  salvarDistribuicao: (percentuais: Record<string, { percentual: number; ativo: boolean }>) => ({ p_percentuais: percentuais }),
  vincularProduto: (p: Pick<ProdutoHotmart, 'produtoId' | 'noComercial' | 'nomeComercial' | 'produtoKey' | 'agrupadorId' | 'escada'>) => ({ p_produto: p }),
  salvarOferta: (o: Pick<OfertaHotmart, 'codigo' | 'vigente' | 'condicao' | 'validaAte' | 'uso'>) => ({ p_oferta: o }),
  salvarDashboard: (d: Dashboard) => ({ p_dashboard: d }),
  excluirDashboard: (id: string) => ({ p_dashboard: id }),
  salvarPainel: (p: PainelPessoa) => ({ p_perfil: p.vendedorId, p_widgets: p.widgets }),
  salvarPreferencias: (p: PreferenciasNotificacao) => ({ p_preferencias: p }),
  /** Sem ids = todas as minhas; lista vazia = nenhuma (como o mock). */
  marcarNotificacoesLidas: (ids?: string[]) => ({ p_ids: ids === undefined ? null : ids }),
};
