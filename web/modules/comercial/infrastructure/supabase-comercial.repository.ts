'use client';

// Adapter Supabase do Comercial (Fase 1: só LEITURA). Único lugar do módulo que chama `.rpc('crm_*')`.
// As RPCs (migration 20261005s) devolvem jsonb em camelCase; o formato vira tipo do domínio em
// `mapeamento-supabase.ts` (puro e testado). Permissão mora no banco (RLS + guarda nas RPCs definer):
// quem não é do Comercial recebe erro 42501, que vira exceção aqui (nunca lista vazia).
// Escrita entra na Fase 2 (RPCs definer de escrita); até lá todo método de escrita devolve `ok: false`.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { ComercialRepository, Resultado } from '../application/ports';
import type {
  Contato, Conversa, Dashboard, EventoTimeline, FichaDisparo, FilaRecuperacao, FiltroLog, LinkRastreavel, LogCrm,
  Mensagem, Negocio, OfertaHotmart, PainelPessoa, PontoJornada, PreferenciasNotificacao, ProdutoHotmart, Template,
} from '../domain/types';
import {
  mapAgrupadores, mapAtividades, mapBuscaPorLink, mapConfig, mapPaginaContatos, mapDashboards, mapEventos, mapFunis, mapJornada,
  mapLog, mapMotivosPerda, mapNegocios, mapNotificacoes, mapOfertas, mapOfertasOrfas, mapPainel, mapPreferencias,
  mapProdutosHotmart, mapSessao, mapVendedores, mensagemErroRpc,
} from './mapeamento-supabase';
// Padrão de fábrica de quem nunca personalizou (o mesmo que a demonstração usa).
import { painelPadrao, preferenciasPadrao } from './mock-dados';

const SEM_ESCRITA: Resultado = { ok: false, msg: 'Escrita do CRM entra na Fase 2.' };
const escrita = async (): Promise<Resultado> => SEM_ESCRITA;

// Páginas das RPCs com offset. Teto de segurança: passou disso, é erro (não corta calado).
const PAGINA_NEGOCIOS = 2000;
const PAGINA_CONTATOS = 100;
const PAGINA_ATIVIDADES = 2000;
const MAX_PAGINAS = 25;

export class SupabaseComercialRepository implements ComercialRepository {
  private cliente: ReturnType<typeof createBrowserSupabase> | null = null;

  // Client criado na 1ª chamada (o módulo é avaliado também no servidor durante o SSR).
  private db() {
    if (!this.cliente) this.cliente = createBrowserSupabase();
    return this.cliente;
  }

  private async rpc(fn: string, args?: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.db().rpc(fn, args);
    if (error) {
      logQueryError(fn, error);
      throw new Error(mensagemErroRpc(fn, error));
    }
    return data;
  }

  /**
   * Lê todas as páginas de uma RPC com p_limite/p_offset até a página vir vazia. Remove repetidos por id.
   */
  private async todasPaginas<T extends { id: string }>(fn: string, tamanho: number, mapa: (d: unknown) => T[], args: Record<string, unknown> = {}): Promise<T[]> {
    const vistos = new Map<string, T>();
    for (let p = 0; p < MAX_PAGINAS; p++) {
      const pagina = mapa(await this.rpc(fn, { ...args, p_limite: tamanho, p_offset: p * tamanho }));
      if (!pagina.length) return [...vistos.values()];
      for (const x of pagina) if (!vistos.has(x.id)) vistos.set(x.id, x);
    }
    throw new Error(`Lista grande demais para carregar de uma vez (${fn}: mais de ${MAX_PAGINAS * tamanho}).`);
  }

  // ── Leitura (F1) ──
  async sessao() { return mapSessao(await this.rpc('crm_sessao')); }
  async vendedores() { return mapVendedores(await this.rpc('crm_vendedores')); }
  async config() { return mapConfig(await this.rpc('crm_config')); }
  async agrupadores() { return mapAgrupadores(await this.rpc('crm_agrupadores')); }
  async funis() { return mapFunis(await this.rpc('crm_funis', { p_incluir_arquivados: false })); }
  async motivosPerda() { return mapMotivosPerda(await this.rpc('crm_motivos_perda')); }

  /** Pagina por { itens, temMais }: a RPC filtra o alias antes do limite, então as páginas não se sobrepõem. */
  async contatos(): Promise<Contato[]> {
    const todos: Contato[] = [];
    for (let p = 0; p < MAX_PAGINAS; p++) {
      const pg = mapPaginaContatos(await this.rpc('crm_contatos', { p_busca: null, p_limite: PAGINA_CONTATOS, p_offset: p * PAGINA_CONTATOS }));
      todos.push(...pg.itens);
      if (!pg.temMais) return todos;
    }
    throw new Error(`Lista grande demais para carregar de uma vez (crm_contatos: mais de ${MAX_PAGINAS * PAGINA_CONTATOS}).`);
  }

  async jornada(contatoId: string): Promise<PontoJornada[]> {
    return mapJornada(await this.rpc('crm_jornada', { p_pessoa: contatoId }));
  }

  negocios(): Promise<Negocio[]> {
    return this.todasPaginas('crm_negocios', PAGINA_NEGOCIOS, mapNegocios);
  }

  /** Abertas + concluídas nos últimos 30 dias (p_desde padrão da RPC), paginadas por p_offset. */
  atividades() { return this.todasPaginas('crm_atividades', PAGINA_ATIVIDADES, mapAtividades); }

  /** Com id: a linha do tempo da pessoa. Sem id: o dia de hoje (fechamento do dia, padrão da RPC). */
  async eventos(contatoId?: string): Promise<EventoTimeline[]> {
    return mapEventos(await this.rpc('crm_eventos', contatoId ? { p_pessoa: contatoId } : {}));
  }

  async painel(vendedorId: string): Promise<PainelPessoa> {
    const p = mapPainel(await this.rpc('crm_painel', { p_perfil: vendedorId }));
    if (p) return p;
    const vend = await this.vendedores();
    return painelPadrao(vendedorId, vend.find((v) => v.id === vendedorId)?.papel === 'gestor');
  }

  async notificacoes() { return mapNotificacoes(await this.rpc('crm_notificacoes')); }

  async preferenciasNotificacao(): Promise<PreferenciasNotificacao> {
    const [d, s] = await Promise.all([this.rpc('crm_preferencias'), this.sessao()]);
    return mapPreferencias(d, preferenciasPadrao(s.vendedorId));
  }

  async produtosHotmart(): Promise<ProdutoHotmart[]> {
    return mapProdutosHotmart(await this.rpc('crm_produtos_hotmart'));
  }

  async ofertas(produtoId?: string): Promise<OfertaHotmart[]> {
    return mapOfertas(await this.rpc('crm_ofertas', produtoId ? { p_produto: produtoId } : {}));
  }

  /** Últimos 90 dias (histórico inteiro custa ~1 s: materializar se a tela precisar). */
  async ofertasOrfas() { return mapOfertasOrfas(await this.rpc('crm_ofertas_orfas', { p_dias: 90 })); }

  async buscarPorLinkHotmart(linkOuCodigo: string) {
    return mapBuscaPorLink(await this.rpc('crm_buscar_por_link', { p_texto: linkOuCodigo }));
  }

  async dashboards(): Promise<Dashboard[]> { return mapDashboards(await this.rpc('crm_dashboards')); }

  async log(filtro: FiltroLog = {}): Promise<LogCrm[]> {
    // FiltroLog.autorId: undefined = qualquer; null = sistema. Na RPC: null = qualquer; 'sistema' = sem autor.
    const pAutor = filtro.autorId === undefined ? null : filtro.autorId === null ? 'sistema' : filtro.autorId;
    return mapLog(await this.rpc('crm_log', {
      p_autor: pAutor, p_entidade: filtro.entidade ?? null, p_entidade_id: filtro.entidadeId ?? null,
      p_pessoa: filtro.contatoId ?? null, p_desde: filtro.desde ?? null, p_ate: filtro.ate ?? null,
      p_limite: filtro.limite ?? 500,
    }));
  }

  // ── Leitura que a F1 não cobre (backend-arquitetura.md §6) ──
  // Lista vazia é o estado verdadeiro: sem a fase, o sistema não tem nenhum desses registros.
  // Erro aqui derrubaria telas inteiras (o Início junta todas as leituras).
  async conversas(): Promise<Conversa[]> { return []; }
  async mensagens(contatoId: string): Promise<Mensagem[]> { void contatoId; return []; }
  async templates(): Promise<Template[]> { return []; }
  async fichas(): Promise<FichaDisparo[]> { return []; }
  async filas(): Promise<FilaRecuperacao[]> { return []; }
  async links(): Promise<LinkRastreavel[]> { return []; }

  // ── Escrita (Fase 2) ──
  salvarFunil = escrita;
  arquivarFunil = escrita;
  criarAgrupador = escrita;
  criarProjeto = escrita;
  salvarMotivoPerda = escrita;
  moverEtapa = escrita;
  salvarCampos = escrita;
  marcarPerdido = escrita;
  transferirDono = escrita;
  criarNegocio = escrita;
  atribuirContato = escrita;
  criarAtividade = escrita;
  concluirAtividade = escrita;
  adicionarNota = escrita;
  enviarMensagem = escrita;
  marcarConversaLida = escrita;
  atualizarItemFila = escrita;
  salvarFicha = escrita;
  decidirFicha = escrita;
  salvarDistribuicao = escrita;
  criarLink = escrita;
  salvarPainel = escrita;
  marcarNotificacoesLidas = escrita;
  salvarPreferenciasNotificacao = escrita;
  vincularProduto = escrita;
  salvarOferta = escrita;
  salvarDashboard = escrita;
  excluirDashboard = escrita;
}
