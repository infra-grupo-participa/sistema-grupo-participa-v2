// Contrato entre as telas do Comercial e a fonte de dados.
//
// Hoje quem cumpre é `MockComercialRepository` (dados de demonstração em memória). Quando o backend existir,
// entra um `SupabaseComercialRepository` com a MESMA interface e as telas não mudam: trocar em
// `ui/repositorio.ts`. As regras que travam escrita (campos obrigatórios, ganho só com pagamento, troca de dono
// só pelo gestor, ficha aprovada antes do disparo) precisam ser repetidas no banco (RPC SECURITY DEFINER).
import type {
  Agrupador, Atividade, CampoKey, ConfigComercial, Contato, Conversa, EventoTimeline, FichaDisparo, FilaRecuperacao,
  Dashboard, EscopoMcp, FiltroLog, PainelHotmart, TokenMcp, Funil, LinkRastreavel, LogCrm, OfertaHotmart, OfertaOrfa, ProdutoHotmart, Mensagem, MotivoPerda, MotivoPerdaConfig, Negocio, Notificacao, PainelPessoa, PontoJornada,
  PreferenciasNotificacao, ProdutoKey, SessaoComercial, StatusFila, StatusWhatsapp, Template, TipoAtividade, TipoProjeto, Vendedor,
} from '../domain/types';

export interface Resultado {
  ok: boolean;
  msg?: string;
}

export interface ResultadoFicha extends Resultado {
  fichaId?: string;
  codigo?: string;
  quantidade?: number;
  suprimidos?: number;
}

export interface ResultadoLink extends Resultado {
  linkId?: string;
  sck?: string;
  url?: string;
}

/** Token novo do MCP: o texto completo (`token`) só vem nesta resposta e nunca mais. */
export interface ResultadoTokenMcp extends Resultado {
  id?: string;
  token?: string;
  prefixo?: string;
  escopos?: EscopoMcp[];
  expiraEm?: string;
}

export interface NovaAtividade {
  negocioId: string | null;
  contatoId: string;
  tipo: TipoAtividade;
  titulo: string;
  venceEm: string;
}

export interface NovaFicha {
  objetivo: string;
  produto: ProdutoKey;
  /** Descrição legível do filtro (vai para a ficha e o log). */
  filtro: string;
  /** Contatos (ids) que o filtro devolveu: é a lista que o banco grava e conta. */
  destinatarios: string[];
  /** Calculados na tela só para mostrar; o banco recalcula (supressões no momento de salvar). */
  quantidade: number;
  suprimidos: number;
  templateId: string;
  numeroEnvio: string;
  agendadoPara: string;
  link: string;
}

export interface ComercialRepository {
  /** Quem está usando a tela (vendedor + papel). */
  sessao(): Promise<SessaoComercial>;
  vendedores(): Promise<Vendedor[]>;
  config(): Promise<ConfigComercial>;

  /** Construtor de funis: agrupadores (pastas) e funis com etapas e campanhas próprias. */
  agrupadores(): Promise<Agrupador[]>;
  funis(): Promise<Funil[]>;

  /** Cadastro de motivos de perda (9 de fábrica + os criados pelo gestor). */
  motivosPerda(): Promise<MotivoPerdaConfig[]>;

  contatos(): Promise<Contato[]>;
  /**
   * Jornada completa da pessoa com a empresa: inscrições (cada uma com a UTM daquela entrada), listas, pesquisas,
   * grupos, presença, checkout, compras, reembolsos, negócios e conversas. Do mais recente para o mais antigo.
   */
  jornada(contatoId: string): Promise<PontoJornada[]>;
  negocios(): Promise<Negocio[]>;
  atividades(): Promise<Atividade[]>;
  /** Linha do tempo de um contato (todos os negócios dele). Sem id: todos os eventos (fechamento do dia). */
  eventos(contatoId?: string): Promise<EventoTimeline[]>;

  conversas(): Promise<Conversa[]>;
  mensagens(contatoId: string): Promise<Mensagem[]>;
  templates(): Promise<Template[]>;
  /** Interruptores e limites do WhatsApp (sem dado de pessoa). */
  whatsappStatus(): Promise<StatusWhatsapp>;

  filas(): Promise<FilaRecuperacao[]>;
  fichas(): Promise<FichaDisparo[]>;
  links(): Promise<LinkRastreavel[]>;

  // ── Escrita ──
  /** Cria ou atualiza um funil (id vazio = novo). Valida com `validarFunil`. Só o gestor. */
  salvarFunil(f: Funil): Promise<Resultado & { funilId?: string }>;
  /** Arquiva (some da lista; negócios encerrados ficam no histórico). Bloqueia se houver negócio aberto. */
  arquivarFunil(funilId: string): Promise<Resultado>;
  criarAgrupador(nome: string, produto: ProdutoKey | null): Promise<Resultado & { agrupadorId?: string }>;
  /** "Comecei um novo projeto": cria de uma vez os funis do tipo de projeto, com a chave nas campanhas. Só o gestor. */
  criarProjeto(tipo: TipoProjeto, nome: string, agrupadorId: string, produto: ProdutoKey): Promise<Resultado & { funilIds?: string[] }>;
  /** Cria ou edita um motivo de perda. Os de fábrica só mudam nota e ativo. Só o gestor. */
  salvarMotivoPerda(m: MotivoPerdaConfig): Promise<Resultado>;

  /** Move para uma etapa do funil do negócio (id da etapa personalizada). */
  moverEtapa(negocioId: string, etapaId: string): Promise<Resultado>;
  salvarCampos(negocioId: string, campos: Partial<Record<CampoKey, string>>): Promise<Resultado>;
  marcarPerdido(negocioId: string, motivo: MotivoPerda, nota: string): Promise<Resultado>;
  /** Só o gestor troca dono, com nota explicando o motivo (playbook, seção 5.1, regra 4). */
  transferirDono(negocioId: string, novoDonoId: string, motivo: string): Promise<Resultado>;
  /** Negócio novo na primeira etapa do funil. Devolve quem virou dono (distribuição do funil ou geral). */
  criarNegocio(contatoId: string, funilId: string, campanhaId?: string | null): Promise<Resultado & { negocioId?: string; donoId?: string | null }>;
  /** Gestor define o dono de um contato sem dono (ex.: conversa que caiu em "não atribuídos"). */
  atribuirContato(contatoId: string, donoId: string, motivo: string): Promise<Resultado>;

  criarAtividade(a: NovaAtividade): Promise<Resultado>;
  concluirAtividade(atividadeId: string, resultado: string): Promise<Resultado>;
  adicionarNota(contatoId: string, negocioId: string | null, texto: string): Promise<Resultado>;

  /** Com template, o texto é montado no banco ({{1}} = primeiro nome) e `texto` é ignorado. */
  enviarMensagem(contatoId: string, texto: string, templateId?: string | null): Promise<Resultado & { mensagemId?: string }>;
  marcarConversaLida(contatoId: string): Promise<Resultado>;

  atualizarItemFila(filaId: string, itemId: string, status: StatusFila): Promise<Resultado>;

  /** Quantidade e suprimidos voltam contados pelo banco. */
  salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<ResultadoFicha>;
  decidirFicha(fichaId: string, aprovar: boolean): Promise<Resultado>;

  salvarDistribuicao(percentuais: Record<string, { percentual: number; ativo: boolean }>): Promise<Resultado>;
  /** Devolve o link pronto (oferta vigente + sck + UTMs). */
  criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<ResultadoLink>;

  // ── Painel personalizável (por pessoa) ──
  painel(vendedorId: string): Promise<PainelPessoa>;
  salvarPainel(p: PainelPessoa): Promise<Resultado>;

  // ── Notificações (sininho + desktop) ──
  /** Notificações de quem está na sessão, mais recentes primeiro. */
  notificacoes(): Promise<Notificacao[]>;
  marcarNotificacoesLidas(ids?: string[]): Promise<Resultado>;
  preferenciasNotificacao(): Promise<PreferenciasNotificacao>;
  salvarPreferenciasNotificacao(p: PreferenciasNotificacao): Promise<Resultado>;

  // ── Produtos e ofertas (espelho da Hotmart) ──
  /** Produtos sincronizados da Hotmart (vinculados ou não ao comercial). */
  produtosHotmart(): Promise<ProdutoHotmart[]>;
  /** Ofertas da Hotmart, de um produto ou todas. */
  ofertas(produtoId?: string): Promise<OfertaHotmart[]>;
  /** Códigos de oferta vendidos que não estão no catálogo. */
  ofertasOrfas(): Promise<OfertaOrfa[]>;
  /** Acha produto e oferta a partir do link de checkout ou do código colado (pay.hotmart.com/X?off=Y). */
  buscarPorLinkHotmart(linkOuCodigo: string): Promise<{ produto: ProdutoHotmart | null; oferta: OfertaHotmart | null; codigo: string | null }>;
  /** Vincula (ou atualiza) o produto ao comercial. Só o gestor. */
  vincularProduto(p: Pick<ProdutoHotmart, 'produtoId' | 'noComercial' | 'nomeComercial' | 'produtoKey' | 'agrupadorId' | 'escada'>): Promise<Resultado>;
  /** Dados do comercial na oferta (vigente, condição, validade, uso). Só o gestor. */
  salvarOferta(o: Pick<OfertaHotmart, 'codigo' | 'vigente' | 'condicao' | 'validaAte' | 'uso'>): Promise<Resultado>;

  // ── Dashboards (Relatórios) ──
  /** Dashboards meus + compartilhados. */
  dashboards(): Promise<Dashboard[]>;
  salvarDashboard(d: Dashboard): Promise<Resultado & { dashboardId?: string }>;
  excluirDashboard(id: string): Promise<Resultado>;

  // ── Registro do CRM ──
  /** Log de toda manipulação (mais recente primeiro). O backend grava por trigger; a tela só lê. */
  log(filtro?: FiltroLog): Promise<LogCrm[]>;

  // ── Integração Hotmart (F3) — só o gestor ──
  /** Painel da integração nos últimos `dias` (1 a 90). Quem não é gestor recebe erro (nunca painel zerado). */
  hotmartPainel(dias: number): Promise<PainelHotmart>;
  /** Refaz um evento que deu erro (só com a integração ligada). */
  reprocessarHotmart(chave: string): Promise<Resultado>;

  // ── MCP (F7): tokens pessoais para conectar o Claude ──
  /** Os meus tokens (gestor: os do time todo). */
  tokensMcp(): Promise<TokenMcp[]>;
  /** Cria token para quem está na sessão. `ler` é sempre incluído; validade de 1 a 180 dias. */
  criarTokenMcp(nome: string, escopos: EscopoMcp[], dias: number): Promise<ResultadoTokenMcp>;
  /** Revoga (o próprio ou, para o gestor, qualquer um). Funciona com o MCP desligado. */
  revogarTokenMcp(id: string): Promise<Resultado>;

  /** Só para a demonstração: trocar quem está olhando. O backend real ignora (vem do login). */
  verComo?(vendedorId: string): Promise<void>;
}
