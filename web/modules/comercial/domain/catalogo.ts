// Vocabulário fixo do Comercial: produtos, origens, etapas, campos, motivos. Fonte: playbook do Comercial.
// Rótulos e tons de apresentação moram aqui para toda tela usar a mesma palavra.
import type { Tone } from '@/shared/ui/components';
import type {
  AtuaComHolding, CampoKey, MotivoPerdaConfig, Etapa, EtapaKey, FaixaScore, MotivoPerda, OrigemTipo, PerfilProfissional, Produto,
  ProdutoKey, SinalRecuperacao, StatusFicha, StatusFila, Supressao, TipoAtividade,
} from './types';

export const PRODUTOS: Produto[] = [
  { key: 'ht', nome: 'Holding Total', escada: 'B', ticket: 297 },
  { key: 'acelera', nome: 'Acelera Holding', escada: 'B', ticket: 2997 },
  { key: 'hm', nome: 'Holding Masters', escada: 'B', ticket: 30000 },
  { key: 'aurum', nome: 'Aurum', escada: 'B', ticket: 100000 },
  { key: 'ethb', nome: 'ETHB', escada: 'B', ticket: 997 },
  { key: 'sv', nome: 'Sessão de Viabilidade', escada: 'A', ticket: 1200 },
];

export function produto(key: ProdutoKey): Produto {
  return PRODUTOS.find((p) => p.key === key) ?? PRODUTOS[0];
}

export const ROTULO_ORIGEM: Record<OrigemTipo, string> = {
  venda_ativa: 'Venda ativa',
  carrinho_abandonado: 'Carrinho abandonado',
  compra_em_aberto: 'Compra em aberto',
  cartao_recusado: 'Cartão recusado',
  compra_aprovada: 'Compra aprovada',
  expirada: 'Expirada',
  reembolso: 'Reembolso',
};

/** Origens que a integração com a Hotmart cria sozinha. */
export const ORIGENS_HOTMART: OrigemTipo[] = [
  'carrinho_abandonado', 'compra_em_aberto', 'cartao_recusado', 'compra_aprovada', 'expirada', 'reembolso',
];

const H = 60;
const D = 24 * H;

export const ETAPAS: Etapa[] = [
  {
    key: 'primeiro_contato', label: 'Fazer primeiro contato',
    descricao: 'Lead chegou, já com dono. Abordagem pela cadência.',
    criterio: 'O lead respondeu',
    slaAtencaoMin: 5, slaCriticoMin: 15, camposObrigatorios: [],
  },
  {
    key: 'qualificar', label: 'Qualificar',
    descricao: 'Conversa em andamento. Entender perfil, momento e interesse.',
    criterio: 'Campos de qualificação preenchidos',
    slaAtencaoMin: 24 * H, slaCriticoMin: 48 * H,
    camposObrigatorios: ['perfil_profissional', 'atua_com_holding', 'produto_interesse'],
  },
  {
    key: 'apresentar_oferta', label: 'Apresentar a oferta',
    descricao: 'Ligação ou conversa de diagnóstico, oferta ligada à dor.',
    criterio: 'Oferta apresentada e lead pediu condição ou link',
    slaAtencaoMin: 48 * H, slaCriticoMin: 72 * H, camposObrigatorios: [],
  },
  {
    key: 'negociar', label: 'Negociar',
    descricao: 'Proposta e link enviados, objeções em tratamento.',
    criterio: 'Lead escolheu a forma de pagamento',
    slaAtencaoMin: 72 * H, slaCriticoMin: 7 * D, camposObrigatorios: ['objecao_principal'],
  },
  {
    key: 'aguardar_pagamento', label: 'Aguardar pagamento',
    descricao: 'Boleto, Pix ou checkout em andamento.',
    criterio: 'Pagamento aprovado na Hotmart',
    slaAtencaoMin: 24 * H, slaCriticoMin: 48 * H, camposObrigatorios: ['forma_pagamento'],
  },
  {
    key: 'fechado', label: 'Fechado',
    descricao: 'Ganho só com pagamento aprovado. Passagem para a Educação.',
    criterio: '',
    slaAtencaoMin: null, slaCriticoMin: null, camposObrigatorios: [],
  },
];

export function etapa(key: EtapaKey): Etapa {
  return ETAPAS.find((e) => e.key === key) ?? ETAPAS[0];
}

export const ROTULO_CAMPO: Record<CampoKey, string> = {
  perfil_profissional: 'Perfil profissional',
  atua_com_holding: 'Já atua com holding',
  produto_interesse: 'Produto de interesse',
  origem: 'Origem do lead',
  objecao_principal: 'Objeção principal',
  forma_pagamento: 'Forma de pagamento',
};

/** Opções fechadas de cada campo (na Clint viram tag; aqui viram select). */
export const OPCOES_CAMPO: Partial<Record<CampoKey, { value: string; label: string }[]>> = {
  perfil_profissional: [
    { value: 'advogado', label: 'Advogado' },
    { value: 'contador', label: 'Contador' },
    { value: 'outro', label: 'Outro' },
  ],
  atua_com_holding: [
    { value: 'sim', label: 'Sim' },
    { value: 'comecando', label: 'Começando' },
    { value: 'nao', label: 'Não' },
  ],
  produto_interesse: PRODUTOS.map((p) => ({ value: p.key, label: p.nome })),
  objecao_principal: [
    { value: 'preco', label: 'Está caro' },
    { value: 'pensar', label: 'Vou pensar' },
    { value: 'socio_conjuge', label: 'Preciso falar com sócio ou cônjuge' },
    { value: 'momento', label: 'Não é o momento' },
    { value: 'ja_sei', label: 'Já sei fazer holding' },
    { value: 'sem_cliente', label: 'Não tenho cliente' },
    { value: 'outra', label: 'Outra' },
  ],
  forma_pagamento: [
    { value: 'cartao', label: 'Cartão' },
    { value: 'pix', label: 'Pix' },
    { value: 'boleto', label: 'Boleto' },
  ],
};

export const ROTULO_PERFIL: Record<PerfilProfissional, string> = { advogado: 'Advogado', contador: 'Contador', outro: 'Outro' };
export const ROTULO_ATUA: Record<AtuaComHolding, string> = { sim: 'Atua com holding', comecando: 'Começando', nao: 'Não atua' };

export const MOTIVOS_PERDA: { key: MotivoPerda; label: string; reativa: boolean; nota?: string }[] = [
  { key: 'fora_do_perfil', label: 'Fora do perfil', reativa: false },
  { key: 'tentativas_esgotadas', label: 'Tentativas de contato esgotadas', reativa: false },
  { key: 'sem_interesse', label: 'Sem interesse', reativa: false },
  { key: 'nao_e_o_momento', label: 'Não é o momento', reativa: true, nota: 'Volta para reativação' },
  { key: 'sem_condicao_financeira', label: 'Sem condição financeira agora', reativa: true, nota: 'Volta para reativação' },
  { key: 'comprou_outro_produto', label: 'Comprou outro produto da casa', reativa: false },
  { key: 'contato_invalido', label: 'Contato inválido', reativa: false },
  { key: 'pediu_sem_contato', label: 'Pediu para não receber contato', reativa: false, nota: 'Vai para a lista de bloqueio' },
  { key: 'ja_atendido_outro_vendedor', label: 'Já atendido por outro vendedor', reativa: false, nota: 'Falha de distribuição: o gestor trata no mesmo dia' },
];

/** Os 9 motivos de fábrica no formato do cadastro (o gestor acrescenta outros em Configurações). */
export const MOTIVOS_PADRAO: MotivoPerdaConfig[] = MOTIVOS_PERDA.map((m) => ({
  key: m.key,
  label: m.label,
  reativa: m.reativa,
  bloqueia: m.key === 'pediu_sem_contato',
  alertaGestor: m.key === 'ja_atendido_outro_vendedor',
  nota: m.nota ?? null,
  sistema: true,
  ativo: true,
}));

/** Rótulo do motivo. Passe o cadastro (`repo.motivosPerda()`) para reconhecer os criados pelo gestor. */
export function rotuloMotivo(k: MotivoPerda | null, cadastro: Pick<MotivoPerdaConfig, 'key' | 'label'>[] = MOTIVOS_PADRAO): string {
  if (!k) return '—';
  return cadastro.find((m) => m.key === k)?.label ?? MOTIVOS_PERDA.find((m) => m.key === k)?.label ?? k.replace(/_/g, ' ');
}

/** Chave de motivo novo a partir do rótulo (ex.: "Preço acima do orçamento" → preco_acima_do_orcamento). */
export function chaveMotivo(label: string): string {
  return label.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

export const ROTULO_ATIVIDADE: Record<TipoAtividade, string> = {
  whatsapp: 'WhatsApp', ligacao: 'Ligação', email: 'E-mail', tarefa: 'Tarefa', reuniao: 'Reunião',
};
export const ICONE_ATIVIDADE: Record<TipoAtividade, string> = {
  whatsapp: 'message', ligacao: 'phone', email: 'mail', tarefa: 'clipboard', reuniao: 'calendar',
};

/** Cadência padrão depois do primeiro contato sem resposta (playbook, seção 9). */
export const CADENCIA: { dia: number; toques: { tipo: TipoAtividade; titulo: string }[] }[] = [
  { dia: 1, toques: [{ tipo: 'whatsapp', titulo: 'WhatsApp de abordagem' }, { tipo: 'ligacao', titulo: 'Ligação' }] },
  { dia: 2, toques: [{ tipo: 'ligacao', titulo: 'Ligação' }, { tipo: 'whatsapp', titulo: 'WhatsApp curto de retomada' }] },
  { dia: 3, toques: [{ tipo: 'whatsapp', titulo: 'WhatsApp com prova (depoimento, caso)' }] },
  { dia: 4, toques: [{ tipo: 'ligacao', titulo: 'Ligação' }, { tipo: 'whatsapp', titulo: 'WhatsApp' }] },
  { dia: 5, toques: [{ tipo: 'whatsapp', titulo: 'Mensagem de encerramento' }] },
];

// ── Fila de recuperação ──

export const ROTULO_STATUS_FILA: Record<StatusFila, string> = {
  a_abordar: 'A abordar',
  tentando_contato: 'Tentando contato',
  em_conversa: 'Em conversa',
  vai_comprar: 'Vai comprar',
  ganho: 'Ganho',
  sem_resposta: 'Sem resposta',
  declinou: 'Declinou',
  sem_interesse: 'Sem interesse',
  numero_invalido: 'Número inválido',
};
export const TOM_STATUS_FILA: Record<StatusFila, Tone> = {
  a_abordar: 'neutral', tentando_contato: 'info', em_conversa: 'accent', vai_comprar: 'warning', ganho: 'success',
  sem_resposta: 'neutral', declinou: 'danger', sem_interesse: 'danger', numero_invalido: 'danger',
};
/** Caminho principal; o resto são saídas. */
export const STATUS_FILA_CAMINHO: StatusFila[] = ['a_abordar', 'tentando_contato', 'em_conversa', 'vai_comprar', 'ganho'];
export const STATUS_FILA_SAIDA: StatusFila[] = ['sem_resposta', 'declinou', 'sem_interesse', 'numero_invalido'];

export const ROTULO_SINAL: Record<SinalRecuperacao, string> = {
  boleto_aberto: 'Boleto em aberto',
  carrinho: 'Carrinho abandonado',
  cartao_recusado: 'Cartão recusado',
  ficha_completa: 'Ficha completa',
  senhas: 'Senhas da Central',
  chat: 'Comentou no chat',
  workbook: 'Workbook',
  apostila: 'Apostila',
  pesquisa: 'Respondeu a pesquisa',
  comunidade: 'Comunidade',
  grupo: 'Grupo de WhatsApp',
  advogado_contador: 'Advogado ou contador',
  quer_parceria: 'Quer parceria',
  respondeu_sem_retorno: 'Respondeu e ficou sem retorno',
};

export const TOM_FAIXA: Record<FaixaScore, Tone> = { A: 'success', B: 'accent', C: 'warning', D: 'neutral' };

// ── Disparo ──

export const ROTULO_SUPRESSAO: Record<Supressao, string> = {
  em_negociacao: 'Em "Negociar" ou "Aguardar pagamento"',
  disparo_48h: 'Recebeu disparo da casa nas últimas 48 horas',
  opt_out: 'Pediu para não receber contato',
  ja_comprou: 'Já comprou o produto ofertado',
};
/** As quatro supressões obrigatórias em todo disparo do comercial. */
export const SUPRESSOES_OBRIGATORIAS: Supressao[] = ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'];

export const ROTULO_STATUS_FICHA: Record<StatusFicha, string> = {
  rascunho: 'Rascunho',
  aguardando_aprovacao: 'Aguardando aprovação',
  aprovada: 'Aprovada',
  reprovada: 'Reprovada',
  enviada: 'Enviada',
};
export const TOM_STATUS_FICHA: Record<StatusFicha, Tone> = {
  rascunho: 'neutral', aguardando_aprovacao: 'warning', aprovada: 'info', reprovada: 'danger', enviada: 'success',
};
