// Definição dos indicadores da performance da equipe que não estão em domain/metricas.ts (fonte do (i)).
// Regras de contagem em performance.ts; mudou lá, mude aqui.
import type { TextoIndicador } from '../InfoIndicador';
import { CRITERIOS, MIN_ENCERRADOS, type CriterioRanking } from './performance';

export const INFO_EQUIPE = {
  ticket: {
    nome: 'Ticket médio',
    oQueE: 'Valor médio de cada venda do vendedor no período.',
    comoConta: 'Receita ÷ vendas (pagamentos aprovados). Na comparação, o time é a receita somada ÷ vendas somadas.',
    paraQue: 'Ticket baixo com muita venda pode ser concentração em produto de entrada ou excesso de condição especial.',
  },
  abordagensDia: {
    nome: 'Abordagens por dia',
    oQueE: 'Toques de WhatsApp e ligação concluídos por dia no período.',
    comoConta: 'Atividades de WhatsApp ou ligação concluídas pelo dono ÷ dias do período (corridos, contando hoje).',
    paraQue: 'Esforço. Pouca abordagem com fila cheia é fila parada; muita abordagem e pouca venda pede revisar a conversa.',
  },
  noPrazo: {
    nome: 'Atividades no prazo',
    oQueE: 'Parte das atividades que venceram no período e foram concluídas até o vencimento.',
    comoConta: 'Concluídas até o horário de vencimento ÷ todas as que venceram no período (até agora), concluídas ou não.',
    paraQue: 'Disciplina com a agenda. Abaixo de 90% a cadência está escorregando.',
    meta: '90% ou mais.',
  },
  qualidade: {
    nome: 'Reembolso e condição especial',
    oQueE: 'Vendas do vendedor que voltaram (reembolso) ou saíram com condição fora da oferta vigente.',
    comoConta: 'Entra com o backend: a Hotmart informa o reembolso por transação e a oferta usada em cada venda.',
    paraQue: 'Quem mais vende não é necessariamente o melhor vendedor: venda que volta ou que sai com desconto custa caro.',
  },
  tendencia: {
    nome: 'Tendência de receita',
    oQueE: 'Receita por dia do vendedor no período.',
    comoConta: 'Soma dos pagamentos aprovados em cada dia (Brasília). Períodos menores que 7 dias mostram os últimos 7.',
    paraQue: 'Mostra se a venda está concentrada num dia só ou constante.',
  },
  semResposta: {
    nome: 'Conversas sem resposta',
    oQueE: 'Conversas em que o lead escreveu por último e o vendedor ainda não respondeu.',
    comoConta: 'Retrato de agora: última mensagem do WhatsApp é do lead, na conversa atribuída ao vendedor.',
    paraQue: 'Lead que escreveu e esperou esfria. Responda as mais antigas primeiro.',
    meta: 'Zero no fim do dia.',
  },
  ranking: {
    nome: 'Ranking da equipe',
    oQueE: 'Posição de cada vendedor no critério escolhido, no período.',
    comoConta: `Volume: receita. Conversão: ganhos ÷ encerrados (mínimo ${MIN_ENCERRADOS} encerrados). Qualidade: sem reembolso e sem falha de processo. Disciplina: atividades no prazo, menos atrasadas e negócios sem próximo passo.`,
    paraQue: 'Quem mais vende não é necessariamente o melhor vendedor. Olhe os quatro critérios antes de concluir.',
  },
  funilPessoal: {
    nome: 'Funil pessoal',
    oQueE: 'Quantos negócios de venda ativa do vendedor chegaram a cada papel de etapa e quantos passaram da anterior.',
    comoConta: 'Negócios do vendedor que nasceram ou encerraram no período, ou seguem abertos. Ganho conta como tendo passado por todas. "Time" = mesma conta com todos os vendedores.',
    paraQue: 'A etapa em que a passagem do vendedor fica abaixo do time é onde treinar.',
  },
  atividadesTipo: {
    nome: 'Atividades por tipo',
    oQueE: 'Atividades concluídas no período, por tipo.',
    comoConta: 'Data de conclusão no período, do dono da atividade. "Média do time" = total do time ÷ número de vendedores.',
    paraQue: 'Mostra o canal que o vendedor usa. Só WhatsApp e nenhuma ligação costuma travar a negociação.',
  },
  mapaCalor: {
    nome: 'Quando o vendedor trabalha',
    oQueE: 'Atividades concluídas por dia da semana e faixa de horário (Brasília).',
    comoConta: 'Cada atividade concluída no período cai numa célula. Mais escuro = mais atividades. "Fora" = antes das 8h ou depois das 20h.',
    paraQue: 'Buraco no horário de pico do lead é venda perdida por silêncio.',
  },
  cadencia: {
    nome: 'Cadência cumprida',
    oQueE: 'Toques da cadência de primeiro contato (dias 1 a 5) que venceram no período.',
    comoConta: 'No prazo = concluído até o vencimento. Com atraso = concluído depois. Pendente = vencido e não feito.',
    paraQue: 'Cadência pela metade queima o lead antes da hora.',
    meta: '100% no prazo.',
  },
  tempoEtapa: {
    nome: 'Tempo parado em cada etapa',
    oQueE: 'Quanto tempo, em média, os negócios abertos do vendedor estão parados em cada papel de etapa, agora.',
    comoConta: 'Média de (agora − entrada na etapa) dos abertos de venda ativa. Estimativa: o tempo real de passagem entra com o backend.',
    paraQue: 'Etapa com média bem acima do time é onde o vendedor trava.',
  },
  perdidosMotivo: {
    nome: 'Perdidos por motivo',
    oQueE: 'Negócios do vendedor encerrados sem venda no período, por motivo do cadastro.',
    comoConta: '% = perdidos pelo motivo ÷ perdidos do vendedor. "Time" = a mesma fatia no time.',
    paraQue: 'Motivo com fatia muito acima do time aponta abordagem a corrigir. Falha de processo é do gestor, não do vendedor.',
  },
  vendasPor: {
    nome: 'Vendas por produto e funil',
    oQueE: 'Pagamentos aprovados do vendedor no período, agrupados.',
    comoConta: 'Ganhos com data de fechamento no período, pelo produto do negócio ou pelo funil em que ele estava.',
    paraQue: 'Mostra onde o vendedor rende mais.',
  },
  carteira: {
    nome: 'Carteira atual',
    oQueE: 'Negócios abertos do vendedor agora, por papel da etapa.',
    comoConta: 'Status aberto. Atenção/crítico = tempo na etapa acima do alerta/crítico da etapa.',
    paraQue: 'Prazo crítico é onde se perde venda por silêncio: agir agora.',
    meta: 'Zero em prazo crítico.',
  },
  umAUm: {
    nome: 'Anotações de 1:1',
    oQueE: 'O que foi combinado nas conversas individuais com o vendedor.',
    comoConta: 'Por enquanto só nesta tela e neste navegador: some ao recarregar. Gravar e ver o histórico entra com o backend.',
    paraQue: 'Volte nelas no próximo 1:1 para cobrar o combinado.',
  },
} satisfies Record<string, TextoIndicador>;

/** (i) de cada critério do ranking. */
export function infoCriterio(c: CriterioRanking): TextoIndicador {
  return { nome: `Critério: ${CRITERIOS[c].rotulo}`, oQueE: CRITERIOS[c].comoConta, paraQue: INFO_EQUIPE.ranking.paraQue };
}
