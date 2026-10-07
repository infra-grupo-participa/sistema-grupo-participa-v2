// Mapeamento PURO das RPCs de ESCRITA `public.crm_*` (F2 20261005t, WhatsApp/F4 20261006051434, F5 20261006044653): argumentos do port → parâmetros
// da RPC, e o jsonb `{ok, msg?, …ids}` → `Resultado`. Sem Supabase, sem React.
// Regra violada volta como `{ok:false, msg}` (mesmas mensagens do mock); erro de transporte/banco vira `ok:false`
// com mensagem clara (a tela mostra o toast), nunca exceção solta nem sucesso falso.
import type { NovaAtividade, NovaFicha, Resultado, ResultadoFicha, ResultadoLink, ResultadoTokenMcp } from '../application/ports';
import type {
  CampoKey, Dashboard, EscopoMcp, Funil, MotivoPerda, MotivoPerdaConfig, OfertaHotmart, PainelPessoa, PreferenciasNotificacao,
  ProdutoHotmart, ProdutoKey, StatusFila, TipoProjeto,
} from '../domain/types';
import { FormatoInesperado, escoposMcp, type ErroRpc } from './mapeamento-supabase';

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

/** Cadastro rápido de contato (crm_criar_contato, migration 20261007133345). Vazio vira ausente: o banco decide. */
export function argsCriarContato(c: { nome: string; telefone: string; email: string; donoId?: string | null }): { p_dados: Obj } {
  const p_dados: Obj = { nome: c.nome.trim() };
  if (c.email.trim()) p_dados.email = c.email.trim();
  if (c.telefone.trim()) p_dados.telefone = c.telefone.trim();
  if (c.donoId) p_dados.dono = c.donoId;
  return { p_dados };
}

/** criarContato: contatoId (ficha a abrir), `nova` (false = já estava no CRM) e o dono que ficou (null = sem dono). */
export function mapResultadoContato(d: unknown): Resultado & { contatoId?: string; nova?: boolean; donoId?: string | null } {
  const r: Resultado & { contatoId?: string; nova?: boolean; donoId?: string | null } = mapResultadoComId('crm_criar_contato', d, 'contatoId');
  if (r.ok) {
    if (!r.contatoId) throw new FormatoInesperado('crm_criar_contato', 'ok sem contatoId');
    const o = d as Obj;
    r.nova = o.nova === true;
    r.donoId = typeof o.donoId === 'string' && o.donoId ? o.donoId : null;
  }
  return r;
}

/** Erro de chamada (rede, função ausente, permissão) → mensagem para a tela. */
export function mensagemErroEscrita(rpc: string, e: ErroRpc): string {
  if (e.code === '42501') return e.message || 'Sem acesso ao Comercial.';
  if (e.code === 'PGRST202' || e.code === '42883') {
    return `O banco ainda não tem a função ${rpc} (migration do CRM não aplicada).`;
  }
  return `Não foi possível salvar no banco (${rpc})${e.message ? `: ${e.message}` : ''}.`;
}

/** salvarFicha: id, código e a contagem feita pelo banco (quantidade e suprimidos). */
export function mapResultadoFicha(d: unknown): ResultadoFicha {
  const r: ResultadoFicha = mapResultadoComId('crm_salvar_ficha', d, 'fichaId');
  if (r.ok) {
    const o = d as Obj;
    if (typeof o.codigo === 'string' && o.codigo) r.codigo = o.codigo;
    if (typeof o.quantidade === 'number') r.quantidade = o.quantidade;
    if (typeof o.suprimidos === 'number') r.suprimidos = o.suprimidos;
  }
  return r;
}

/** criarLink: id, sck e a URL pronta (oferta vigente + sck + UTMs). */
export function mapResultadoLink(d: unknown): ResultadoLink {
  const r: ResultadoLink = mapResultadoComId('crm_criar_link', d, 'linkId');
  if (r.ok) {
    const o = d as Obj;
    if (typeof o.sck === 'string' && o.sck) r.sck = o.sck;
    if (typeof o.url === 'string' && o.url) r.url = o.url;
  }
  return r;
}

/** criarTokenMcp: o token completo só existe nesta resposta (o banco guarda o sha-256). */
export function mapResultadoTokenMcp(d: unknown): ResultadoTokenMcp {
  const r: ResultadoTokenMcp = mapResultadoComId('crm_mcp_criar_token', d, 'id');
  if (r.ok) {
    const o = d as Obj;
    if (typeof o.token !== 'string' || !o.token.startsWith('gpc_')) throw new FormatoInesperado('crm_mcp_criar_token', 'token ausente');
    r.token = o.token;
    if (typeof o.prefixo === 'string') r.prefixo = o.prefixo;
    r.escopos = escoposMcp(o.escopos);
    if (typeof o.expiraEm === 'string') r.expiraEm = o.expiraEm;
  }
  return r;
}

// ── Argumentos de cada RPC (nomes p_* = assinatura da migration 20261005t) ──

export const argsEscrita = {
  // F3 e F7 (assinaturas conferidas em pg_proc em 06/10/2026)
  reprocessarHotmart: (chave: string) => ({ p_chave: chave }),
  criarTokenMcp: (nome: string, escopos: EscopoMcp[], dias: number) => ({ p_nome: nome.trim(), p_escopos: escopos, p_dias: dias }),
  revogarTokenMcp: (id: string) => ({ p_id: id }),
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
  // `distribuicao` sempre presente (null = sem distribuição própria): até a 20261006n, chave AUSENTE no payload virava
  // "Campo obrigatório vazio." no crm_salvar_funil (jsonb_typeof(NULL) → distribuicao_propria NULL).
  salvarFunil: (f: Funil) => ({ p_funil: { ...f, distribuicao: f.distribuicao ?? null } }),
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
  // WhatsApp (F4). Com template, o banco monta o texto e ignora p_texto.
  enviarMensagem: (contatoId: string, texto: string, templateId?: string | null) => ({ p_pessoa: contatoId, p_texto: texto, p_template: templateId || null }),
  marcarConversaLida: (contatoId: string) => ({ p_pessoa: contatoId }),
  /**
   * Ficha: `destinatarios` (contatoIds) é a lista que o banco grava. quantidade/suprimidos não vão (o banco conta).
   * `numeroEnvio` vazio = número padrão; só dígitos quando vier (o rótulo da tela não é número).
   */
  salvarFicha: (f: NovaFicha & { id?: string }, enviarParaAprovacao: boolean) => {
    const digitos = f.numeroEnvio.replace(/\D/g, '');
    return {
      p_ficha: {
        ...(f.id ? { id: f.id } : {}),
        objetivo: f.objetivo, produto: f.produto, filtro: f.filtro, templateId: f.templateId, numeroEnvio: digitos,
        agendadoPara: f.agendadoPara, link: f.link, destinatarios: [...new Set(f.destinatarios)],
      },
      p_enviar_para_aprovacao: enviarParaAprovacao,
    };
  },
  decidirFicha: (fichaId: string, aprovar: boolean) => ({ p_ficha: fichaId, p_aprovar: aprovar }),
  // Filas e links (F5).
  atualizarItemFila: (filaId: string, itemId: string, status: StatusFila) => ({ p_fila: filaId, p_item: itemId, p_status: status }),
  criarLink: (vendedorId: string, produto: ProdutoKey, acao: string, canal: string) => ({
    p_vendedor: vendedorId, p_produto: produto, p_acao: acao, p_canal: canal,
  }),
  /** Sem ids = todas as minhas; lista vazia = nenhuma (como o mock). */
  marcarNotificacoesLidas: (ids?: string[]) => ({ p_ids: ids === undefined ? null : ids }),
};
