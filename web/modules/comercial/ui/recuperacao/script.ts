// Script de abordagem da recuperação. Fonte: fechamento/processos/recuperar-quem-assistiu-e-nao-comprou.md
// (dono: Jonathan Mendes). Texto copiado do processo; a tela só preenche nome, vendedor e evento.
import type { SinalRecuperacao } from '../../domain/types';

export const REGRAS_PRIMEIRA_MENSAGEM: { titulo: string; texto: string }[] = [
  { titulo: 'Sem link', texto: 'Link na primeira mensagem derruba resposta e é sinal de spam. O link entra quando a pessoa pedir.' },
  { titulo: 'Sem oferta', texto: 'A primeira mensagem não vende, pede uma informação. Quem abre vendendo recebe "obrigado" e some.' },
  { titulo: 'Uma pergunta só', texto: 'Fácil de responder: a pessoa tem que conseguir responder em cinco palavras, do ponto de ônibus.' },
];

export type VarianteKey = 'base' | 'ficha_completa' | 'senhas' | 'quer_parceria' | 'chat' | 'comunidade';

/** Segundo parágrafo da mensagem 1, trocado conforme o sinal da pessoa. */
export const VARIANTES: { key: VarianteKey; rotulo: string; paragrafo: string; nota?: string }[] = [
  {
    key: 'base', rotulo: 'Base',
    paragrafo: 'Você acompanhou as aulas do {evento} e não chegou a entrar. Não vim insistir em venda, vim entender o que te segurou.',
  },
  {
    key: 'ficha_completa', rotulo: 'Ficha completa',
    paragrafo: 'Você preencheu a ficha inteira e escreveu lá que sua maior dificuldade hoje é "{frase da ficha}". Foi isso que me fez te chamar.',
    nota: 'Usar a frase da pessoa palavra por palavra, como está na ficha, sem melhorar.',
  },
  {
    key: 'senhas', rotulo: 'Senhas da Central',
    paragrafo: 'Você resgatou as senhas da Central, até a última. Isso quase ninguém fez. Por isso estranhei não ver seu nome na lista de quem entrou.',
  },
  {
    key: 'quer_parceria', rotulo: 'Parceria',
    paragrafo: 'Na ficha você marcou que queria a parceria de negócio, não só a formação. Essa é justamente a parte que a aula não teve tempo de explicar direito, e é sobre ela que eu queria te ouvir cinco minutos.',
  },
  {
    key: 'chat', rotulo: 'Chat',
    paragrafo: 'Te vi comentando no chat durante as aulas, você ficou até o fim em mais de uma. Por isso vim falar direto com você.',
  },
  {
    key: 'comunidade', rotulo: 'Comunidade',
    paragrafo: 'Você entrou na comunidade e acompanhou a semana inteira por lá. Fiquei com a impressão de que faltou pouco.',
  },
];

const PERGUNTA = 'Na pesquisa que a gente fez com a turma, quase todo mundo travou em uma de duas coisas: achar que ainda não domina a técnica pra atender um cliente de holding, ou não saber de onde viria o primeiro cliente. Foi alguma dessas duas? Ou foi outra coisa?';

/** Variante sugerida pelo sinal mais forte (ficha > senhas > parceria > chat > comunidade). */
export function varianteDoSinal(sinais: SinalRecuperacao[]): VarianteKey {
  const s = new Set(sinais);
  if (s.has('ficha_completa')) return 'ficha_completa';
  if (s.has('senhas')) return 'senhas';
  if (s.has('quer_parceria')) return 'quer_parceria';
  if (s.has('chat')) return 'chat';
  if (s.has('comunidade')) return 'comunidade';
  return 'base';
}

/** Mensagem 1 completa, com nome do lead, vendedor e evento preenchidos. */
export function montarMensagem(v: VarianteKey, nomeLead: string, vendedor: string, evento: string): string {
  const primeiro = (s: string) => s.trim().split(/\s+/)[0] || s;
  const par = (VARIANTES.find((x) => x.key === v) ?? VARIANTES[0]).paragrafo.replace('{evento}', evento);
  return [
    `Oi ${primeiro(nomeLead)}, tudo bem? Aqui é o ${primeiro(vendedor)}, do time do Professor Marcio.`,
    par,
    PERGUNTA,
  ].join('\n\n');
}

export const ROTEIRO_RESPOSTAS: { gatilho: string; resposta: string; nota?: string }[] = [
  {
    gatilho: '"Foi a técnica / não me sinto preparado"',
    resposta: 'Faz sentido, e é a resposta mais comum que a gente recebe. Deixa eu te perguntar uma coisa: você já chegou a montar uma holding do começo ao fim, ou ainda não pegou nenhum caso?',
    nota: 'Ouvir primeiro. Só depois falar do método.',
  },
  {
    gatilho: '"Foi cliente / não sei captar"',
    resposta: 'Entendi. E hoje, quando alguém te procura pra outro assunto e você percebe que a família tem patrimônio, você chega a levantar o tema de holding ou deixa passar?',
  },
  {
    gatilho: '"Quanto custa?"',
    resposta: 'São {valor}, {condição}. Antes de te mandar o link, me diz só uma coisa: você pretende atender holding como área principal ou como um serviço a mais no que você já faz?',
    nota: 'Responder o preço na hora, sem rodeio, com a oferta vigente. Enrolar destrói a confiança.',
  },
  {
    gatilho: '"Tá caro"',
    resposta: 'Olhar a ficha antes. Valor declarado alto: "O valor não parece ser o ponto. O que mais tá pesando?" Valor baixo: não brigar com o valor nem dar desconto por conta própria; perguntar se pretende fazer disso uma frente de trabalho.',
    nota: 'Nunca prometer faturamento, retorno ou número de clientes.',
  },
  {
    gatilho: '"Vou pensar"',
    resposta: 'Tranquilo. Te chamo {dia da semana} de manhã pra saber o que você decidiu, pode ser?',
    nota: 'Marcar dia e cumprir. "Vou pensar" sem data é "não" com educação.',
  },
  {
    gatilho: 'Sem resposta em 24 h',
    resposta: '{Nome}, só pra não deixar em aberto: prefere que eu te explique por aqui ou prefere que eu não insista? Qualquer uma das duas tá ok.',
    nota: 'Um toque só. Sem resposta ao segundo toque, encerrar como "Sem resposta".',
  },
];

export const CUIDADOS_WHATSAPP: string[] = [
  'Teto de 30 a 50 conversas novas por dia, por número.',
  'Intervalo irregular de 1 a 2 minutos entre mensagens, em horário comercial.',
  'Áudio: no máximo 5 encaminhamentos por vez, espaçados.',
  'Nunca contornar restrição da Meta. Número restrito para e avisa a Mensageria.',
  'Só pelo número oficial do comercial, nunca pelo WhatsApp pessoal.',
];
