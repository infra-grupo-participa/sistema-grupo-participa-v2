// Tipos do CRM do Comercial. Domínio puro: sem Next, sem Supabase.
//
// Fonte das regras: gp-operacoes/departamentos/comercial/playbook.md (v1, 26/09/2026). Os nomes seguem o
// playbook (etapas no infinitivo, 9 motivos de perda, campos obrigatórios por etapa). Quando o backend
// existir, as tabelas espelham estes tipos; o front não muda.

/** Produto vendido = "agrupador" na Clint. Um funil "Venda ativa" por produto. */
export type ProdutoKey = 'ht' | 'hm' | 'aurum' | 'sv' | 'acelera' | 'ethb';

/** Escada A = serviço do escritório (cliente final). Escada B = infoproduto (profissional). Nunca misturar. */
export type Escada = 'A' | 'B';

export interface Produto {
  key: ProdutoKey;
  nome: string;
  escada: Escada;
  /** Preço de referência para o card; o preço vigente mora em produtos-e-ofertas/. */
  ticket: number;
}

/**
 * Origem do negócio. `venda_ativa` é onde o comercial trabalha; as demais nascem sozinhas pela Hotmart
 * (playbook, seção 4.1).
 */
export type OrigemTipo =
  | 'venda_ativa'
  | 'carrinho_abandonado'
  | 'compra_em_aberto'
  | 'cartao_recusado'
  | 'compra_aprovada'
  | 'expirada'
  | 'reembolso';

/** Etapas da origem "Venda ativa" (playbook, seção 4.2). */
export type EtapaKey =
  | 'primeiro_contato'
  | 'qualificar'
  | 'apresentar_oferta'
  | 'negociar'
  | 'aguardar_pagamento'
  | 'fechado';

/** Campos do negócio (playbook, seção 4.3). No máximo oito. */
export type CampoKey =
  | 'perfil_profissional'
  | 'atua_com_holding'
  | 'produto_interesse'
  | 'origem'
  | 'objecao_principal'
  | 'forma_pagamento';

export interface Etapa {
  key: EtapaKey;
  label: string;
  /** O que acontece aqui. */
  descricao: string;
  /** Critério para passar para a próxima. */
  criterio: string;
  /** Alerta de tempo parado na etapa, em minutos. null = sem alerta. */
  slaAtencaoMin: number | null;
  slaCriticoMin: number | null;
  /** Campos que precisam estar preenchidos para ENTRAR nesta etapa. */
  camposObrigatorios: CampoKey[];
}

/** Os 9 motivos de fábrica (playbook, seção 4.4). O gestor cadastra outros: ver `MotivoPerdaConfig`. */
export type MotivoPerdaPadrao =
  | 'fora_do_perfil'
  | 'tentativas_esgotadas'
  | 'sem_interesse'
  | 'nao_e_o_momento'
  | 'sem_condicao_financeira'
  | 'comprou_outro_produto'
  | 'contato_invalido'
  | 'pediu_sem_contato'
  | 'ja_atendido_outro_vendedor';

/** Chave de um motivo de perda (padrão ou cadastrado). Motivo fora do cadastro não existe. */
export type MotivoPerda = MotivoPerdaPadrao | (string & {});

/** Motivo de perda cadastrado. Os de fábrica (`sistema`) não podem ser apagados, só desativados. */
export interface MotivoPerdaConfig {
  key: MotivoPerda;
  label: string;
  /** Volta para a fila de reativação na próxima oferta. */
  reativa: boolean;
  /** Vai para a lista de bloqueio (não recebe mais contato). */
  bloqueia: boolean;
  /** Mede falha de processo (ex.: distribuição): o gestor é avisado no mesmo dia. */
  alertaGestor: boolean;
  nota: string | null;
  sistema: boolean;
  ativo: boolean;
}

export type StatusNegocio = 'aberto' | 'ganho' | 'perdido';

export type PapelComercial = 'gestor' | 'vendedor';

export interface Vendedor {
  id: string;
  nome: string;
  /** Sigla usada no SCK dos links rastreáveis (playbook, seção 8). */
  sigla: string;
  papel: PapelComercial;
  ativo: boolean;
  /** Percentual na distribuição automática (0–100). Soma dos ativos = 100. */
  percentual: number;
  /** Pode operar disparo por API (com ficha aprovada). */
  disparaApi: boolean;
}

export type PerfilProfissional = 'advogado' | 'contador' | 'outro';
export type AtuaComHolding = 'sim' | 'nao' | 'comecando';

export interface Utm {
  source?: string | null;
  medium?: string | null;
  campaign?: string | null;
  content?: string | null;
  sck?: string | null;
}

/** Pessoa única do CRM. Chave de identidade: e-mail OU últimos 8 dígitos do telefone. */
export interface Contato {
  id: string;
  nome: string;
  email: string | null;
  telefone: string | null;
  cidade: string | null;
  uf: string | null;
  perfil: PerfilProfissional | null;
  atuaComHolding: AtuaComHolding | null;
  /** Dono do contato. Contato com dono mantém o dono em negócio novo (playbook, seção 5.1). */
  donoId: string | null;
  tags: string[];
  utm: Utm;
  /** Score de recuperação 0–100 (modelo do Acelera). null = não calculado. */
  score: number | null;
  ehAluno: boolean;
  /** Pediu para não receber contato: entra na lista de bloqueio. */
  optOut: boolean;
  criadoEm: string;
}

export interface ProximaAtividade {
  id: string;
  tipo: TipoAtividade;
  titulo: string;
  venceEm: string;
}

export interface Negocio {
  id: string;
  contatoId: string;
  produto: ProdutoKey;
  origem: OrigemTipo;
  /** Funil (origem, na Clint) onde o negócio está. */
  funilId: string;
  /** Campanha de entrada que trouxe o negócio, quando houver. */
  campanhaId: string | null;
  /** Etapa personalizada do funil (id). */
  etapaId: string;
  /** Nome da etapa personalizada (desnormalizado para listas). */
  etapaNome: string;
  /**
   * PAPEL da etapa no playbook. Toda etapa personalizada declara um papel, e as regras da casa valem por ele:
   * negociação entra na supressão de disparo, ganho só com pagamento aprovado etc.
   */
  etapa: EtapaKey;
  /**
   * Alerta de tempo da etapa personalizada (minutos). null = etapa sem alerta.
   * Ausente = vale o alerta padrão do playbook para o papel da etapa.
   */
  sla?: { atencaoMin: number; criticoMin: number } | null;
  status: StatusNegocio;
  donoId: string | null;
  valor: number;
  campos: Partial<Record<CampoKey, string>>;
  motivoPerda: MotivoPerda | null;
  criadoEm: string;
  /** Quando entrou na etapa atual — base do alerta de tempo. */
  etapaDesde: string;
  fechadoEm: string | null;
  proximaAtividade: ProximaAtividade | null;
  ultimaInteracaoEm: string | null;
}

export type TipoAtividade = 'whatsapp' | 'ligacao' | 'email' | 'tarefa' | 'reuniao';

export interface Atividade {
  id: string;
  negocioId: string | null;
  contatoId: string;
  donoId: string;
  tipo: TipoAtividade;
  titulo: string;
  venceEm: string;
  concluidaEm: string | null;
  resultado: string | null;
  /** Dia da cadência padrão (1–5), quando a atividade veio dela. */
  cadenciaDia: number | null;
}

export type DirecaoMensagem = 'entrada' | 'saida';
export type StatusMensagem = 'enviada' | 'entregue' | 'lida' | 'falhou';
export type CanalMensagem = 'whatsapp' | 'email' | 'nota';

export interface Mensagem {
  id: string;
  contatoId: string;
  canal: CanalMensagem;
  direcao: DirecaoMensagem;
  texto: string;
  em: string;
  status: StatusMensagem | null;
  autorId: string | null;
  /** Template aprovado usado (fora da janela de 24h só sai template). */
  templateId: string | null;
}

export interface Conversa {
  contatoId: string;
  ultimaMensagem: Mensagem;
  naoLidas: number;
  /** Fim da janela de 24h aberta pela última mensagem do lead. null = fechada. */
  janelaAteEm: string | null;
  atribuidaA: string | null;
}

export type TipoEvento =
  | 'criado'
  | 'etapa'
  | 'dono'
  | 'mensagem'
  | 'ligacao'
  | 'nota'
  | 'compra'
  | 'checkout'
  | 'pesquisa'
  | 'grupo'
  | 'disparo'
  | 'perdido'
  | 'ganho';

export interface EventoTimeline {
  id: string;
  contatoId: string;
  negocioId: string | null;
  tipo: TipoEvento;
  titulo: string;
  detalhe: string | null;
  em: string;
  autorId: string | null;
}

// ── Construtor de funis (modelo da Clint: agrupador → funil/origem → etapas + campanhas) ──

/** Pasta de funis, normalmente um produto (ex.: Holding Masters). */
export interface Agrupador {
  id: string;
  nome: string;
  produto: ProdutoKey | null;
  ordem: number;
}

/** Cor da etapa: só tokens do tema (proibido hex). */
export type CorEtapa = 'neutral' | 'accent' | 'info' | 'cyan' | 'purple' | 'yellow' | 'green' | 'red';

export interface EtapaFunil {
  id: string;
  nome: string;
  /** Papel no playbook (ver Negocio.etapa). Exatamente uma etapa com papel 'fechado', e ela é a última. */
  papel: EtapaKey;
  cor: CorEtapa;
  slaAtencaoMin: number | null;
  slaCriticoMin: number | null;
  /** Campos exigidos para ENTRAR nesta etapa. */
  camposObrigatorios: CampoKey[];
  /** Critério para passar para a próxima (texto para o vendedor). */
  criterio: string;
}

/** Por onde o lead entra no funil. */
export type CanalCampanha = 'utm' | 'formulario' | 'disparo' | 'hotmart' | 'webhook' | 'manual';

export interface Campanha {
  id: string;
  nome: string;
  canal: CanalCampanha;
  /** Regra de entrada legível (ex.: utm_campaign = ht33-meteorico; evento = Carrinho abandonado). */
  regra: string;
  ativa: boolean;
  criadoEm: string;
}

/** `manual` = o comercial trabalha (Venda ativa); `hotmart` = nasce sozinho de eventos do checkout. */
export type TipoFunil = 'manual' | 'hotmart';

export interface Funil {
  id: string;
  nome: string;
  /** Ícone escolhido (nome do mapa de `shared/ui/icons.tsx`). */
  icone: string;
  /** Chave do projeto quando o funil nasceu de "Comecei um novo projeto" (ex.: ht34-meteorico). */
  projeto: string | null;
  agrupadorId: string;
  produto: ProdutoKey;
  tipo: TipoFunil;
  /** Eventos da Hotmart que criam negócio neste funil (só tipo hotmart). */
  eventosHotmart: OrigemTipo[];
  etapas: EtapaFunil[];
  campanhas: Campanha[];
  /** Distribuição própria do funil. null = usa a distribuição geral do Comercial. */
  distribuicao: { vendedorId: string; percentual: number }[] | null;
  ativo: boolean;
  criadoEm: string;
}

// ── Fila de recuperação pós-lançamento (processo montar-fila-de-recuperacao.md) ──

export type FaixaScore = 'A' | 'B' | 'C' | 'D';

export type StatusFila =
  | 'a_abordar'
  | 'tentando_contato'
  | 'em_conversa'
  | 'vai_comprar'
  | 'ganho'
  | 'sem_resposta'
  | 'declinou'
  | 'sem_interesse'
  | 'numero_invalido';

export type SinalRecuperacao =
  | 'boleto_aberto'
  | 'carrinho'
  | 'cartao_recusado'
  | 'ficha_completa'
  | 'senhas'
  | 'chat'
  | 'workbook'
  | 'apostila'
  | 'pesquisa'
  | 'comunidade'
  | 'grupo'
  | 'advogado_contador'
  | 'quer_parceria'
  | 'respondeu_sem_retorno';

export interface ItemFila {
  id: string;
  contatoId: string;
  score: number;
  faixa: FaixaScore;
  sinais: SinalRecuperacao[];
  status: StatusFila;
  responsavelId: string | null;
  alteradoPor: string | null;
  alteradoEm: string | null;
}

export interface FilaRecuperacao {
  id: string;
  nome: string;
  produto: ProdutoKey;
  criadaEm: string;
  /** Oferta disponível hoje: sem ela, não se aborda (fechamento/playbook.md, seção 3). */
  ofertaVigente: string | null;
  itens: ItemFila[];
}

// ── Disparo por API (playbook, seção 7) ──

export type StatusFicha = 'rascunho' | 'aguardando_aprovacao' | 'aprovada' | 'reprovada' | 'enviada';

export type Supressao = 'em_negociacao' | 'disparo_48h' | 'opt_out' | 'ja_comprou';

export interface Template {
  id: string;
  nome: string;
  categoria: 'marketing' | 'utility';
  texto: string;
  aprovado: boolean;
}

export interface FichaDisparo {
  id: string;
  /** Mesmo código no template, no log e no utm_content. */
  codigo: string;
  objetivo: string;
  produto: ProdutoKey;
  /** Descrição do filtro da lista. */
  filtro: string;
  quantidade: number;
  supressoes: Supressao[];
  suprimidos: number;
  templateId: string;
  numeroEnvio: string;
  agendadoPara: string;
  operadorId: string;
  link: string;
  status: StatusFicha;
  aprovadoPor: string | null;
  criadoEm: string;
  resultado: { entregues: number; lidas: number; respostas: number; falhas: number } | null;
}

// ── Configuração ──

export interface LinkRastreavel {
  id: string;
  vendedorId: string;
  produto: ProdutoKey;
  acao: string;
  url: string;
  sck: string;
}

export interface ConfigComercial {
  /** Horário de contato com lead (a definir pelo Jonathan; proposta do playbook). */
  horarioContato: string;
  /** Limite de negócios abertos por vendedor (a definir depois de 30 dias de dado). */
  limiteNegociosAbertos: number | null;
}

/** Quem está olhando a tela: decide o que aparece como "meu". */
export interface SessaoComercial {
  vendedorId: string;
  papel: PapelComercial;
}

// ── Jornada da pessoa: tudo o que a pessoa fez com a empresa, em ordem ──

export type TipoPontoJornada =
  | 'inscricao'     // entrou num lançamento/captação (com a UTM daquela entrada)
  | 'lista'         // entrou numa lista (ActiveCampaign)
  | 'pesquisa'      // respondeu pesquisa ou formulário (MQL)
  | 'grupo'         // entrou ou saiu de grupo de WhatsApp
  | 'presenca'      // assistiu aula/evento
  | 'checkout'      // foi ao checkout, abandonou, boleto/Pix gerado, cartão recusado
  | 'compra'        // pagamento aprovado
  | 'reembolso'     // pediu reembolso, chargeback
  | 'negocio'       // negócio criado, mudou de etapa, ganho, perdido
  | 'conversa'      // mensagem, ligação
  | 'disparo'       // recebeu disparo
  | 'nota';         // nota interna

export type FonteJornada =
  | 'activecampaign' | 'hotmart' | 'respondi' | 'sendflow' | 'crm' | 'infobip' | 'unnichat' | 'manychat'
  | 'formulario' | 'youtube' | 'instagram';

export interface PontoJornada {
  id: string;
  contatoId: string;
  tipo: TipoPontoJornada;
  em: string;
  titulo: string;
  detalhe: string | null;
  fonte: FonteJornada;
  /** Chave do lançamento/projeto a que o ponto pertence (ex.: imersao-ht-set26). */
  lancamento: string | null;
  produto: ProdutoKey | null;
  /** UTM DAQUELA entrada: a mesma pessoa chega por campanhas diferentes em lançamentos diferentes. */
  utm: Utm | null;
  valor: number | null;
  negocioId: string | null;
}

// ── Modelos de funil e projetos ──

export type TipoProjeto =
  | 'lancamento_classico' | 'lancamento_meteorico' | 'webinar_perpetuo' | 'seminario' | 'evento_presencial' | 'ascensao_aluno';

export interface ModeloFunil {
  id: string;
  nome: string;
  descricao: string;
  icone: string;
  tipo: TipoFunil;
  eventosHotmart: OrigemTipo[];
  etapas: Omit<EtapaFunil, 'id'>[];
  /** Campanhas sugeridas; `{chave}` vira a chave do projeto. */
  campanhas: Omit<Campanha, 'id' | 'criadoEm'>[];
}

export interface ModeloProjeto {
  tipo: TipoProjeto;
  nome: string;
  descricao: string;
  icone: string;
  /** Ids de `ModeloFunil`, na ordem em que os funis aparecem. */
  funis: string[];
  /** Boas práticas para o começo do projeto. */
  checklist: string[];
}

// ── Painel personalizável (por pessoa) ──

export type MetricaKey =
  | 'abordados' | 'responderam' | 'entraram_contato' | 'em_negociacao' | 'vendas' | 'receita'
  | 'abertos' | 'criticos' | 'sem_proximo' | 'sem_dono' | 'atrasadas' | 'tempo_primeiro_contato'
  | 'conversao' | 'perdidos';

export type VisualWidget = 'numero' | 'barras' | 'linha' | 'pizza' | 'lista';
export type PeriodoWidget = 'hoje' | '7d' | '30d' | 'mes';
export type AgrupamentoWidget = 'nenhum' | 'dia' | 'vendedor' | 'produto' | 'etapa' | 'motivo' | 'funil';

export interface WidgetPainel {
  id: string;
  titulo: string;
  metrica: MetricaKey;
  visual: VisualWidget;
  periodo: PeriodoWidget;
  agrupar: AgrupamentoWidget;
  /** Largura em colunas (grade de 4). */
  largura: 1 | 2 | 3 | 4;
  /** Filtro opcional por funil. */
  funilId: string | null;
}

export interface PainelPessoa {
  vendedorId: string;
  widgets: WidgetPainel[];
}

// ── Notificações ──

export type GatilhoNotificacao = 'lead_novo' | 'lead_respondeu' | 'prazo_estourado' | 'venda_aprovada' | 'ficha_para_aprovar' | 'atividade_vencendo';

export interface PreferenciasNotificacao {
  vendedorId: string;
  desktop: boolean;
  gatilhos: Record<GatilhoNotificacao, boolean>;
  /** Silêncio fora do horário (ex.: 20h às 8h). */
  silencioInicio: string | null;
  silencioFim: string | null;
}

export interface Notificacao {
  id: string;
  vendedorId: string;
  gatilho: GatilhoNotificacao;
  titulo: string;
  corpo: string;
  /** Para onde o clique leva. */
  href: string;
  em: string;
  lida: boolean;
}
