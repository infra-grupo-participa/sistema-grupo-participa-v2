// Integrações do CRM do Comercial (aba #integracoes): o que entra, o que sai e o risco de cada uma.
// Só dado: o status real vem do backend quando cada conexão existir.

export type StatusIntegracao = 'A conectar' | 'Em breve' | 'Entra com o backend';

export interface FerramentaMcp {
  nome: string;
  descricao: string;
}

export interface Integracao {
  nome: string;
  icone: string;
  papel: string;
  entra: string;
  sai: string;
  risco: string;
  status: StatusIntegracao;
  /** Só o MCP: ferramentas que o servidor expõe ao Claude. */
  ferramentas?: FerramentaMcp[];
}

/** Ferramentas do servidor MCP do Comercial (o Claude na nuvem lê e age no CRM com as mesmas regras da tela). */
export const FERRAMENTAS_MCP: FerramentaMcp[] = [
  { nome: 'buscar_pessoa', descricao: 'Acha o contato por nome, e-mail ou telefone.' },
  { nome: 'ver_jornada', descricao: 'Inscrições, compras, grupos e conversas da pessoa.' },
  { nome: 'ver_funil', descricao: 'Negócios por etapa, com prazo e dono.' },
  { nome: 'criar_atividade', descricao: 'Agenda o próximo passo com data.' },
  { nome: 'mover_etapa', descricao: 'Move o negócio, respeitando os campos obrigatórios.' },
  { nome: 'registrar_nota', descricao: 'Anota na linha do tempo do contato.' },
  { nome: 'fechamento_do_dia', descricao: 'Os números do dia com a definição exata.' },
];

export const INTEGRACOES: Integracao[] = [
  {
    nome: 'Hotmart', icone: 'wallet', papel: 'Webhook de compra e abandono', status: 'A conectar',
    entra: 'Compra aprovada, boleto/Pix em aberto, cartão recusado, carrinho abandonado, expirada e reembolso.',
    sai: 'Nada: a Hotmart só informa. Cria as origens automáticas e fecha o negócio como ganho no pagamento aprovado.',
    risco: 'Casar comprador com contato pelo e-mail ou pelo DDD + últimos 8 dígitos do telefone; SCK precisa chegar no checkout.',
  },
  {
    nome: 'Infobip', icone: 'phone', papel: 'WhatsApp oficial e voz', status: 'A conectar',
    entra: 'Mensagens recebidas, status de entrega e leitura, e o registro das ligações.',
    sai: 'Mensagens do vendedor, templates aprovados fora da janela de 24 h, disparos por API e ligações.',
    risco: 'Confirmar o dono da conta do WhatsApp oficial antes de migrar o número.',
  },
  {
    nome: 'Unnichat', icone: 'message', papel: 'Atendimento e automação no WhatsApp', status: 'A conectar',
    entra: 'Conversas e etiquetas dos fluxos automáticos (quem respondeu, quem pediu vendedor).',
    sai: 'Dono do contato e etapa do negócio, para o fluxo não falar com quem já está com um vendedor.',
    risco: 'Não pode haver dois robôs no mesmo número: definir qual fluxo fica no Unnichat e qual no Infobip.',
  },
  {
    nome: 'Manychat', icone: 'zap', papel: 'Automação no Instagram e WhatsApp', status: 'A conectar',
    entra: 'Leads das palavras-chave e dos fluxos de DM, com a campanha de origem.',
    sai: 'Tag de "em atendimento" para pausar o fluxo quando o vendedor assume.',
    risco: 'Casar o perfil do Instagram com o contato: a DM nem sempre traz telefone ou e-mail.',
  },
  {
    nome: 'ActiveCampaign', icone: 'mail', papel: 'E-mail, tags e opt-out', status: 'A conectar',
    entra: 'Opt-out e tags de engajamento (abriu, clicou).',
    sai: 'Tags de etapa e de perdido, para a régua de e-mail não falar com quem está em negociação.',
    risco: 'Opt-out precisa valer nos dois sentidos (lista de bloqueio única).',
  },
  {
    nome: 'SendFlow', icone: 'users', papel: 'Grupos de WhatsApp', status: 'A conectar',
    entra: 'Quem entrou e saiu dos grupos do evento (sinal de recuperação).',
    sai: 'Nada pelo CRM.',
    risco: 'Casar participante do grupo com contato só pelo telefone.',
  },
  {
    nome: 'Slack', icone: 'send', papel: '#comercial-alertas e #comercial', status: 'A conectar',
    entra: 'Nada.',
    sai: 'Alertas em tempo real (lead sem dono, prazo crítico) e o fechamento do dia às 19h.',
    risco: 'Definir quem recebe menção em cada alerta para não virar ruído.',
  },
  {
    nome: 'Clint', icone: 'download', papel: 'Somente migração', status: 'A conectar',
    entra: 'Negócios, contatos, conversas e gravações exportados uma vez.',
    sai: 'Nada: a Clint é desligada depois da migração.',
    risco: 'Exportar negócios, contatos, conversas e gravações ANTES de desligar.',
  },
  {
    nome: 'Instagram / Social selling', icone: 'camera', papel: 'Perfis do Marcio, da Elaine e outros', status: 'Em breve',
    entra: 'Comentários e DMs dos perfis conectados; quem comenta com intenção de compra vira lead no funil de social selling.',
    sai: 'Nada pelo CRM: a resposta continua no Instagram, feita pelo vendedor.',
    risco: 'Cada perfil precisa ser conta profissional ligada a uma página; ler comentário exige aprovação da Meta.',
  },
  {
    nome: 'MCP do Comercial', icone: 'server', papel: 'Conecta o CRM ao Claude na nuvem', status: 'Entra com o backend',
    entra: 'Pedidos do Claude feitos por quem está logado (mesmo papel e permissões da tela).',
    sai: 'Dados do CRM e as ações abaixo, com registro de quem pediu.',
    risco: 'Toda escrita passa pelas mesmas regras do banco (RPC); nada de chave de serviço exposta.',
    ferramentas: FERRAMENTAS_MCP,
  },
];
