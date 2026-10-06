// Definição dos números próprios da recuperação (os que não estão em domain/metricas.ts). Aparecem no (i).
import type { TextoIndicador } from '../InfoIndicador';

export const INFO_FILA = {
  naFila: {
    nome: 'Na fila',
    oQueE: 'Pessoas da fila de recuperação escolhida, em qualquer status.',
    comoConta: 'Uma por pessoa, como o Fechamento montou a fila quando o carrinho fechou. Os filtros da tela não mudam este número.',
    paraQue: 'Tamanho do trabalho do pós-lançamento. Compare com Em trabalho para ver quanto ainda falta.',
    meta: null,
  },
  emTrabalho: {
    nome: 'Em trabalho',
    oQueE: 'Pessoas da fila que ainda não foram encerradas.',
    comoConta: 'Tudo que não é Ganho nem saída (Sem resposta, Declinou, Sem interesse, Número inválido).',
    paraQue: 'O que ainda pode virar venda. Zera quando todo mundo teve um desfecho.',
    meta: 'Zero no fim da recuperação.',
  },
  ganhos: {
    nome: 'Ganhos',
    oQueE: 'Pessoas da fila marcadas como Ganho.',
    comoConta: 'Status Ganho na fila. A venda só vale com pagamento aprovado na Hotmart; o status aqui é o registro do vendedor.',
    paraQue: 'Resultado da recuperação desta fila.',
    meta: null,
  },
  taxa: {
    nome: 'Taxa de recuperação',
    oQueE: 'Parte da fila que virou venda.',
    comoConta: 'Ganhos ÷ total de pessoas na fila, em %. Quem ainda está em trabalho conta no total.',
    paraQue: 'Compara uma recuperação com a outra e mostra se a ordem e o script funcionam.',
    meta: null,
  },
  semRetorno: {
    nome: 'Respondeu e ficou sem retorno',
    oQueE: 'Pessoas que já responderam a casa e ainda esperam o nosso retorno.',
    comoConta: 'Sinal "Respondeu e ficou sem retorno" com status ainda em A abordar. Clique para filtrar a lista.',
    paraQue: 'É o primeiro grupo da ordem do playbook: venda quase pronta perdida por silêncio.',
    meta: 'Zero, antes de abrir qualquer lista nova.',
  },
  faixas: {
    nome: 'Faixas A a D e score',
    oQueE: 'Prioridade de cada pessoa na fila, pelo score de 0 a 100.',
    comoConta: 'O score soma os sinais da pessoa (boleto em aberto 40 ou carrinho 24, ficha completa 20, senhas 16, chat 12, entre outros), com teto de 100. Faixa A: 60 ou mais; B: 40 a 59; C: 25 a 39; D: abaixo de 25. O número ao lado de cada faixa é quantas pessoas ela tem.',
    paraQue: 'Define a ordem de abordagem: C e D ficam travadas enquanto houver alguém de A ou B em A abordar.',
    meta: 'A e B zeradas antes de tocar em C e D.',
  },
} satisfies Record<string, TextoIndicador>;
