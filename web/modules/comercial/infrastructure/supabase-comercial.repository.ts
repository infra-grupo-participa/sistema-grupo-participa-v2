'use client';

// Adapter Supabase do Comercial. Único lugar do módulo que chama `.rpc('crm_*')`.
// Leitura (migration 20261005s, F1): jsonb em camelCase → tipo do domínio em `mapeamento-supabase.ts` (puro e testado).
// Permissão mora no banco (RLS + guarda nas RPCs definer): quem não é do Comercial recebe erro 42501, que vira
// exceção aqui (nunca lista vazia).
// Escrita (migration 20261005t, F2): RPCs definer que devolvem `{ok, msg?, …ids}` com as MESMAS mensagens do mock
// (`mapeamento-escrita.ts`). Enquanto `crm.config.escrita_ligada = false`, todas respondem "CRM em manutenção".
// Métodos sem tabela no banco (conversa, ficha, fila, link) devolvem `ok:false` dizendo a fase.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { ComercialRepository, NovaAtividade, NovaFicha, Resultado } from '../application/ports';
import type {
  CampoKey, Contato, Conversa, Dashboard, EventoTimeline, FichaDisparo, FilaRecuperacao, FiltroLog, Funil, LinkRastreavel,
  LogCrm, Mensagem, MotivoPerda, MotivoPerdaConfig, Negocio, OfertaHotmart, PainelPessoa, PontoJornada,
  PreferenciasNotificacao, ProdutoHotmart, ProdutoKey, StatusFila, Template, TipoProjeto,
} from '../domain/types';
import {
  mapAgrupadores, mapAtividades, mapBuscaPorLink, mapConfig, mapPaginaContatos, mapDashboards, mapEventos, mapFunis, mapJornada,
  mapLog, mapMotivosPerda, mapNegocios, mapNotificacoes, mapOfertas, mapOfertasOrfas, mapPainel, mapPreferencias,
  mapProdutosHotmart, mapSessao, mapVendedores, mensagemErroRpc,
} from './mapeamento-supabase';
import {
  argsEscrita, mapResultado, mapResultadoComId, mapResultadoNegocio, mapResultadoProjeto, mensagemErroEscrita, semTabela,
} from './mapeamento-escrita';
// Padrão de fábrica de quem nunca personalizou (o mesmo que a demonstração usa).
import { painelPadrao, preferenciasPadrao } from './mock-dados';

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

  // ── Escrita (F2) ──
  /**
   * Chama a RPC de escrita. Erro de chamada (rede, função ausente, sem permissão) e formato fora do contrato viram
   * `{ok:false, msg}` para a tela mostrar; nunca sucesso presumido.
   */
  private async escrever<T extends Resultado>(fn: string, args: Record<string, unknown>, mapa: (d: unknown) => T): Promise<T | Resultado> {
    const { data, error } = await this.db().rpc(fn, args);
    if (error) {
      logQueryError(fn, error);
      return { ok: false, msg: mensagemErroEscrita(fn, error) };
    }
    try {
      return mapa(data);
    } catch (e) {
      return { ok: false, msg: e instanceof Error ? e.message : `Resposta inesperada do banco (${fn}).` };
    }
  }

  private simples(fn: string, args: Record<string, unknown>) {
    return this.escrever(fn, args, (d) => mapResultado(fn, d));
  }

  salvarFunil(f: Funil): Promise<Resultado & { funilId?: string }> {
    return this.escrever('crm_salvar_funil', argsEscrita.salvarFunil(f), (d) => mapResultadoComId('crm_salvar_funil', d, 'funilId'));
  }
  arquivarFunil(funilId: string) { return this.simples('crm_arquivar_funil', argsEscrita.arquivarFunil(funilId)); }
  criarAgrupador(nome: string, produto: ProdutoKey | null): Promise<Resultado & { agrupadorId?: string }> {
    return this.escrever('crm_criar_agrupador', argsEscrita.criarAgrupador(nome, produto), (d) => mapResultadoComId('crm_criar_agrupador', d, 'agrupadorId'));
  }
  criarProjeto(tipo: TipoProjeto, nome: string, agrupadorId: string, produto: ProdutoKey): Promise<Resultado & { funilIds?: string[] }> {
    return this.escrever('crm_criar_projeto', argsEscrita.criarProjeto(tipo, nome, agrupadorId, produto), mapResultadoProjeto);
  }
  salvarMotivoPerda(m: MotivoPerdaConfig) { return this.simples('crm_salvar_motivo_perda', argsEscrita.salvarMotivoPerda(m)); }

  moverEtapa(negocioId: string, etapaId: string) { return this.simples('crm_mover_etapa', argsEscrita.moverEtapa(negocioId, etapaId)); }
  salvarCampos(negocioId: string, campos: Partial<Record<CampoKey, string>>) {
    return this.simples('crm_salvar_campos', argsEscrita.salvarCampos(negocioId, campos));
  }
  marcarPerdido(negocioId: string, motivo: MotivoPerda, nota: string) {
    return this.simples('crm_marcar_perdido', argsEscrita.marcarPerdido(negocioId, motivo, nota));
  }
  transferirDono(negocioId: string, novoDonoId: string, motivo: string) {
    return this.simples('crm_transferir_dono', argsEscrita.transferirDono(negocioId, novoDonoId, motivo));
  }
  criarNegocio(contatoId: string, funilId: string, campanhaId?: string | null): Promise<Resultado & { negocioId?: string; donoId?: string | null }> {
    return this.escrever('crm_criar_negocio', argsEscrita.criarNegocio(contatoId, funilId, campanhaId), mapResultadoNegocio);
  }
  atribuirContato(contatoId: string, donoId: string, motivo: string) {
    return this.simples('crm_atribuir_contato', argsEscrita.atribuirContato(contatoId, donoId, motivo));
  }

  criarAtividade(a: NovaAtividade) { return this.simples('crm_criar_atividade', argsEscrita.criarAtividade(a)); }
  concluirAtividade(atividadeId: string, resultado: string) {
    return this.simples('crm_concluir_atividade', argsEscrita.concluirAtividade(atividadeId, resultado));
  }
  adicionarNota(contatoId: string, negocioId: string | null, texto: string) {
    return this.simples('crm_adicionar_nota', argsEscrita.adicionarNota(contatoId, negocioId, texto));
  }

  salvarDistribuicao(percentuais: Record<string, { percentual: number; ativo: boolean }>) {
    return this.simples('crm_salvar_distribuicao', argsEscrita.salvarDistribuicao(percentuais));
  }
  salvarPainel(p: PainelPessoa) { return this.simples('crm_salvar_painel', argsEscrita.salvarPainel(p)); }
  marcarNotificacoesLidas(ids?: string[]) { return this.simples('crm_marcar_notificacoes_lidas', argsEscrita.marcarNotificacoesLidas(ids)); }
  salvarPreferenciasNotificacao(p: PreferenciasNotificacao) { return this.simples('crm_salvar_preferencias', argsEscrita.salvarPreferencias(p)); }
  vincularProduto(p: Pick<ProdutoHotmart, 'produtoId' | 'noComercial' | 'nomeComercial' | 'produtoKey' | 'agrupadorId' | 'escada'>) {
    return this.simples('crm_vincular_produto', argsEscrita.vincularProduto(p));
  }
  salvarOferta(o: Pick<OfertaHotmart, 'codigo' | 'vigente' | 'condicao' | 'validaAte' | 'uso'>) {
    return this.simples('crm_salvar_oferta', argsEscrita.salvarOferta(o));
  }
  salvarDashboard(d: Dashboard): Promise<Resultado & { dashboardId?: string }> {
    return this.escrever('crm_salvar_dashboard', argsEscrita.salvarDashboard(d), (x) => mapResultadoComId('crm_salvar_dashboard', x, 'dashboardId'));
  }
  /** "Excluir" na tela = arquivar no banco (nada se apaga). */
  excluirDashboard(id: string) { return this.simples('crm_arquivar_dashboard', argsEscrita.excluirDashboard(id)); }

  // ── Escrita sem tabela no banco ainda (backend-arquitetura.md §6) ──
  async enviarMensagem(contatoId: string, texto: string, templateId?: string | null): Promise<Resultado> {
    void contatoId; void texto; void templateId;
    return semTabela('Envio de mensagem', 'Fase 4');
  }
  async marcarConversaLida(contatoId: string): Promise<Resultado> { void contatoId; return semTabela('Conversa', 'Fase 4'); }
  async atualizarItemFila(filaId: string, itemId: string, status: StatusFila): Promise<Resultado> {
    void filaId; void itemId; void status;
    return semTabela('Fila de recuperação', 'próxima fase');
  }
  async salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<Resultado> {
    void f; void enviarParaAprovacao;
    return semTabela('Ficha de disparo', 'Fase 4');
  }
  async decidirFicha(fichaId: string, aprovar: boolean): Promise<Resultado> { void fichaId; void aprovar; return semTabela('Ficha de disparo', 'Fase 4'); }
  async criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<Resultado> {
    void vendedorId; void produto; void acao; void canal;
    return semTabela('Link rastreável', 'próxima fase');
  }
}
