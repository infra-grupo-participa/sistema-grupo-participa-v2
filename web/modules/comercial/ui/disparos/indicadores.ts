// Definição dos números próprios de Disparos (os que não estão em domain/metricas.ts). Aparecem no (i).
import type { TextoIndicador } from '../InfoIndicador';

export const INFO_DISPARO = {
  aguardando: {
    nome: 'Aguardando aprovação',
    oQueE: 'Fichas enviadas pelo operador que ainda esperam o ok do gestor.',
    comoConta: 'Status Aguardando aprovação. Rascunho não conta.',
    paraQue: 'Disparo só sai com ficha aprovada. O gestor confere supressões, template e link e decide no mesmo dia.',
    meta: 'Zero no fim do dia.',
  },
  proximos7: {
    nome: 'Agendados para 7 dias',
    oQueE: 'Disparos que vão sair de agora até daqui a 7 dias.',
    comoConta: 'Fichas aguardando aprovação, aprovadas ou enviadas com data entre agora e 7 dias à frente. Rascunho e reprovada ficam fora.',
    paraQue: 'Mostra a pressão sobre a base na semana. Muito disparo junto cansa a lista e derruba a resposta.',
    meta: null,
  },
  conflitos: {
    nome: 'Conflitos de 48 h',
    oQueE: 'Fichas do mesmo produto agendadas a menos de 48 h uma da outra.',
    comoConta: 'Conta cada ficha envolvida (um conflito entre duas fichas soma 2). Rascunho e reprovada não entram.',
    paraQue: 'A mesma pessoa não recebe disparo da casa em 48 h. Conflito pede remarcar uma das fichas.',
    meta: 'Zero.',
  },
  entregues: {
    nome: 'Entregues',
    oQueE: 'Mensagens que chegaram ao WhatsApp do contato.',
    comoConta: 'Soma das entregas registradas no log das fichas já disparadas. Falha de envio não conta.',
    paraQue: 'Base das taxas de leitura e resposta. Entrega baixa em relação à lista aponta número inválido ou bloqueio.',
    meta: null,
  },
  leitura: {
    nome: 'Taxa de leitura',
    oQueE: 'Parte das mensagens entregues que foi lida.',
    comoConta: 'Lidas ÷ entregues, em %, somando as fichas com resultado (confirmação de leitura do WhatsApp).',
    paraQue: 'Mede se o template e o horário chamam atenção. Leitura caindo pede revisar a primeira linha do template ou o horário.',
    meta: null,
  },
  resposta: {
    nome: 'Taxa de resposta',
    oQueE: 'Parte das mensagens entregues que recebeu resposta do contato.',
    comoConta: 'Respostas ÷ entregues, em %, somando as fichas com resultado.',
    paraQue: 'É o que vira conversa e venda. Resposta baixa com leitura alta pede revisar a oferta ou a pergunta do template.',
    meta: null,
  },
  falhas: {
    nome: 'Falhas',
    oQueE: 'Mensagens que não saíram ou não chegaram.',
    comoConta: 'Falhas ÷ (entregues + falhas), em %.',
    paraQue: 'Falha alta indica lista suja (número inválido, sem WhatsApp) ou limite diário da Meta. Limpe a lista antes do próximo disparo.',
    meta: null,
  },
  resultado: {
    nome: 'Resultado do disparo',
    oQueE: 'Como a ficha foi recebida depois de sair: leitura, resposta e falhas.',
    comoConta: 'Lidas ÷ entregues e respostas ÷ entregues, em %, pelo log do envio. Falhas aparecem em vermelho quando houver. Os números completos estão na ficha.',
    paraQue: 'Compara um disparo com o outro para decidir template, horário e lista dos próximos.',
    meta: null,
  },
  recebem: {
    nome: 'Recebem',
    oQueE: 'Quantas pessoas da lista recebem de fato o disparo.',
    comoConta: 'Tamanho da lista menos os suprimidos pelas 4 supressões obrigatórias (em negociação, disparo nas últimas 48 h, pediu para não receber, já comprou o produto).',
    paraQue: 'É o tamanho real do disparo e o que conta no limite diário do número.',
    meta: null,
  },
  simulador: {
    nome: 'Simulador de supressões',
    oQueE: 'Prévia de quantos contatos da base saem por cada supressão obrigatória para o produto escolhido.',
    comoConta: 'Cada contato conta uma vez, pelo primeiro motivo que o tira: em negociação, disparo nas últimas 48 h, pediu para não receber, já comprou o produto.',
    paraQue: 'Confere se a lista é viável antes de pedir aprovação.',
    meta: null,
  },
} satisfies Record<string, TextoIndicador>;
