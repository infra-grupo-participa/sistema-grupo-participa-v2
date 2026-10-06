// Definição dos números próprios da agenda (os que não estão em domain/metricas.ts). Aparecem no ícone (i).
import type { TextoIndicador } from '../InfoIndicador';

export const INFO_AGENDA = {
  paraHoje: {
    nome: 'Para hoje',
    oQueE: 'Atividades abertas que vencem hoje e ainda estão no prazo.',
    comoConta: 'Vencimento hoje (horário de Brasília), não concluída e com horário ainda por vir. As que já venceram contam em Atividades atrasadas.',
    paraQue: 'É a lista de trabalho do dia. Chegar às 18h45 com isso zerado.',
    meta: 'Zero no fechamento do dia (18h45).',
  },
  concluidasHoje: {
    nome: 'Concluídas hoje',
    oQueE: 'Atividades marcadas como feitas hoje, de qualquer tipo.',
    comoConta: 'Data de conclusão hoje (horário de Brasília), seja qual for o vencimento. Respeita o filtro de dono.',
    paraQue: 'Produção do dia. Se não está no CRM, não existe: todo toque é registrado com o resultado.',
    meta: null,
  },
  ligacoesHoje: {
    nome: 'Ligações hoje',
    oQueE: 'Ligações feitas hoje, de quantas estavam agendadas para hoje.',
    comoConta: 'Primeiro número: atividades de ligação concluídas hoje. Segundo: atividades de ligação com vencimento hoje, feitas ou não.',
    paraQue: 'Ligação é o toque que mais avança negócio. Feitas abaixo das agendadas no fim do dia pede reagendar o resto.',
    meta: 'Todas as agendadas de hoje feitas até 18h45.',
  },
} satisfies Record<string, TextoIndicador>;
