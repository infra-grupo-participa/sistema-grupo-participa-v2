// Integrações do CRM do Comercial (aba #integracoes): o que entra, o que sai e o risco de cada uma.
// Só texto. O STATUS vem vivo do banco (crm_integracoes_status → domain/integracoes-status.ts), casado pela `chave`;
// integração sem linha no banco (Manychat, Instagram) aparece como "Em breve".
import type { ChaveIntegracao } from '../../domain/integracoes-status';
import { FERRAMENTAS } from '../../domain/mcp-ferramentas';

export interface FerramentaMcp {
  nome: string;
  descricao: string;
}

export interface Integracao {
  /** Chave da linha em crm_integracoes_status. Sem backend ainda: 'manychat' / 'instagram' (selo "Em breve"). */
  chave: ChaveIntegracao | 'manychat' | 'instagram';
  nome: string;
  icone: string;
  papel: string;
  entra: string;
  sai: string;
  risco: string;
  /** Só o MCP: ferramentas que o servidor expõe ao Claude. */
  ferramentas?: FerramentaMcp[];
}

/**
 * Ferramentas do servidor MCP do Comercial (F7): as MESMAS de `domain/mcp-ferramentas.ts`, que é a fonte única.
 * O Claude na nuvem lê e age no CRM com as mesmas regras da tela; as de escrita pedem o escopo "operar" no token.
 */
export const FERRAMENTAS_MCP: FerramentaMcp[] = FERRAMENTAS.map((f) => ({
  nome: f.name,
  descricao: f.escopo === 'ler' ? `${f.title}.`
    : f.annotations.readOnlyHint ? `${f.title} (só consulta, para o envio de WhatsApp; precisa da permissão "operar").`
      : `${f.title} (escreve; precisa da permissão "operar").`,
}));

export const INTEGRACOES: Integracao[] = [
  {
    chave: 'hotmart', nome: 'Hotmart', icone: 'wallet', papel: 'Webhook de compra e abandono',
    entra: 'Compra aprovada, boleto/Pix em aberto, cartão recusado, carrinho abandonado, expirada e reembolso.',
    sai: 'Nada: a Hotmart só informa. Cria as origens automáticas e fecha o negócio como ganho no pagamento aprovado.',
    risco: 'Casar comprador com contato pelo e-mail ou pelo DDD + últimos 8 dígitos do telefone; SCK precisa chegar no checkout.',
  },
  {
    chave: 'infobip', nome: 'Infobip', icone: 'phone', papel: 'WhatsApp oficial e voz',
    entra: 'Mensagens recebidas, status de entrega e leitura, e o registro das ligações.',
    sai: 'Mensagens do vendedor, templates aprovados fora da janela de 24 h, disparos por API e ligações.',
    risco: 'Confirmar o dono da conta do WhatsApp oficial antes de migrar o número.',
  },
  {
    chave: 'evolution', nome: 'WhatsApp por QR (Evolution)', icone: 'phone', papel: 'Números extras conectados por QR code',
    entra: 'Mensagens recebidas nos números conectados por QR e o estado de cada conexão (conectado, aguardando QR, banido).',
    sai: 'Mensagens do vendedor pelo número escolhido, dentro dos limites por minuto e por hora.',
    risco: 'Número não oficial pode ser banido pelo WhatsApp: respeitar os limites e não disparar em massa por aqui.',
  },
  {
    chave: 'unnichat', nome: 'Unnichat', icone: 'message', papel: 'Atendimento e automação no WhatsApp',
    entra: 'Conversas e etiquetas dos fluxos automáticos (quem respondeu, quem pediu vendedor).',
    sai: 'Dono do contato e etapa do negócio, para o fluxo não falar com quem já está com um vendedor.',
    risco: 'Não pode haver dois robôs no mesmo número: definir qual fluxo fica no Unnichat e qual no Infobip.',
  },
  {
    chave: 'manychat', nome: 'Manychat', icone: 'zap', papel: 'Automação no Instagram e WhatsApp',
    entra: 'Leads das palavras-chave e dos fluxos de DM, com a campanha de origem.',
    sai: 'Tag de "em atendimento" para pausar o fluxo quando o vendedor assume.',
    risco: 'Casar o perfil do Instagram com o contato: a DM nem sempre traz telefone ou e-mail.',
  },
  {
    chave: 'activecampaign', nome: 'ActiveCampaign', icone: 'mail', papel: 'E-mail, tags e opt-out',
    entra: 'Opt-out e tags de engajamento (abriu, clicou).',
    sai: 'Tags de etapa e de perdido, para a régua de e-mail não falar com quem está em negociação.',
    risco: 'Opt-out precisa valer nos dois sentidos (lista de bloqueio única).',
  },
  {
    chave: 'sendflow', nome: 'SendFlow', icone: 'users', papel: 'Grupos de WhatsApp',
    entra: 'Quem entrou e saiu dos grupos do evento (sinal de recuperação).',
    sai: 'Nada pelo CRM.',
    risco: 'Casar participante do grupo com contato só pelo telefone.',
  },
  {
    chave: 'respondi', nome: 'Respondi', icone: 'clipboard', papel: 'Formulários e pesquisas',
    entra: 'Respostas dos formulários (aplicação, pesquisa), que aparecem na jornada da pessoa.',
    sai: 'Nada pelo CRM.',
    risco: 'A sincronização roda 1 vez por dia: resposta de hoje cedo pode só aparecer amanhã.',
  },
  {
    chave: 'slack', nome: 'Slack', icone: 'send', papel: '#comercial-alertas e #comercial',
    entra: 'Nada.',
    sai: 'Alertas em tempo real (lead sem dono, prazo crítico) e o fechamento do dia às 19h.',
    risco: 'Definir quem recebe menção em cada alerta para não virar ruído.',
  },
  {
    chave: 'clint', nome: 'Clint', icone: 'download', papel: 'Somente migração',
    entra: 'Negócios, contatos, conversas e gravações exportados uma vez.',
    sai: 'Nada: a Clint é desligada depois da migração.',
    risco: 'Exportar negócios, contatos, conversas e gravações ANTES de desligar.',
  },
  {
    chave: 'instagram', nome: 'Instagram / Social selling', icone: 'camera', papel: 'Perfis do Marcio, da Elaine e outros',
    entra: 'Comentários e DMs dos perfis conectados; quem comenta com intenção de compra vira lead no funil de social selling.',
    sai: 'Nada pelo CRM: a resposta continua no Instagram, feita pelo vendedor.',
    risco: 'Cada perfil precisa ser conta profissional ligada a uma página; ler comentário exige aprovação da Meta.',
  },
  {
    chave: 'mcp', nome: 'MCP do Comercial', icone: 'server', papel: 'Conecta o CRM ao Claude na nuvem',
    entra: 'Pedidos do Claude feitos por quem está logado (mesmo papel e permissões da tela).',
    sai: 'Dados do CRM e as ações abaixo, com registro de quem pediu.',
    risco: 'Toda escrita passa pelas mesmas regras do banco (RPC); nada de chave de serviço exposta.',
    ferramentas: FERRAMENTAS_MCP,
  },
];
