'use client';

// Adapter Supabase do Comercial. Único lugar do módulo que chama `.rpc('crm_*')`.
// Leitura (migration 20261005s, F1): jsonb em camelCase → tipo do domínio em `mapeamento-supabase.ts` (puro e testado).
// Permissão mora no banco (RLS + guarda nas RPCs definer): quem não é do Comercial recebe erro 42501, que vira
// exceção aqui (nunca lista vazia).
// Escrita (migration 20261005t, F2): RPCs definer que devolvem `{ok, msg?, …ids}` com as MESMAS mensagens do mock
// (`mapeamento-escrita.ts`). Enquanto `crm.config.escrita_ligada = false`, todas respondem "CRM em manutenção".
// WhatsApp (F4, 20261006051434) e filas/links (F5, 20261006044653): mesmas regras; com os interruptores desligados
// (`whatsapp_ligado`, `envio_ligado`), a leitura vem vazia de verdade e a escrita responde a mensagem do banco.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type {
  ComercialRepository, FiltroNegocios, NovaAtividade, NovaFicha, Resultado, ResultadoFicha, ResultadoLink, ResultadoTokenMcp,
} from '../application/ports';
import {
  casaBusca, linhasContatos, mapaDuplicados, paginarContatos, resumirContatos,
  type FiltroContatos, type PaginaContatos, type ResumoContatos,
} from '../domain/contatos';
import type {
  CampoKey, Contato, Conversa, Dashboard, EscopoMcp, PainelHotmart, TokenMcp, EventoTimeline, FichaDisparo, FilaRecuperacao, FiltroLog, Funil, LinkRastreavel,
  LogCrm, Mensagem, MotivoPerda, MotivoPerdaConfig, Negocio, OfertaHotmart, PainelPessoa, PontoJornada,
  PreferenciasNotificacao, ProdutoHotmart, ProdutoKey, StatusFila, StatusWhatsapp, Template, TipoProjeto,
} from '../domain/types';
import {
  mapAgrupadores, mapAtividades, mapBuscaPorLink, mapConfig, mapConversas, mapPaginaContatos, mapDashboards, mapEventos,
  mapFichas, mapFilas, mapFunis, mapJornada, mapLinks, mapLog, mapMensagens, mapMotivosPerda, mapNegocios, mapNotificacoes,
  mapOfertas, mapOfertasOrfas, mapPainel, mapPreferencias, mapProdutosHotmart, mapSessao, mapTemplates, mapVendedores,
  mapPainelHotmart, mapTokensMcp, mapWhatsappStatus, mensagemErroRpc,
  mapContatosPorIds, mapPaginaServidor, mapResumoContatos, rpcAusente, type ErroRpc,
} from './mapeamento-supabase';
import {
  argsCriarContato, argsEscrita, mapResultado, mapResultadoComId, mapResultadoContato, mapResultadoFicha, mapResultadoLink,
  mapResultadoNegocio, mapResultadoProjeto, mapResultadoTokenMcp,
  mensagemErroEscrita,
} from './mapeamento-escrita';
import type { EdicaoAtivacao, PainelAtivacao } from '../domain/ativacao';
import { argsSalvarAtivacao, mapPainelAtivacao } from './mapeamento-ativacao';
import { argsRegra, mapOrigemDetalhada, mapPainelCatalogo } from './mapeamento-catalogacao';
import type { OrigemDetalhada, PainelCatalogo, RegraCatalogo } from '../domain/catalogacao';
import { LIMITE_LEGENDA, caminhoAnexo, validarAnexo } from '../domain/midia';
import { LIMITE_AUDIO, extAudioPermitida } from '../domain/audio';
// Padrão de fábrica de quem nunca personalizou (o mesmo que a demonstração usa).
import { painelPadrao, preferenciasPadrao } from './mock-dados';

// Páginas das RPCs com offset. Teto de segurança: passou disso, é erro (não corta calado).
const PAGINA_NEGOCIOS = 2000;
// Busca de contatos no servidor: até 50 por termo (a tela mostra os primeiros; refinar o termo acha o resto).
const LIMITE_BUSCA_CONTATOS = 50;
// Contatos: 500 é o máximo que `crm_contatos` aceita por chamada. Teto próprio de 20 páginas (10.000 contatos):
// a lista de um gestor (2.648 em 06/10/2026) cabe em 6 chamadas. Ajuste rápido; a correção definitiva é a lista
// paginada no banco (docs/projetos/comercial/ajuste-rapido-2026-10-06.md).
const PAGINA_CONTATOS = 500;
const MAX_PAGINAS_CONTATOS = 20;
const PAGINA_ATIVIDADES = 2000;
const MAX_PAGINAS = 25;
// crm_contatos_por_ids aceita até 1.000 ids por chamada.
const LOTE_POR_IDS = 1000;
// Caminho antigo (RPC nova ainda não aplicada): a lista inteira fica 30 s em memória para trocar de página/filtro
// sem baixar tudo de novo a cada clique.
const VALIDADE_BASE_ANTIGA_MS = 30_000;

export class SupabaseComercialRepository implements ComercialRepository {
  private cliente: ReturnType<typeof createBrowserSupabase> | null = null;

  // Client criado na 1ª chamada (o módulo é avaliado também no servidor durante o SSR).
  private db() {
    if (!this.cliente) this.cliente = createBrowserSupabase();
    return this.cliente;
  }

  /** Chamada crua (ponto único que fala com o Supabase; os testes trocam por um falso). */
  private async bruto(fn: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: ErroRpc | null }> {
    const { data, error } = await this.db().rpc(fn, args);
    return { data, error };
  }

  private async rpc(fn: string, args?: Record<string, unknown>): Promise<unknown> {
    const { data, error } = await this.bruto(fn, args);
    if (error) {
      logQueryError(fn, error);
      throw new Error(mensagemErroRpc(fn, error));
    }
    return data;
  }

  // RPCs da migration 20261006m que o banco ainda não tem: depois da 1ª resposta 42883/PGRST202, nem tenta de novo.
  private ausentes = new Set<string>();

  /** RPC nova: devolve null se ela ainda não existe no banco (o chamador usa o caminho antigo). Outro erro lança. */
  private async rpcNova(fn: string, args: Record<string, unknown>): Promise<unknown | null> {
    if (this.ausentes.has(fn)) return null;
    const { data, error } = await this.bruto(fn, args);
    if (error) {
      if (rpcAusente(error)) {
        this.ausentes.add(fn);
        return null;
      }
      logQueryError(fn, error);
      throw new Error(mensagemErroRpc(fn, error));
    }
    return data;
  }

  private baseAntiga: { em: number; dados: Promise<{ contatos: Contato[]; negocios: Negocio[] }> } | null = null;

  /** Caminho antigo: lista inteira de contatos + negócios, reaproveitada por 30 s. */
  private carregarBaseAntiga() {
    const agora = Date.now();
    if (!this.baseAntiga || agora - this.baseAntiga.em > VALIDADE_BASE_ANTIGA_MS) {
      const dados = Promise.all([this.contatos(), this.negocios()]).then(([contatos, negocios]) => ({ contatos, negocios }));
      this.baseAntiga = { em: agora, dados };
      dados.catch(() => { this.baseAntiga = null; });
    }
    return this.baseAntiga.dados;
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
    for (let p = 0; p < MAX_PAGINAS_CONTATOS; p++) {
      const pg = mapPaginaContatos(await this.rpc('crm_contatos', { p_busca: null, p_limite: PAGINA_CONTATOS, p_offset: p * PAGINA_CONTATOS }));
      todos.push(...pg.itens);
      if (!pg.temMais) return todos;
    }
    const teto = (MAX_PAGINAS_CONTATOS * PAGINA_CONTATOS).toLocaleString('pt-BR');
    throw new Error(`Lista grande demais para carregar de uma vez (crm_contatos: mais de ${teto} contatos). Avise o time de dados.`);
  }

  /** Uma chamada só, com p_busca: a RPC aplica a regra da busca (vendedor acha qualquer sem dono). */
  async buscarContatos(texto: string): Promise<Contato[]> {
    const t = texto.trim();
    if (t.length < 3) return [];
    return mapPaginaContatos(await this.rpc('crm_contatos', { p_busca: t, p_limite: LIMITE_BUSCA_CONTATOS, p_offset: 0 })).itens;
  }

  /** Página da tela Contatos no servidor. Sem a RPC (migration 20261006m não aplicada): lista inteira, filtrada aqui. */
  async contatosPagina(f: FiltroContatos): Promise<PaginaContatos> {
    const busca = f.busca?.trim() ?? '';
    const d = await this.rpcNova('crm_contatos_pagina', {
      p_busca: busca || null, p_dono: f.dono ?? null, p_perfil: f.perfil ?? null, p_uf: f.uf ?? null,
      p_tags: f.tags?.length ? f.tags : null, p_opt_out: !!f.optOut, p_so_alunos: !!f.soAlunos,
      p_ordem: f.ordem ?? 'criado', p_dir: f.dir ?? 'desc', p_limite: f.limite ?? 50, p_offset: f.offset ?? 0,
      // 20261007141044: só vão quando filtram (sem a migration, a RPC de 11 parâmetros continua respondendo o resto)
      ...(f.canal && f.canal !== 'todos' ? { p_canal: f.canal } : {}),
      ...(f.projeto && f.projeto !== 'todos' ? { p_projeto: f.projeto } : {}),
    });
    if (d !== null) return mapPaginaServidor(d);
    const [{ contatos, negocios }, vendedores, achados] = await Promise.all([
      this.carregarBaseAntiga(), this.vendedores(), busca.length >= 3 ? this.buscarContatos(busca) : Promise.resolve([] as Contato[]),
    ]);
    // a busca do servidor alcança quem não está na lista do vendedor; e-mail/telefone mascarados não casam aqui
    const ids = new Set(contatos.map((c) => c.id));
    const daBusca = new Set(achados.map((c) => c.id));
    const base = [...contatos, ...achados.filter((c) => !ids.has(c.id))]
      .filter((c) => !busca || daBusca.has(c.id) || casaBusca(c, busca));
    const nomes = new Map(vendedores.map((v) => [v.id, v.nome]));
    return paginarContatos(linhasContatos(base, negocios), { ...f, busca: undefined }, (id) => (id ? nomes.get(id) ?? '' : ''));
  }

  async contatosResumo(): Promise<ResumoContatos> {
    const d = await this.rpcNova('crm_contatos_resumo', {});
    if (d !== null) return mapResumoContatos(d);
    return resumirContatos((await this.carregarBaseAntiga()).contatos);
  }

  /** Em lotes de 1.000. Sem a RPC: filtra a lista inteira (quem não está nela fica de fora, como antes). */
  async contatosPorIds(ids: string[]): Promise<Contato[]> {
    const unicos = [...new Set(ids.filter(Boolean))];
    if (!unicos.length) return [];
    const achados: Contato[] = [];
    for (let i = 0; i < unicos.length; i += LOTE_POR_IDS) {
      const d = await this.rpcNova('crm_contatos_por_ids', { p_ids: unicos.slice(i, i + LOTE_POR_IDS) });
      if (d === null) {
        const pedidos = new Set(unicos);
        return (await this.carregarBaseAntiga()).contatos.filter((c) => pedidos.has(c.id));
      }
      achados.push(...mapContatosPorIds(d).contatos);
    }
    return achados;
  }

  async duplicadosDe(contatoId: string): Promise<Contato[]> {
    const d = await this.rpcNova('crm_contatos_por_ids', { p_ids: [contatoId], p_duplicados: true });
    if (d === null) {
      const lista = (await this.carregarBaseAntiga()).contatos;
      const ids = mapaDuplicados(lista).get(contatoId) ?? [];
      return lista.filter((c) => ids.includes(c.id));
    }
    const dup = mapContatosPorIds(d).duplicados.get(contatoId) ?? [];
    return dup.length ? this.contatosPorIds(dup) : [];
  }

  async jornada(contatoId: string): Promise<PontoJornada[]> {
    return mapJornada(await this.rpc('crm_jornada', { p_pessoa: contatoId }));
  }

  /** Filtro opcional no banco (p_pessoa resolve o grupo de alias; p_funil; p_status). */
  negocios(filtro: FiltroNegocios = {}): Promise<Negocio[]> {
    const args: Record<string, unknown> = {};
    if (filtro.contatoId) args.p_pessoa = filtro.contatoId;
    if (filtro.funilId) args.p_funil = filtro.funilId;
    if (filtro.status) args.p_status = filtro.status;
    return this.todasPaginas('crm_negocios', PAGINA_NEGOCIOS, mapNegocios, args);
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

  // ── WhatsApp (F4) ──
  async conversas(): Promise<Conversa[]> { return mapConversas(await this.rpc('crm_conversas', { p_limite: 300 })); }
  async mensagens(contatoId: string): Promise<Mensagem[]> {
    return mapMensagens(await this.rpc('crm_mensagens', { p_pessoa: contatoId, p_limite: 500 }));
  }
  async templates(): Promise<Template[]> { return mapTemplates(await this.rpc('crm_templates')); }
  async fichas(): Promise<FichaDisparo[]> { return mapFichas(await this.rpc('crm_fichas', { p_limite: 200 })); }
  async whatsappStatus(): Promise<StatusWhatsapp> { return mapWhatsappStatus(await this.rpc('crm_whatsapp_status')); }

  // ── Filas de recuperação e links (F5) ──
  /** Só as abertas. Vendas por link (`p_vendas`) custam 2 Seq Scans: ficam para pedido explícito. */
  async filas(): Promise<FilaRecuperacao[]> { return mapFilas(await this.rpc('crm_filas', { p_incluir_encerradas: false })); }
  async links(): Promise<LinkRastreavel[]> {
    return mapLinks(await this.rpc('crm_links', { p_vendas: false, p_incluir_arquivados: false }));
  }

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

  // ── Catalogação de origem (20261007141044) ──
  async catalogo(): Promise<PainelCatalogo> { return mapPainelCatalogo(await this.rpc('crm_catalogo')); }
  salvarRegraCatalogo(r: RegraCatalogo): Promise<Resultado & { id?: number }> {
    return this.escrever('crm_catalogo_regra_salvar', argsRegra(r), (d) => {
      const res = mapResultado('crm_catalogo_regra_salvar', d);
      const id = (d as { id?: unknown } | null)?.id;
      return typeof id === 'number' ? { ...res, id } : res;
    });
  }
  salvarListaAc(id: string, nome: string) { return this.simples('crm_catalogo_lista_salvar', { p_id: id, p_nome: nome }); }
  reaplicarCatalogo(todos = false): Promise<Resultado & { catalogados?: number }> {
    return this.escrever('crm_catalogo_reaplicar', { p_todos: todos }, (d) => {
      const res = mapResultado('crm_catalogo_reaplicar', d);
      const n = (d as { catalogados?: unknown } | null)?.catalogados;
      return typeof n === 'number' ? { ...res, catalogados: n } : res;
    });
  }
  async origemContato(contatoId: string): Promise<OrigemDetalhada | null> {
    // Sem a migration: a ficha simplesmente não mostra o bloco (null), sem erro.
    const d = await this.rpcNova('crm_contato_origem', { p_pessoa: contatoId });
    return d === null ? null : mapOrigemDetalhada(d);
  }
  definirProjetoContato(contatoId: string, projeto: string | null) {
    return this.simples('crm_contato_origem_definir', { p_pessoa: contatoId, p_projeto: projeto });
  }

  // Ativação padrão (migration 20261007135415). Sem a migration aplicada, a leitura dá erro claro (nunca painel vazio).
  async ativacao(): Promise<PainelAtivacao> { return mapPainelAtivacao(await this.rpc('crm_ativacao_painel')); }
  salvarAtivacao(e: EdicaoAtivacao) { return this.simples('crm_ativacao_salvar', argsSalvarAtivacao(e)); }
  garantirAtivacao(projeto: string): Promise<Resultado & { funilId?: string }> {
    return this.escrever('crm_ativacao_garantir', { p_projeto: projeto }, (d) => mapResultadoComId('crm_ativacao_garantir', d, 'funilId'));
  }
  encerrarAtivacao(projeto: string) { return this.simples('crm_ativacao_encerrar', { p_projeto: projeto }); }

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
  /** "Novo contato" (crm_criar_contato, 20261007133345): cria ou casa a pessoa (e-mail, depois telefone) e devolve a ficha a abrir. */
  criarContato(c: { nome: string; telefone: string; email: string; donoId?: string | null }) {
    return this.escrever('crm_criar_contato', argsCriarContato(c), mapResultadoContato);
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

  // ── Escrita WhatsApp (F4) ──
  enviarMensagem(contatoId: string, texto: string, templateId?: string | null): Promise<Resultado & { mensagemId?: string }> {
    return this.escrever('crm_enviar_mensagem', argsEscrita.enviarMensagem(contatoId, texto, templateId),
      (d) => mapResultadoComId('crm_enviar_mensagem', d, 'mensagemId'));
  }
  marcarConversaLida(contatoId: string) { return this.simples('crm_marcar_conversa_lida', argsEscrita.marcarConversaLida(contatoId)); }

  // ── Arquivos do WhatsApp (20261007140044): bucket privado crm-midia ──
  /** Sobe em envio/<meu id>/<uuid>.<ext> (policy do Storage) e enfileira pela crm_enviar_mensagem (que valida de novo). */
  async enviarAnexo(contatoId: string, arquivo: File, legenda: string): Promise<Resultado & { mensagemId?: string }> {
    const v = validarAnexo(arquivo);
    if (!v.ok) return { ok: false, msg: v.msg };
    if (legenda.trim().length > LIMITE_LEGENDA) return { ok: false, msg: 'Legenda longa demais (máximo 1.024 caracteres).' };
    const { data: u } = await this.db().auth.getUser();
    const eu = u.user?.id;
    if (!eu) return { ok: false, msg: 'Sessão expirada. Entre de novo.' };
    const caminho = caminhoAnexo(eu, crypto.randomUUID(), v.ext);
    const { error } = await this.db().storage.from('crm-midia').upload(caminho, arquivo, { contentType: v.mime, upsert: false, cacheControl: '3600' });
    if (error) {
      logQueryError('crm-midia upload', error);
      return { ok: false, msg: 'Não foi possível subir o arquivo. Tente de novo.' };
    }
    return this.escrever('crm_enviar_mensagem', argsEscrita.enviarAnexo(contatoId, caminho, legenda, v.tipo === 'documento' ? v.nome : null),
      (d) => mapResultadoComId('crm_enviar_mensagem', d, 'mensagemId'));
  }
  /** Áudio gravado (20261007s): sobe em envio/<meu id>/<uuid>.<ogg|m4a|aac|mp3> e enfileira sem legenda. */
  async enviarAudio(contatoId: string, audio: Blob, formato: { mime: string; ext: string }): Promise<Resultado & { mensagemId?: string }> {
    if (!extAudioPermitida(formato.ext, formato.mime)) return { ok: false, msg: 'Formato de áudio não aceito.' };
    if (!audio.size) return { ok: false, msg: 'A gravação ficou vazia. Grave de novo.' };
    if (audio.size > LIMITE_AUDIO) return { ok: false, msg: 'Áudio grande demais (máximo 16 MB).' };
    const { data: u } = await this.db().auth.getUser();
    const eu = u.user?.id;
    if (!eu) return { ok: false, msg: 'Sessão expirada. Entre de novo.' };
    const caminho = caminhoAnexo(eu, crypto.randomUUID(), formato.ext);
    const { error } = await this.db().storage.from('crm-midia').upload(caminho, audio, { contentType: formato.mime, upsert: false, cacheControl: '3600' });
    if (error) {
      logQueryError('crm-midia upload audio', error);
      return { ok: false, msg: 'Não foi possível subir o áudio. Tente de novo.' };
    }
    return this.escrever('crm_enviar_mensagem', argsEscrita.enviarAudio(contatoId, caminho),
      (d) => mapResultadoComId('crm_enviar_mensagem', d, 'mensagemId'));
  }
  /** URL assinada de 10 min; o Storage aplica a policy crm_midia_ler (mesma regra de quem vê a conversa). */
  async urlMidia(caminho: string): Promise<string | null> {
    const { data, error } = await this.db().storage.from('crm-midia').createSignedUrl(caminho, 600);
    if (error || !data?.signedUrl) {
      if (error) logQueryError('crm-midia url', error);
      return null;
    }
    return data.signedUrl;
  }
  salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<ResultadoFicha> {
    return this.escrever('crm_salvar_ficha', argsEscrita.salvarFicha(f, enviarParaAprovacao), mapResultadoFicha);
  }
  decidirFicha(fichaId: string, aprovar: boolean) { return this.simples('crm_decidir_ficha', argsEscrita.decidirFicha(fichaId, aprovar)); }

  // ── Escrita filas e links (F5) ──
  atualizarItemFila(filaId: string, itemId: string, status: StatusFila) {
    return this.simples('crm_atualizar_item_fila', argsEscrita.atualizarItemFila(filaId, itemId, status));
  }
  criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<ResultadoLink> {
    return this.escrever('crm_criar_link', argsEscrita.criarLink(vendedorId, produto, acao, canal), mapResultadoLink);
  }

  // ── Integração Hotmart (F3) ──
  /** 42501 (não é gestor) vira exceção: a tela mostra o erro, nunca um painel zerado. */
  async hotmartPainel(dias: number): Promise<PainelHotmart> {
    return mapPainelHotmart(await this.rpc('crm_hotmart_painel', { p_dias: dias }));
  }
  reprocessarHotmart(chave: string) { return this.simples('crm_hotmart_reprocessar', argsEscrita.reprocessarHotmart(chave)); }

  // ── MCP (F7) ──
  async tokensMcp(): Promise<TokenMcp[]> { return mapTokensMcp(await this.rpc('crm_mcp_tokens')); }
  criarTokenMcp(nome: string, escopos: EscopoMcp[], dias: number): Promise<ResultadoTokenMcp> {
    return this.escrever('crm_mcp_criar_token', argsEscrita.criarTokenMcp(nome, escopos, dias), mapResultadoTokenMcp);
  }
  revogarTokenMcp(id: string) { return this.simples('crm_mcp_revogar_token', argsEscrita.revogarTokenMcp(id)); }
}
