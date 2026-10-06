// Definição dos números próprios da caixa de conversas (os que não estão em domain/metricas.ts). Aparecem no (i).
import type { TextoIndicador } from '../InfoIndicador';

export const INFO_CAIXA = {
  esperando: {
    nome: 'Conversas sem resposta',
    oQueE: 'Conversas em que a última mensagem é do lead: ele está esperando a nossa resposta.',
    comoConta: 'Uma por conversa, dentro do filtro escolhido (Minhas, Todas ou Sem dono). Responder tira da conta na hora.',
    paraQue: 'É a fila de trabalho da caixa. A lista já vem na ordem: quem espera há mais tempo fica no topo.',
    meta: 'Primeira resposta em até 5 minutos em horário comercial.',
  },
  criticas: {
    nome: 'Esperando além do prazo',
    oQueE: 'Conversas sem resposta que passaram do alerta crítico.',
    comoConta: 'Tempo desde a última mensagem do lead, contando só o horário comercial (seg a sex 8h–20h, sáb 9h–13h), ≥ 15 minutos. O mesmo alerta do primeiro contato no funil.',
    paraQue: 'É onde se perde venda por silêncio. Responder agora ou pedir ajuda ao gestor.',
    meta: 'Zero.',
  },
  naoLidas: {
    nome: 'Mensagens não lidas',
    oQueE: 'Mensagens do lead que ninguém abriu ainda.',
    comoConta: 'Soma das mensagens recebidas depois da última resposta nossa, dentro do filtro escolhido. Abrir a conversa marca como lida só para o dono (ou o gestor, em conversa sem dono).',
    paraQue: 'Mostra o que ainda nem foi visto. Quem só espia a conversa de outro não apaga o aviso do dono.',
    meta: null,
  },
  semDono: {
    nome: 'Conversas sem dono',
    oQueE: 'Conversas de contatos que ainda não têm vendedor responsável.',
    comoConta: 'Conversas da caixa inteira (não só do filtro) cujo contato está sem dono.',
    paraQue: 'Ninguém responde lead sem dono: o gestor atribui antes. Clique para ver a lista.',
    meta: 'Zero, conferido pelo gestor às 9h.',
  },
  janela: {
    nome: 'Janela de 24 h',
    oQueE: 'Prazo do WhatsApp oficial para mandar mensagem livre ao lead.',
    comoConta: 'Abre (ou renova) a cada mensagem do lead e dura 24 horas a partir dela. Mostra quanto falta para fechar; fica em alerta abaixo de 2 h.',
    paraQue: 'Dentro da janela sai texto livre; fora dela só sai template aprovado. Responder antes de fechar evita depender de template.',
    meta: null,
  },
} satisfies Record<string, TextoIndicador>;
