// Definição de cada indicador do Comercial: fonte ÚNICA para o ícone (i) das telas, para o painel
// personalizável e para o backend. Número com definição exata: o mesmo número para todo mundo, todo dia
// (playbook, seção 12.1). Mudou a regra aqui, muda em todas as telas.
import type { AgrupamentoWidget, MetricaKey, PeriodoWidget, VisualWidget } from './types';

export interface DefinicaoMetrica {
  key: MetricaKey;
  nome: string;
  /** O que o número conta, em uma frase. */
  oQueE: string;
  /** Regra exata de contagem. */
  comoConta: string;
  /** Para que serve / o que fazer quando foge da meta. */
  paraQue: string;
  meta: string | null;
  formato: 'numero' | 'moeda' | 'percentual' | 'minutos';
  /** Agrupamentos que fazem sentido no gráfico. */
  agrupamentos: AgrupamentoWidget[];
}

export const METRICAS: Record<MetricaKey, DefinicaoMetrica> = {
  abordados: {
    key: 'abordados', nome: 'Leads abordados',
    oQueE: 'Pessoas únicas que receberam um contato ativo do comercial no período.',
    comoConta: 'Conta cada pessoa uma vez: atividade de WhatsApp ou ligação concluída pelo dono, ou disparo do comercial. Mensagem avulsa fora de atividade não conta.',
    paraQue: 'Mede o esforço de cada vendedor. Abaixo da meta diária, a fila está parada.',
    meta: 'Definida pelo gestor depois de 30 dias de dado.', formato: 'numero', agrupamentos: ['nenhum', 'dia', 'vendedor'],
  },
  responderam: {
    key: 'responderam', nome: 'Leads que responderam',
    oQueE: 'Pessoas abordadas, em qualquer dia, que responderam no período.',
    comoConta: 'Conta quando o negócio entra numa etapa com papel de Qualificação.',
    paraQue: 'Mostra se a abordagem funciona. Muita abordagem e pouca resposta pede revisar mensagem, horário ou lista.',
    meta: null, formato: 'numero', agrupamentos: ['nenhum', 'dia', 'vendedor', 'funil'],
  },
  entraram_contato: {
    key: 'entraram_contato', nome: 'Leads que entraram em contato',
    oQueE: 'Pessoas que procuraram a casa sem terem sido abordadas antes no ciclo.',
    comoConta: 'Primeira mensagem do lead no número oficial ou pedido de contato, sem atividade ativa anterior no mesmo ciclo.',
    paraQue: 'Mede a demanda espontânea. Cada uma precisa de resposta em até 5 minutos em horário comercial.',
    meta: null, formato: 'numero', agrupamentos: ['nenhum', 'dia', 'vendedor'],
  },
  em_negociacao: {
    key: 'em_negociacao', nome: 'Em negociação',
    oQueE: 'Negócios abertos em etapas de Negociação ou Pagamento, agora.',
    comoConta: 'Fotografia do momento: negócios abertos cujo papel da etapa é Negociação ou Pagamento. Valor = soma do valor dos negócios.',
    paraQue: 'É o dinheiro mais perto de entrar. Essas pessoas recebem conversa, nunca disparo em massa.',
    meta: null, formato: 'moeda', agrupamentos: ['nenhum', 'vendedor', 'produto', 'funil'],
  },
  vendas: {
    key: 'vendas', nome: 'Vendas',
    oQueE: 'Pagamentos aprovados no período.',
    comoConta: 'Ganho só com pagamento aprovado na Hotmart; "o lead disse sim" não conta. Crédito para o dono do negócio que trabalhou o lead.',
    paraQue: 'Resultado. Olhe junto com reembolso e condição especial: quem mais vende não é necessariamente o melhor vendedor.',
    meta: null, formato: 'numero', agrupamentos: ['nenhum', 'dia', 'vendedor', 'produto', 'funil'],
  },
  receita: {
    key: 'receita', nome: 'Receita',
    oQueE: 'Soma dos pagamentos aprovados no período.',
    comoConta: 'Valor do negócio ganho (preço da oferta vigente). Reembolso desconta no período em que acontece.',
    paraQue: 'Base da conta de trás para frente: meta de receita ÷ ticket = vendas necessárias.',
    meta: null, formato: 'moeda', agrupamentos: ['nenhum', 'dia', 'vendedor', 'produto', 'funil'],
  },
  abertos: {
    key: 'abertos', nome: 'Negócios abertos',
    oQueE: 'Negócios em andamento, agora.',
    comoConta: 'Status aberto, em qualquer etapa e funil.',
    paraQue: 'Mede a carga. Acima do limite por vendedor, ele não recebe lead novo até limpar a fila.',
    meta: 'Limite por vendedor: a definir depois de 30 dias de dado.', formato: 'numero', agrupamentos: ['nenhum', 'vendedor', 'etapa', 'funil'],
  },
  criticos: {
    key: 'criticos', nome: 'Prazo crítico',
    oQueE: 'Negócios parados na etapa além do alerta crítico.',
    comoConta: 'Tempo desde que o negócio entrou na etapa ≥ alerta crítico da etapa (ex.: primeiro contato: 15 minutos).',
    paraQue: 'É onde se perde venda por silêncio. Agir agora ou escalar para o gestor.',
    meta: 'Zero.', formato: 'numero', agrupamentos: ['nenhum', 'vendedor', 'etapa', 'funil'],
  },
  sem_proximo: {
    key: 'sem_proximo', nome: 'Sem próximo passo',
    oQueE: 'Negócios abertos sem atividade futura com data.',
    comoConta: 'Status aberto e nenhuma atividade não concluída.',
    paraQue: 'Inegociável 4: negócio sem próximo passo vira perdido com motivo. Agende ou encerre.',
    meta: 'Zero.', formato: 'numero', agrupamentos: ['nenhum', 'vendedor', 'funil'],
  },
  sem_dono: {
    key: 'sem_dono', nome: 'Sem dono',
    oQueE: 'Negócios abertos sem vendedor responsável.',
    comoConta: 'Status aberto e dono vazio.',
    paraQue: 'É onde nasce a sobreposição. O gestor confere às 9h e distribui na hora.',
    meta: 'Zero.', formato: 'numero', agrupamentos: ['nenhum', 'funil'],
  },
  atrasadas: {
    key: 'atrasadas', nome: 'Atividades atrasadas',
    oQueE: 'Atividades com data vencida e não concluídas.',
    comoConta: 'Vencimento antes de agora e sem conclusão.',
    paraQue: 'Disciplina. Atrasada de hoje é feita hoje; a da semana passada pede revisar a cadência.',
    meta: 'Zero no fechamento do dia (18h45).', formato: 'numero', agrupamentos: ['nenhum', 'vendedor'],
  },
  tempo_primeiro_contato: {
    key: 'tempo_primeiro_contato', nome: 'Tempo até o primeiro contato',
    oQueE: 'Quanto o lead esperou entre chegar e receber o primeiro contato.',
    comoConta: 'Mediana, em minutos, entre a criação do negócio e a primeira atividade concluída pelo dono, em horário comercial.',
    paraQue: 'Velocidade. Carrinho, Pix, boleto e cartão recusado: até 15 minutos; quem pediu contato: até 5.',
    meta: 'Até 15 min (checkout) e 5 min (pediu contato).', formato: 'minutos', agrupamentos: ['nenhum', 'vendedor', 'funil'],
  },
  conversao: {
    key: 'conversao', nome: 'Conversão',
    oQueE: 'Parte dos negócios encerrados que virou venda.',
    comoConta: 'Ganhos ÷ (ganhos + perdidos) no período.',
    paraQue: 'Mostra onde se perde venda quando olhada por etapa e por vendedor.',
    meta: null, formato: 'percentual', agrupamentos: ['nenhum', 'vendedor', 'produto', 'funil'],
  },
  perdidos: {
    key: 'perdidos', nome: 'Perdidos',
    oQueE: 'Negócios encerrados sem venda no período.',
    comoConta: 'Status perdido, sempre com um motivo do cadastro.',
    paraQue: 'Por que se perde venda. "Já atendido por outro vendedor" é falha de distribuição e deveria ser zero.',
    meta: null, formato: 'numero', agrupamentos: ['nenhum', 'motivo', 'vendedor', 'funil'],
  },
};

export const ROTULO_PERIODO: Record<PeriodoWidget, string> = { hoje: 'Hoje', '7d': 'Últimos 7 dias', '30d': 'Últimos 30 dias', mes: 'Este mês' };
export const ROTULO_VISUAL: Record<VisualWidget, string> = { numero: 'Número', barras: 'Barras', linha: 'Linha', pizza: 'Pizza', lista: 'Lista' };
export const ROTULO_AGRUPAR: Record<AgrupamentoWidget, string> = {
  nenhum: 'Sem agrupar', dia: 'Por dia', vendedor: 'Por vendedor', produto: 'Por produto', etapa: 'Por etapa', motivo: 'Por motivo', funil: 'Por funil',
};
