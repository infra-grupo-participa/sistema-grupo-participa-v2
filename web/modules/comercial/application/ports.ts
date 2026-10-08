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
import type { FiltroContatos, PaginaContatos, ResumoContatos } from '../domain/contatos';
import type { OrigemDetalhada, PainelCatalogo, RegraCatalogo } from '../domain/catalogacao';
import type { EdicaoAtivacao, PainelAtivacao } from '../domain/ativacao';
import type { PainelCanais } from '../domain/canais-whatsapp';
import type { PainelIntegracoes } from '../domain/integracoes-status';

export interface Resultado {
  ok: boolean;
  msg?: string;
}

/** Envio de WhatsApp. `repetida` = a chave de idempotência já tinha virado mensagem (nada novo foi enfileirado). */
export interface ResultadoEnvio extends Resultado {
  mensagemId?: string;
  repetida?: boolean;
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

export interface FiltroNegocios {
  contatoId?: string;
  funilId?: string;
  status?: Negocio['status'];
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

  /**
   * Lista INTEIRA de contatos visíveis. Pesada (lotes de 500): só para telas que precisam da base toda (Disparos,
   * Performance da equipe). Lista da tela Contatos: `contatosPagina`; nome dos contatos mostrados: `contatosPorIds`.
   */
  contatos(): Promise<Contato[]>;
  /** Uma página da tela Contatos, com filtros e ordem no servidor (`crm_contatos_pagina`, migration 20261006m). */
  contatosPagina(filtro: FiltroContatos): Promise<PaginaContatos>;
  /** Números do topo da tela Contatos e opções de UF/tags (`crm_contatos_resumo`). */
  contatosResumo(): Promise<ResumoContatos>;
  /**
   * Contatos pelo id, com a visibilidade e a máscara da busca (`crm_contatos_por_ids`). O que a pessoa não vê não
   * volta. Para fichas e telas que só precisam dos contatos dos negócios/atividades/conversas que mostram.
   */
  contatosPorIds(ids: string[]): Promise<Contato[]>;
  /** Outros contatos com a mesma chave de telefone (DDD + últimos 8 dígitos), para o aviso da ficha. */
  duplicadosDe(contatoId: string): Promise<Contato[]>;
  /**
   * Busca no servidor por nome, e-mail ou telefone (mínimo 3 caracteres; até 50). Alcança contatos que não vêm na
   * lista do vendedor (sem dono e sem negócio aberto, migration 20261006191824), com a mesma máscara de e-mail/telefone.
   */
  buscarContatos(texto: string): Promise<Contato[]>;
  /**
   * Jornada completa da pessoa com a empresa: inscrições (cada uma com a UTM daquela entrada), listas, pesquisas,
   * grupos, presença, checkout, compras, reembolsos, negócios e conversas. Do mais recente para o mais antigo.
   */
  jornada(contatoId: string): Promise<PontoJornada[]>;
  /** Sem filtro: todos os visíveis. `contatoId`/`funilId`/`status` filtram no banco (`crm_negocios`). */
  negocios(filtro?: FiltroNegocios): Promise<Negocio[]>;
  atividades(): Promise<Atividade[]>;
  /** Linha do tempo de um contato (todos os negócios dele). Sem id: todos os eventos (fechamento do dia). */
  eventos(contatoId?: string): Promise<EventoTimeline[]>;

  conversas(): Promise<Conversa[]>;
  mensagens(contatoId: string): Promise<Mensagem[]>;
  templates(): Promise<Template[]>;
  /** Interruptores e limites do WhatsApp (sem dado de pessoa). */
  whatsappStatus(): Promise<StatusWhatsapp>;
  /** Números de WhatsApp do CRM (oficial + conectados por QR), com status e limites anti-ban (20261008152212). */
  canais(): Promise<PainelCanais>;
  /** Nome, dono, recebe/envia de um número. Só o gestor. */
  salvarCanal(canalId: string, dados: { nome?: string; donoId?: string | null; recebe?: boolean; envia?: boolean; ativo?: boolean }): Promise<Resultado>;

  filas(): Promise<FilaRecuperacao[]>;
  fichas(): Promise<FichaDisparo[]>;
  links(): Promise<LinkRastreavel[]>;

  // ── Escrita ──
  /** Cria ou atualiza um funil (id vazio = novo). Valida com `validarFunil`. Só o gestor. */
  salvarFunil(f: Funil): Promise<Resultado & { funilId?: string }>;
  /** Arquiva (some da lista). Com negócio aberto, só com `comAbertos`: os negócios ficam ocultos até desarquivar. */
  arquivarFunil(funilId: string, comAbertos?: boolean): Promise<Resultado>;
  criarAgrupador(nome: string, produto: ProdutoKey | null): Promise<Resultado & { agrupadorId?: string }>;
  /** "Comecei um novo projeto": cria de uma vez os funis do tipo de projeto, com a chave nas campanhas. Só o gestor. */
  criarProjeto(tipo: TipoProjeto, nome: string, agrupadorId: string, produto: ProdutoKey): Promise<Resultado & { funilIds?: string[] }>;
  // ── Ativação padrão (migration 20261007135415) ──
  /** Projetos com a ativação: cadastro, negócios por etapa (vendedor: só os dele), carga do dia e avisos. */
  ativacao(): Promise<PainelAtivacao>;
  /** Datas do evento e as entradas (listas/tags do AC, ingresso e oferta da Hotmart, formulário). Só o gestor. Reagenda os toques. */
  salvarAtivacao(e: EdicaoAtivacao): Promise<Resultado>;
  /** Acrescenta o funil de Ativação a um projeto criado antes dela. Só o gestor. */
  garantirAtivacao(projeto: string): Promise<Resultado & { funilId?: string }>;
  /** Encerra a ativação: quem não comprou vira perdido "Evento encerrado sem compra" e vai para a fila de recuperação com o mesmo dono. Só o gestor. */
  encerrarAtivacao(projeto: string): Promise<Resultado>;
  /** Cria ou edita um motivo de perda. Os de fábrica só mudam nota e ativo. Só o gestor. */
  salvarMotivoPerda(m: MotivoPerdaConfig): Promise<Resultado>;

  // ── Catalogação de origem (migration 20261007141044) ──
  /** Regras, listas do AC, projetos, números e valores sem regra. Todos do Comercial leem; `podeEditar` = gestor. */
  catalogo(): Promise<PainelCatalogo>;
  /** Cria (id null) ou edita uma regra; desativar = `ativo: false` (nada se apaga). Só o gestor. */
  salvarRegraCatalogo(r: RegraCatalogo): Promise<Resultado & { id?: number }>;
  /** Nome de uma lista do ActiveCampaign (o webhook só manda o id). Só o gestor. */
  salvarListaAc(id: string, nome: string): Promise<Resultado>;
  /** Reaplica as regras aos contatos sem projeto (ou a todos). Projeto definido à mão não muda. Só o gestor. */
  reaplicarCatalogo(todos?: boolean): Promise<Resultado & { catalogados?: number }>;
  /** "Como entrou" da ficha (null = contato sem origem registrada). */
  origemContato(contatoId: string): Promise<OrigemDetalhada | null>;
  /** Gestor define o projeto do contato à mão; null = volta a seguir as regras. */
  definirProjetoContato(contatoId: string, projeto: string | null): Promise<Resultado>;

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
  /** `chave` = idempotência: a mesma chave devolve a mesma mensagem (repetida) sem duplicar. */
  /** `canalId` = número por onde sai (vazio = o da conversa mais recente; senão o oficial). */
  enviarMensagem(contatoId: string, texto: string, templateId?: string | null, chave?: string | null, canalId?: string | null): Promise<ResultadoEnvio>;
  marcarConversaLida(contatoId: string): Promise<Resultado>;
  /**
   * Imagem (JPG/PNG/WebP até 5 MB) ou PDF (até 16 MB) com legenda opcional: sobe para o bucket privado e enfileira
   * (janela de 24 h aberta; o banco valida dono, tipo e tamanho de novo).
   */
  enviarAnexo(contatoId: string, arquivo: File, legenda: string, chave?: string | null, canalId?: string | null): Promise<ResultadoEnvio>;
  /**
   * Áudio gravado no navegador (20261007s), já no formato final (ogg/opus = nota de voz; m4a/aac/mp3 = áudio comum):
   * sobe para o bucket privado e enfileira sem legenda (janela de 24 h aberta; o banco valida dono, tipo e tamanho).
   */
  enviarAudio(contatoId: string, audio: Blob, formato: { mime: string; ext: string }, chave?: string | null, canalId?: string | null): Promise<ResultadoEnvio>;
  /** URL assinada de curta duração (10 min) do arquivo de uma mensagem; null = sem acesso ou indisponível. */
  urlMidia(caminho: string): Promise<string | null>;

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

  // ── Status vivo das integrações (aba Integrações) — gestor, vendedor e leitor ──
  /** Fatos de cada integração (chave, credencial, último evento, 24 h, erro) e os números de WhatsApp. Selo: domain/integracoes-status. */
  integracoesStatus(): Promise<PainelIntegracoes>;

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
