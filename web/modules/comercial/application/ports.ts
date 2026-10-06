// Contrato entre as telas do Comercial e a fonte de dados.
//
// Hoje quem cumpre é `MockComercialRepository` (dados de demonstração em memória). Quando o backend existir,
// entra um `SupabaseComercialRepository` com a MESMA interface e as telas não mudam: trocar em
// `ui/repositorio.ts`. As regras que travam escrita (campos obrigatórios, ganho só com pagamento, troca de dono
// só pelo gestor, ficha aprovada antes do disparo) precisam ser repetidas no banco (RPC SECURITY DEFINER).
import type {
  Agrupador, Atividade, CampoKey, ConfigComercial, Contato, Conversa, EventoTimeline, FichaDisparo, FilaRecuperacao,
  Funil, LinkRastreavel, Mensagem, MotivoPerda, MotivoPerdaConfig, Negocio, Notificacao, PainelPessoa, PontoJornada,
  PreferenciasNotificacao, ProdutoKey, SessaoComercial, StatusFila, Template, TipoAtividade, TipoProjeto, Vendedor,
} from '../domain/types';

export interface Resultado {
  ok: boolean;
  msg?: string;
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
  filtro: string;
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

  enviarMensagem(contatoId: string, texto: string, templateId?: string | null): Promise<Resultado>;
  marcarConversaLida(contatoId: string): Promise<Resultado>;

  atualizarItemFila(filaId: string, itemId: string, status: StatusFila): Promise<Resultado>;

  salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<Resultado>;
  decidirFicha(fichaId: string, aprovar: boolean): Promise<Resultado>;

  salvarDistribuicao(percentuais: Record<string, { percentual: number; ativo: boolean }>): Promise<Resultado>;
  criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<Resultado>;

  // ── Painel personalizável (por pessoa) ──
  painel(vendedorId: string): Promise<PainelPessoa>;
  salvarPainel(p: PainelPessoa): Promise<Resultado>;

  // ── Notificações (sininho + desktop) ──
  /** Notificações de quem está na sessão, mais recentes primeiro. */
  notificacoes(): Promise<Notificacao[]>;
  marcarNotificacoesLidas(ids?: string[]): Promise<Resultado>;
  preferenciasNotificacao(): Promise<PreferenciasNotificacao>;
  salvarPreferenciasNotificacao(p: PreferenciasNotificacao): Promise<Resultado>;

  /** Só para a demonstração: trocar quem está olhando. O backend real ignora (vem do login). */
  verComo?(vendedorId: string): Promise<void>;
}
