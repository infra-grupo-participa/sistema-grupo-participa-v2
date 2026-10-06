// Definições dos indicadores próprios do Início (os que não estão em domain/metricas.ts).
import type { TextoIndicador } from '../InfoIndicador';
import type { Urgencia } from './painel';

export const INFO_AGIR_AGORA: TextoIndicador = {
  nome: 'Agir agora',
  oQueE: 'O que pede ação de quem está no painel, do mais urgente para o menos.',
  comoConta: 'Entra: negócio aberto com prazo em atenção ou crítico, conversa com lead esperando resposta, atividade atrasada e atividade de hoje ainda aberta.',
  paraQue: 'Comece o dia por aqui. Atrasado primeiro, depois quem está esperando, depois o resto do dia.',
  meta: 'Zero itens em "Atrasado" no fechamento do dia (18h45).',
};

export const INFO_URGENCIA: Record<Urgencia, TextoIndicador> = {
  atrasado: {
    nome: 'Atrasado',
    oQueE: 'Negócios com prazo crítico na etapa e atividades com vencimento já passado.',
    comoConta: 'Prazo crítico: tempo na etapa ≥ alerta crítico. Atividade: vencimento antes de agora e sem conclusão.',
    paraQue: 'É onde se perde venda por silêncio. Resolver antes de qualquer outra coisa.',
    meta: 'Zero.',
  },
  agora: {
    nome: 'Agora',
    oQueE: 'Leads esperando resposta e negócios com prazo em atenção.',
    comoConta: 'Conversa atribuída com mensagem não lida, ou tempo na etapa entre o alerta de atenção e o crítico.',
    paraQue: 'Responder antes que vire atrasado.',
  },
  hoje: {
    nome: 'Hoje',
    oQueE: 'Atividades com vencimento hoje que ainda não venceram.',
    comoConta: 'Vencimento no dia de hoje (Brasília), depois de agora, sem conclusão.',
    paraQue: 'O resto da agenda do dia.',
  },
};

export const INFO_CONVERSAS_ESPERANDO: TextoIndicador = {
  nome: 'Conversas esperando',
  oQueE: 'Conversas atribuídas com mensagem do lead ainda sem resposta.',
  comoConta: 'Conversas com mensagens não lidas, atribuídas a quem está no painel (no time: a qualquer vendedor).',
  paraQue: 'Quem pediu contato espera no máximo 5 minutos em horário comercial.',
  meta: 'Zero no fim de cada bloco de atendimento.',
};

export const INFO_CONTROLE_9H: TextoIndicador = {
  nome: 'Controle das 9h',
  oQueE: 'Conferência diária do gestor (playbook, seção 5.2): quatro listas que deveriam estar vazias.',
  comoConta: 'Cada número é a quantidade de itens da lista agora. Clique para ver os itens.',
  paraQue: 'Achar falha de processo antes que vire venda perdida.',
  meta: 'Zero em cada lista.',
};

export const INFO_JA_ATENDIDO: TextoIndicador = {
  nome: 'Perdidos por "já atendido por outro vendedor"',
  oQueE: 'Negócios marcados como perdidos hoje porque outro vendedor já atendia a pessoa.',
  comoConta: 'Status perdido, motivo "Já atendido por outro vendedor", fechado hoje (Brasília).',
  paraQue: 'É falha de distribuição: dois donos para a mesma pessoa. O gestor trata no mesmo dia.',
  meta: 'Zero.',
};

export const INFO_FICHAS: TextoIndicador = {
  nome: 'Fichas aguardando aprovação',
  oQueE: 'Fichas de disparo por API enviadas para aprovação e ainda sem decisão.',
  comoConta: 'Fichas com status "aguardando aprovação".',
  paraQue: 'Sem ficha aprovada não há disparo. Decidir cedo libera o operador.',
};

export const INFO_CARGA: TextoIndicador = {
  nome: 'Carga por vendedor',
  oQueE: 'Quanto cada vendedor tem nas mãos agora e quanto disso está fora da regra.',
  comoConta: 'Abertos, prazo crítico, sem próximo passo e atividades atrasadas, por dono. Vendas: pagamentos aprovados hoje.',
  paraQue: 'Redistribuir antes que a fila de alguém pare. Clique no vendedor para ver o painel dele.',
  meta: 'Zero em crítico, sem próximo e atrasadas.',
};

export const INFO_PAINEL: TextoIndicador = {
  nome: 'Painel personalizado',
  oQueE: 'Os gráficos e números que cada pessoa escolheu acompanhar.',
  comoConta: 'Cada widget usa a definição oficial da métrica (o (i) de cada um) no período e agrupamento escolhidos.',
  paraQue: 'Cada um monta o seu em "Personalizar". O gestor também pode montar o de um vendedor.',
};

export const INFO_NUMEROS_DIA: TextoIndicador = {
  nome: 'Números do dia',
  oQueE: 'Os números do fechamento do dia (playbook, seção 12), com as mesmas definições de Relatórios.',
  comoConta: 'Contam de meia-noite até agora, no fuso de Brasília.',
};
