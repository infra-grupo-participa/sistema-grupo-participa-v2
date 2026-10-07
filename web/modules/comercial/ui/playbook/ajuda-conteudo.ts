// Conteúdo da central de ajuda do Comercial, em dado tipado (a tela só desenha).
// Junta duas coisas: (1) como usar o sistema, tela a tela, escrito a partir do que o código de
// web/modules/comercial faz hoje; (2) o playbook de vendas de conteudo.ts, inteiro, sem perder nada.
// Regras de escrita: frase curta, PT-BR simples, sem jargão técnico. Função que não existe ainda é "em breve",
// nunca descrita como pronta. Ao mudar uma tela, atualizar a seção dela aqui (o teste cobra a estrutura).
import { GRUPOS, SECOES, type Atalho, type Bloco, type LinkFerramenta } from './conteudo';
import type { Pesquisavel } from './busca';

export type ParteKey = 'comece' | 'sistema' | 'modulos' | 'playbook' | 'faq' | 'glossario';

export interface Parte {
  key: ParteKey;
  /** Âncora do começo da parte (#parte-...). */
  ancora: string;
  titulo: string;
  /** Uma linha para o cartão da entrada. */
  chamada: string;
  /** Uma ou duas linhas no topo da parte. */
  descricao: string;
  icone: string;
}

export interface SecaoAjuda extends Pesquisavel {
  parte: ParteKey;
  /** Subtítulo de agrupamento dentro da parte (ex.: "Fundamentos" no playbook). */
  subgrupo?: string;
  icone?: string;
  ferramentas?: LinkFerramenta[];
  /** Assunto inteiro ainda não existe no sistema. */
  emBreve?: boolean;
}

export const PARTES: Parte[] = [
  { key: 'comece', ancora: 'parte-comece-aqui', titulo: 'Comece aqui', icone: 'star', chamada: 'Primeiro dia e rotina', descricao: 'O primeiro dia do vendedor e do gestor no sistema, a rotina diária e os atalhos que poupam tempo.' },
  { key: 'sistema', ancora: 'parte-como-funciona', titulo: 'Como o sistema funciona', icone: 'sliders', chamada: 'O mapa e as peças', descricao: 'O mapa das telas, o caminho de um lead do começo ao fim, as peças do CRM e o que ainda vem por aí.' },
  { key: 'modulos', ancora: 'parte-modulos', titulo: 'Módulo a módulo', icone: 'dashboard', chamada: 'Cada tela, passo a passo', descricao: 'Cada tela do Comercial: para que serve, passo a passo, dicas, erros comuns e o atalho para abrir.' },
  { key: 'playbook', ancora: 'parte-playbook', titulo: 'Playbook de vendas', icone: 'notebook', chamada: 'Regras, scripts e processos', descricao: 'O playbook completo do Comercial: regras inegociáveis, funil, distribuição, conversa, scripts e processos das áreas. O playbook ainda cita o Clint, o CRM em uso hoje; as regras valem igual neste sistema.' },
  { key: 'faq', ancora: 'parte-perguntas', titulo: 'Perguntas frequentes', icone: 'message', chamada: 'Dúvidas do dia a dia', descricao: 'As dúvidas que mais aparecem, com resposta curta e o caminho na tela.' },
  { key: 'glossario', ancora: 'parte-glossario', titulo: 'Glossário', icone: 'list-checks', chamada: 'O que cada termo quer dizer', descricao: 'Os termos do sistema e os termos de vendas que o Comercial usa.' },
];

// Atalhos para os blocos (deixam o conteúdo legível).
const p = (texto: string): Bloco => ({ tipo: 'paragrafo', texto });
const h = (texto: string): Bloco => ({ tipo: 'subtitulo', texto });
const ul = (itens: string[], titulo?: string): Bloco => ({ tipo: 'lista', itens, titulo });
const tab = (colunas: string[], linhas: string[][], titulo?: string): Bloco => ({ tipo: 'tabela', colunas, linhas, titulo });
const passos = (titulo: string, itens: string[]): Bloco => ({ tipo: 'passos', titulo, itens });
const dicas = (itens: string[]): Bloco => ({ tipo: 'dicas', itens });
const cuidados = (itens: string[]): Bloco => ({ tipo: 'cuidados', itens });
const emBreve = (titulo: string, texto: string): Bloco => ({ tipo: 'em_breve', titulo, texto });
const pergunta = (q: string, resposta: string, link?: LinkFerramenta): Bloco => ({ tipo: 'pergunta', pergunta: q, resposta, link });
const atalhos = (itens: Atalho[]): Bloco => ({ tipo: 'atalhos', itens });

// ─────────────────────────────────────────────────────────────────────────────
// Telas do sistema (fonte única dos links)
// ─────────────────────────────────────────────────────────────────────────────

export const TELAS = {
  inicio: { rotulo: 'Início do Comercial', href: '/comercial' },
  funil: { rotulo: 'Funil de vendas', href: '/comercial/funil' },
  conversas: { rotulo: 'Conversas', href: '/comercial/conversas' },
  atividades: { rotulo: 'Atividades', href: '/comercial/atividades' },
  contatos: { rotulo: 'Contatos', href: '/comercial/contatos' },
  recuperacao: { rotulo: 'Recuperação', href: '/comercial/recuperacao' },
  disparos: { rotulo: 'Disparos', href: '/comercial/disparos' },
  relatorios: { rotulo: 'Relatórios', href: '/comercial/relatorios' },
  dashboards: { rotulo: 'Dashboards', href: '/comercial/relatorios#dashboards' },
  fechamento: { rotulo: 'Fechamento do dia', href: '/comercial/relatorios#fechamento' },
  equipe: { rotulo: 'Performance da equipe', href: '/comercial/relatorios#equipe' },
  produtos: { rotulo: 'Produtos e ofertas', href: '/comercial/produtos' },
  registro: { rotulo: 'Registro', href: '/comercial/registro' },
  configuracoes: { rotulo: 'Configurações', href: '/comercial/configuracoes' },
  distribuicao: { rotulo: 'Distribuição', href: '/comercial/configuracoes#distribuicao' },
  motivos: { rotulo: 'Motivos de perda', href: '/comercial/configuracoes#motivos' },
  links: { rotulo: 'Links rastreáveis', href: '/comercial/configuracoes#links' },
  notificacoes: { rotulo: 'Preferências de aviso', href: '/comercial/configuracoes#notificacoes' },
  integracoes: { rotulo: 'Integrações', href: '/comercial/configuracoes#integracoes' },
  claude: { rotulo: 'Conectar ao Claude', href: '/comercial/configuracoes#mcp' },
  socialSelling: { rotulo: 'Social selling', href: '/comercial/social-selling' },
} satisfies Record<string, LinkFerramenta>;

// ─────────────────────────────────────────────────────────────────────────────
// Módulo a módulo: um molde só para toda tela (para que serve, o que tem, passo a passo, dicas, erros, em breve)
// ─────────────────────────────────────────────────────────────────────────────

interface Modulo {
  id: string;
  titulo: string;
  icone: string;
  resumo: string;
  telas: LinkFerramenta[];
  sinonimos?: string[];
  paraQue: string[];
  naTela: string[];
  comoFazer: { titulo: string; itens: string[] }[];
  soGestor?: string[];
  dicas: string[];
  cuidados: string[];
  emBreve?: { titulo: string; texto: string }[];
  extra?: Bloco[];
}

function modulo(m: Modulo): SecaoAjuda {
  return {
    id: m.id,
    titulo: m.titulo,
    parte: 'modulos',
    icone: m.icone,
    resumo: m.resumo,
    sinonimos: m.sinonimos,
    ferramentas: m.telas,
    blocos: [
      h('Para que serve'),
      ...m.paraQue.map(p),
      ul(m.naTela, 'O que tem na tela'),
      ...m.comoFazer.map((c) => passos(c.titulo, c.itens)),
      ...(m.soGestor ? [ul(m.soGestor, 'Só para o gestor')] : []),
      ...(m.extra ?? []),
      dicas(m.dicas),
      cuidados(m.cuidados),
      ...(m.emBreve ?? []).map((e) => emBreve(e.titulo, e.texto)),
    ],
  };
}

const MODULOS: SecaoAjuda[] = [
  modulo({
    id: 'modulo-inicio',
    titulo: 'Início do Comercial',
    icone: 'home',
    resumo: 'Seu painel do dia: o que pede ação agora, seus números e o seu painel montado do seu jeito.',
    telas: [TELAS.inicio],
    sinonimos: ['meu dia', 'painel', 'home', 'visão do time', 'agir agora', 'controle das 9h', 'widget'],
    paraQue: [
      'É a primeira tela do dia. Mostra o que precisa da sua ação agora, em ordem de urgência.',
      'O vendedor vê **"Meu dia"**. O gestor vê **"Visão do time"** e pode olhar o painel de cada vendedor.',
    ],
    naTela: [
      '**Números do dia:** abordados, responderam, em negociação, vendas e receita. Contam de meia-noite até agora.',
      '**Minha carga:** negócios abertos, prazo crítico, sem próximo passo, atividades atrasadas e conversas esperando. Fica vermelho quando passa de zero.',
      '**Agir agora:** a lista do que fazer, em três grupos: **Atrasado**, **Agora** e **Hoje**. Mostra até 10; "Ver todos" mostra o resto. O que está atrasado nunca fica escondido.',
      '**Meu painel:** cartões e gráficos que você escolhe (até 12).',
      '**Os 9 inegociáveis do playbook:** versão de bolso, recolhida. Clique em "Mostrar".',
    ],
    comoFazer: [
      {
        titulo: 'Como trabalhar a lista "Agir agora"',
        itens: [
          'Comece de cima. A lista já vem na ordem certa: crítico, conversa esperando, atividade atrasada, atenção e o que vence hoje.',
          'Passe o mouse na linha para ver as ações.',
          'Atividade: clique em **"Concluir"**, escolha como foi e agende o próximo passo.',
          'Conversa esperando: clique em **"Responder"**. Você vai direto para a conversa.',
          'Negócio: clique em **"Abrir"** (ou no nome) para abrir a ficha.',
          'Quando a lista mostrar "Nada pendente agora", você está em dia.',
        ],
      },
      {
        titulo: 'Como montar o seu painel',
        itens: [
          'Em "Meu painel", clique em **"Personalizar"**.',
          'Clique em **"Adicionar widget"**. Dê um título, escolha a métrica, o visual (número, barras, lista, linha ou pizza) e o período.',
          'Arraste para mudar a ordem. Use o lápis para editar e a lixeira para remover.',
          'Clique em **"Salvar painel"**. Nada grava antes disso. "Restaurar padrão" volta ao painel original.',
        ],
      },
    ],
    soGestor: [
      'No seletor **"Ver"**, escolha "Time inteiro" ou um vendedor. Para voltar, clique em **"Voltar ao time"**.',
      '**Controle das 9h:** quatro listas que devem estar zeradas: negócios sem dono, perdidos hoje por "já atendido por outro vendedor", sem próxima atividade e fichas de disparo esperando aprovação.',
      '**Carga por vendedor:** abertos, críticos, sem próximo passo, atrasadas e vendas de hoje de cada pessoa. Clique no nome para ver o painel dela.',
      'O gestor pode editar o painel de um vendedor.',
    ],
    dicas: [
      'Abra o Início assim que chegar. Ele responde "o que eu faço primeiro?".',
      'O ícone (i) ao lado de cada número explica como ele é contado.',
      'Ao passar o mouse num número do dia, aparece a comparação: o time, para o vendedor; você, para o gestor.',
    ],
    cuidados: [
      'Concluir uma atividade sem agendar a próxima deixa o negócio sem próximo passo. O sistema avisa, mas não impede.',
      'Mudou o painel e não salvou? Ao cancelar, o sistema pergunta se quer descartar.',
    ],
  }),
  modulo({
    id: 'modulo-funil',
    titulo: 'Funil de vendas',
    icone: 'kanban',
    resumo: 'O quadro de negócios por etapa, um funil por vez. Arraste o card para mover.',
    telas: [TELAS.funil],
    sinonimos: ['kanban', 'pipeline', 'pipe', 'quadro', 'etapa', 'mover', 'arrastar', 'card', 'novo negócio', 'projeto', 'agrupador', 'atm', 'aula ao vivo', 'live'],
    paraQue: [
      'Mostra cada negócio na etapa em que está, do primeiro contato ao fechado. Cada produto tem seus funis, reunidos num **agrupador**.',
      'Funil **manual** é onde o comercial trabalha (a "Venda ativa"). Funil **automático** é preenchido pela Hotmart (carrinho abandonado, cartão recusado e outros); nele não se cria negócio à mão.',
    ],
    naTela: [
      '**Trocar funil:** lista os funis por produto, com quantos abertos e um ponto vermelho onde há prazo crítico. Um ponto vermelho no próprio botão avisa crítico em outro funil.',
      '**Números:** abertos, valor em negociação, prazo crítico, sem próximo passo e sem dono. Os três últimos funcionam como filtro: clique para ligar e desligar.',
      '**Filtros:** dono ("Meus negócios", "Sem dono", cada vendedor) e busca por nome, e-mail ou telefone.',
      '**Colunas:** uma por etapa, com quantidade, valor e críticos. Ao passar o mouse no topo, aparece o critério para passar e o prazo da etapa.',
      '**Card:** nome, valor, produto, tempo na etapa, próximo passo e dono. Uma faixa colorida mostra o sinal mais urgente.',
      'No celular, aparece uma coluna por vez. Escolha a etapa no seletor.',
    ],
    comoFazer: [
      {
        titulo: 'Como mover um negócio de etapa',
        itens: [
          'Arraste o card para a coluna da etapa nova. Ou use o menu ⋯ do card, em **"Mover para"**.',
          'Etapa que pede campo vazio aparece com cadeado no menu, e a coluna não aceita o card (fica apagada enquanto você arrasta). Abra a ficha, preencha e salve.',
          'Mova de novo. Os campos das etapas anteriores também contam, mesmo se você pular etapa.',
          'Pode voltar uma etapa, se os campos até ela estiverem preenchidos.',
        ],
      },
      {
        titulo: 'Como criar um negócio',
        itens: [
          'Num funil manual, clique em **"Novo negócio"**.',
          'Busque o contato pelo nome, e-mail ou telefone. Veja o dono ao lado de cada nome.',
          'Escolha o funil e, se houver, a campanha de entrada.',
          'Confira a prévia do dono: o dono do contato, ou a distribuição se o contato não tiver dono.',
          'Clique em **"Criar negócio"**. Ele entra na primeira etapa e a ficha abre.',
        ],
      },
      {
        titulo: 'Ações rápidas no card',
        itens: [
          'Balão de conversa: abre a conversa do lead.',
          'Calendário: agenda o próximo passo.',
          'Menu ⋯: abrir ficha, copiar telefone ou mover para outra etapa.',
        ],
      },
    ],
    soGestor: [
      '**Novo funil:** assistente em 6 passos (ponto de partida, geral, etapas, campanhas e integrações, distribuição e revisão). Dá para partir de um modelo ou do zero.',
      '**Editar funil** (engrenagem): nome, etapas, prazos, campos obrigatórios, campanhas e distribuição própria. Também arquiva o funil.',
      '**Comecei um novo projeto:** escolha o tipo (lançamento, webinar, seminário, evento, ascensão, ATM), dê o nome e o sistema cria de uma vez os funis certos, com a chave do projeto nas campanhas.',
      '**ATM (aula ao vivo de entrada):** uma live sobre a base que já existe, sem captação paga, para o HT ou para o Seminário ATM (Sessão de Viabilidade): escolha o produto. Cria a **Ativação comercial (pré-checkout)**: lista recebida, contato feito (recebeu e assistiu ao caso), convidado para a live, presença confirmada, ofertado no fechamento, aguardar pagamento e fechado. E o **Fechamento da live**, automático pela Hotmart, porque a condição vale só até 23h59 do dia.',
      'Regras ao salvar: pelo menos 2 etapas, nomes sem repetir, uma etapa de ganho e ela por último, prazo crítico maior que o de atenção, distribuição própria somando 100%.',
      'Etapa com negócio aberto não pode ser removida. Funil com negócio aberto não pode ser arquivado.',
    ],
    dicas: [
      'Os cards já vêm em ordem de urgência: crítico primeiro, depois quem está parado há mais tempo.',
      'Use "Meus negócios" para ver só a sua carteira.',
      'Um link com o negócio abre o funil certo e a ficha dele. Bom para mandar no Slack.',
    ],
    cuidados: [
      'Ninguém move para **Fechado** à mão. Ganho é pagamento aprovado na Hotmart.',
      'Negócio perdido não aparece no quadro. Procure pela ficha do contato.',
      'Lead que não é seu não se toca, e o quadro trava: o card de outro dono mostra um cadeado, não arrasta, não agenda e não tem "Mover para". Negócio sem dono também fica travado para o vendedor até o gestor definir quem atende.',
      'Um contato só tem um negócio aberto por funil. Se já existe, o funil aparece desativado na criação.',
    ],
    emBreve: [
      { titulo: 'Negócios criados pela Hotmart', texto: 'Os funis automáticos vão nascer sozinhos dos eventos da Hotmart (carrinho abandonado, cartão recusado, compra aprovada) e o ganho vai fechar sozinho com o pagamento aprovado. A ligação com a Hotmart está a conectar.' },
    ],
  }),
  modulo({
    id: 'modulo-ficha-negocio',
    titulo: 'Ficha do negócio',
    icone: 'briefcase',
    resumo: 'Tudo sobre uma oportunidade: próximo passo, etapa, campos, atividades, notas e conversa.',
    telas: [TELAS.funil],
    sinonimos: ['negócio', 'oportunidade', 'deal', 'perdido', 'perder', 'trocar dono', 'campos obrigatórios', 'nota', 'gaveta'],
    paraQue: [
      'A ficha abre de lado quando você clica num negócio, no Funil, no Início, nas Atividades ou nas Conversas.',
      'É onde você registra o que aconteceu e decide o próximo passo.',
    ],
    naTela: [
      '**Cabeçalho:** nome, telefone, produto, origem e dono. Botões "Conversa" e copiar telefone. Selos como "Ganho", "Perdido", tempo na etapa, "Não quer contato" e "Já é aluno".',
      '**Resumo:** próximo passo, trilha das etapas, campos do negócio, dados do negócio e do contato, e outros negócios da mesma pessoa.',
      '**Atividades:** a lista de toques, com as atrasadas marcadas.',
      '**Linha do tempo:** notas internas e o histórico do negócio.',
      '**Conversa:** as mensagens do WhatsApp, só para ler.',
      '**Alterações:** quem mudou o quê e quando.',
      '**Rodapé:** "Marcar como perdido", "Próxima atividade" e "Mover para" a próxima etapa.',
    ],
    comoFazer: [
      {
        titulo: 'Como preencher os campos e avançar',
        itens: [
          'Na aba Resumo, veja "Campos do negócio". Os exigidos aparecem abertos.',
          'Vermelho "obrigatório" quer dizer que já devia estar preenchido. Amarelo "para <etapa>" é o que a próxima etapa pede.',
          'Preencha e clique em **"Salvar campos"**.',
          'Clique em **"Mover para <próxima etapa>"**. Enquanto faltar campo, o botão fica desligado e o que falta aparece escrito ao lado dele.',
        ],
      },
      {
        titulo: 'Como agendar o próximo passo',
        itens: [
          'Clique em **"Próxima atividade"** (ou "Agendar agora", se o aviso vermelho aparecer).',
          'Escolha o tipo: ligação, WhatsApp, e-mail, reunião ou tarefa.',
          'Escreva o que fazer e quando. O padrão é amanhã às 10h.',
          'Clique em **"Agendar"**. A atividade fica no nome do dono do negócio.',
        ],
      },
      {
        titulo: 'Como marcar um negócio como perdido',
        itens: [
          'Clique em **"Marcar como perdido"**.',
          'Escolha o motivo na lista. Motivo fora da lista não existe. A nota é opcional.',
          'Leia o aviso do motivo. Alguns mandam a pessoa para a lista de bloqueio; outros avisam o gestor.',
          'Clique em **"Confirmar perda"**. As atividades abertas do negócio são canceladas.',
        ],
      },
      {
        titulo: 'Como registrar uma nota',
        itens: [
          'Abra a aba **Linha do tempo**.',
          'Escreva a objeção, o combinado ou o contexto.',
          'Clique em **"Registrar"**. Se não está no CRM, não existe.',
        ],
      },
    ],
    soGestor: [
      '**Trocar dono:** no bloco "Negócio", clique em "Trocar" (o botão só aparece para o gestor). Novo dono e motivo são obrigatórios. O contato e as atividades abertas vão junto.',
    ],
    dicas: [
      'Ao concluir uma atividade, use **"Concluir e agendar próxima"**. É o jeito mais rápido de nunca ficar sem próximo passo.',
      'Na trilha de etapas, o cadeado mostra onde falta campo.',
      'Origem do lead não se edita: vem da integração.',
    ],
    cuidados: [
      'Aviso vermelho "Sem próxima atividade com data" é violação do inegociável 4. Agende na hora.',
      'O sistema não marca perdido sozinho. Se o lead esgotou, marque você, com o motivo certo.',
      '"Já atendido por outro vendedor" é falha de distribuição. Só use quando for verdade: o gestor é avisado.',
      'Negócio de outro vendedor abre só para leitura: sem mover, editar campos, agendar, concluir, anotar ou perder. O mesmo vale, para o vendedor, no negócio sem dono. Peça ao gestor para transferir.',
    ],
  }),
  modulo({
    id: 'modulo-conversas',
    titulo: 'Conversas',
    icone: 'message',
    resumo: 'A caixa do WhatsApp oficial: quem espera há mais tempo vem primeiro.',
    telas: [TELAS.conversas],
    sinonimos: ['whatsapp', 'mensagem', 'chat', 'caixa', 'responder', 'template', 'janela de 24 horas', 'resposta rápida'],
    paraQue: [
      'Reúne as conversas do número oficial do comercial, cada uma ligada ao dono do lead.',
      'A regra é simples: responda primeiro quem espera há mais tempo.',
    ],
    naTela: [
      '**Caixa agora:** sem resposta, além do prazo (15 min em horário comercial), não lidas e sem dono.',
      '**Lista à esquerda:** filtros "Minhas", "Todas" e "Sem dono", busca e a ordem por urgência. Cada item mostra há quanto tempo o lead espera.',
      '**Conversa no meio:** mensagens por dia, com o status (enviada, entregue, lida, falhou) e o selo da janela de 24 horas.',
      '**Painel à direita:** dados do contato, dono, tags e os negócios abertos.',
      '**Botão "Playbook":** as regras da conversa, sempre à mão.',
    ],
    comoFazer: [
      {
        titulo: 'Como responder um lead',
        itens: [
          'Clique na conversa no topo da lista "Minhas".',
          'Com a janela aberta, escreva no campo. Use o primeiro nome do lead e sem emoji.',
          'Digite **"/"** com o campo vazio para ver as respostas rápidas do playbook.',
          'Envie com **Ctrl + Enter** (no Mac, ⌘ + Enter).',
          'Termine com o próximo passo: clique em **"Próximo passo"** e agende.',
        ],
      },
      {
        titulo: 'Quando a janela de 24 horas fechou',
        itens: [
          'O selo mostra "Janela fechada". Mensagem livre não sai mais.',
          'Escolha um **template aprovado**. Confira a prévia com as variáveis preenchidas.',
          'Se faltar dado do contato para uma variável, complete o contato ou escolha outro template.',
          'Clique em **"Enviar template"**.',
        ],
      },
    ],
    soGestor: [
      'O gestor pode escrever em qualquer conversa.',
      'Conversa sem dono: clique em **"Atribuir dono"**, escolha o vendedor e o motivo. O vendedor passa a ser dono do contato e dos negócios abertos sem dono.',
    ],
    dicas: [
      'Abrir a conversa marca como lida só para o dono.',
      'O selo da janela fica amarelo quando faltam menos de 2 horas. Responda antes de fechar.',
      'Sem negócio aberto? "Se não está no CRM, não existe." Abra pela ficha do contato.',
    ],
    cuidados: [
      'Lead de outro vendedor fica só para leitura. Lead que não é seu não se toca: peça ao gestor para transferir.',
      'Lead sem dono também fica só para leitura do vendedor. O gestor atribui antes.',
      'Quem pediu para não receber contato não recebe nenhuma mensagem.',
      'Emoji não bloqueia o envio, mas o playbook pede mensagem sem emoji.',
    ],
    emBreve: [
      { titulo: 'WhatsApp oficial conectado', texto: 'O envio e o recebimento de verdade entram quando o número oficial for conectado ao sistema. Hoje a caixa é de demonstração: o que você envia aqui não sai para o lead.' },
    ],
  }),
  modulo({
    id: 'modulo-atividades',
    titulo: 'Atividades',
    icone: 'list-checks',
    resumo: 'A agenda de toques: o que fazer hoje, o que atrasou e o que vem.',
    telas: [TELAS.atividades],
    sinonimos: ['agenda', 'tarefa', 'ligação', 'cadência', 'atrasada', 'próximo passo', 'follow up', 'concluir'],
    paraQue: [
      'Cada atividade é um toque com data: ligação, WhatsApp, e-mail, reunião ou tarefa.',
      'Nenhum negócio aberto fica sem a próxima atividade. Esta tela é onde você cumpre isso.',
    ],
    naTela: [
      '**Filtros:** dono ("Minhas atividades", "Todo o time", cada vendedor) e tipo.',
      '**Agenda de hoje:** para hoje, atrasadas, concluídas hoje e ligações feitas de agendadas.',
      '**Abas:** Hoje (com as atrasadas no topo e o dia dividido em manhã, tarde e noite), Atrasadas, Próximas e Concluídas.',
      '**Cada linha:** o que fazer, contato, produto, etapa, dia da cadência, dono e a hora (vermelho quando venceu).',
      '**"Cadência padrão":** os toques de cada dia para quem não respondeu ao primeiro contato.',
    ],
    comoFazer: [
      {
        titulo: 'Como concluir uma atividade',
        itens: [
          'Clique em **"Concluir"** na linha.',
          'Escolha como foi: Respondeu, Não atendeu, Pediu retorno ou Caixa postal. Um clique já conclui. Ou use "Outro resultado…".',
          'Se o negócio segue aberto, abre o **"Agendar próximo passo"** já preenchido com a sugestão certa.',
          'Confira e clique em **"Agendar"**.',
        ],
      },
      {
        titulo: 'Como criar uma atividade solta',
        itens: [
          'Clique em **"Nova atividade"**.',
          'Escolha o negócio. O vendedor vê os próprios negócios abertos.',
          'Escolha o tipo, escreva o que fazer e quando.',
          'Clique em **"Agendar"**.',
        ],
      },
    ],
    extra: [
      tab(['Dia', 'Toques da cadência'], [
        ['Dia 1', 'WhatsApp de abordagem e ligação'],
        ['Dia 2', 'Ligação e WhatsApp curto de retomada'],
        ['Dia 3', 'WhatsApp com prova (depoimento, caso)'],
        ['Dia 4', 'Ligação e WhatsApp'],
        ['Dia 5', 'Mensagem de encerramento'],
      ], 'A cadência padrão, de bolso'),
    ],
    dicas: [
      'O próximo passo sugerido segue a cadência: se o lead não respondeu, vem o próximo toque do dia certo.',
      'Zere as atrasadas até as 18h45. É o horário do CRM em dia.',
      'O vendedor pode olhar "Todo o time" só para ler.',
    ],
    cuidados: [
      '"Agora não" fecha sem agendar. O sistema só lembra; o negócio fica sem próximo passo.',
      'Só o dono (ou o gestor) conclui uma atividade.',
      'Depois da proposta, são até 5 tentativas cruzando ligação e WhatsApp. Depois, perdido com o motivo "Tentativas de contato esgotadas".',
    ],
  }),
  modulo({
    id: 'modulo-contatos',
    titulo: 'Contatos',
    icone: 'contact',
    resumo: 'A base única de pessoas, com dono, jornada completa e negócios.',
    telas: [TELAS.contatos],
    sinonimos: ['pessoa', 'lead', 'cliente', 'cadastro', 'buscar', 'dono', 'jornada', 'duplicado', 'opt-out', 'aluno', 'ficha do contato'],
    paraQue: [
      'Cada pessoa aparece uma vez só. Ela é reconhecida pelo e-mail ou pelo DDD com os últimos 8 dígitos do telefone.',
      '**Antes de abordar alguém, busque aqui.** Se a pessoa tem dono e não é você, não toque.',
    ],
    naTela: [
      '**Números:** contatos, sem dono (meta zero), não querem contato e já são alunos. Os três últimos filtram a lista.',
      '**Busca:** nome, e-mail ou final do telefone, sem se importar com acento ou formatação.',
      '**Filtros:** dono, perfil, UF, tags, só quem não quer contato, só quem já é aluno.',
      '**Lista:** pessoa, dono, negócios abertos, lançamentos e última interação. Ícones mostram possível duplicado, cadeado (não quer contato) e capelo (já é aluno).',
    ],
    comoFazer: [
      {
        titulo: 'Como conferir o dono antes de abordar',
        itens: [
          'Digite o final do telefone (4 dígitos ou mais) ou o e-mail na busca.',
          'Veja a coluna **Dono**. "Sem dono" em vermelho pede o gestor.',
          'Se o dono é outro vendedor, não fale com a pessoa. Avise o dono ou o gestor.',
        ],
      },
      {
        titulo: 'Como ler a ficha do contato',
        itens: [
          'Clique na pessoa. A ficha abre de lado.',
          'No topo: negócios abertos, lançamentos, compras, pago líquido e reembolsos.',
          'Aba **Jornada:** tudo o que a pessoa fez com a casa, por lançamento: inscrição, lista, pesquisa, grupo, checkout, compra, reembolso, negócio, conversa e disparo. Cada lançamento mostra como ela chegou (a campanha daquela entrada).',
          'Abas **Negócios**, **Dados**, **Conversa** e **Alterações** completam a ficha.',
          'Para abrir uma oportunidade, clique em **"Novo negócio"** no rodapé.',
        ],
      },
      {
        titulo: 'Como cadastrar um contato',
        itens: [
          'Clique em **"Novo contato"**.',
          'Preencha o nome e pelo menos telefone (com DDD) ou e-mail.',
          'Se o e-mail já existe, o sistema bloqueia e mostra a ficha da pessoa.',
          'Se o final do telefone já existe, confira. Só marque "É outra pessoa" se tiver certeza.',
          'Clique em **"Salvar contato"**.',
        ],
      },
    ],
    dicas: [
      'A busca por telefone aceita qualquer formato: com ou sem DDD, com ou sem traço.',
      'O botão "Conversa" na ficha leva direto à caixa de Conversas.',
      '"Pago líquido" já desconta reembolsos e chargebacks.',
    ],
    cuidados: [
      'Quem pediu para não receber contato não recebe negócio novo nem mensagem.',
      'Possível duplicado não é a mesma pessoa até alguém confirmar. Não junte por conta própria.',
      'CPF não entra no CRM.',
    ],
    emBreve: [
      { titulo: 'Cadastro gravado', texto: 'Hoje o contato novo vale só na tela (na demonstração, some ao recarregar). A gravação entra na próxima etapa do sistema.' },
    ],
  }),
  modulo({
    id: 'modulo-recuperacao',
    titulo: 'Recuperação',
    icone: 'target',
    resumo: 'Filas pós-lançamento com score de A a D: quem respondeu sem retorno vem primeiro.',
    telas: [TELAS.recuperacao],
    sinonimos: ['fila', 'score', 'faixa', 'sala de guerra', 'carrinho abandonado', 'boleto', 'cartão recusado', 'script de abordagem'],
    paraQue: [
      'Depois que o carrinho fecha, o Fechamento monta uma fila com quem esteve perto de comprar.',
      'Cada pessoa tem score de 0 a 100, faixa, responsável e status. A ordem já vem pronta.',
    ],
    naTela: [
      '**Fila e oferta vigente:** o seletor da fila e a oferta que vale nela.',
      '**Números:** na fila, em trabalho, ganhos, recuperação % e sem retorno.',
      '**Faixas:** A (60 ou mais), B (40 a 59), C (25 a 39), D (abaixo de 25).',
      '**Filtros:** busca, responsável ("Minha carteira"), status e sinal.',
      '**Lista:** pessoa, faixa e score, sinais (boleto em aberto, carrinho abandonado, cartão recusado, ficha completa e outros), responsável, status e o botão "Script".',
    ],
    comoFazer: [
      {
        titulo: 'Como trabalhar a fila',
        itens: [
          'Abra a fila e confira se tem **oferta vigente**. Sem oferta, ninguém aborda.',
          'Comece de cima. Quem respondeu e ficou sem retorno vem primeiro.',
          'Clique em **"Script"**. O sistema sugere a variante pelo sinal mais forte.',
          'Clique em **"Copiar mensagem"** e envie pelo número oficial.',
          'Mude o status: A abordar, Tentando contato, Em conversa, Vai comprar, Ganho. Ou uma saída: Sem resposta, Declinou, Sem interesse, Número inválido.',
        ],
      },
    ],
    soGestor: [
      'O gestor abre a tela vendo todos os responsáveis e muda o status de qualquer pessoa.',
    ],
    dicas: [
      'O script traz o roteiro de "quando a pessoa responder": foi a técnica, foi cliente, quanto custa, tá caro, vou pensar.',
      'Primeira mensagem: sem link, sem oferta, uma pergunta só.',
      'Sem resposta em 24 horas, um toque só. Sem resposta ao segundo, encerre como "Sem resposta".',
    ],
    cuidados: [
      'Faixas C e D ficam travadas enquanto houver alguém de A ou B em "A abordar".',
      'Só o responsável (ou o gestor) muda o status.',
      'Status "Ganho" é o seu registro. A venda só vale com pagamento aprovado na Hotmart.',
      'De 30 a 50 conversas novas por dia por número, com 1 a 2 minutos entre elas. Só pelo número oficial.',
    ],
  }),
  modulo({
    id: 'modulo-disparos',
    titulo: 'Disparos',
    icone: 'send',
    resumo: 'Ficha, aprovação, supressões, agenda e templates do disparo por API.',
    telas: [TELAS.disparos],
    sinonimos: ['disparo', 'api', 'ficha', 'supressão', 'template', 'agenda', 'aprovar', 'massa', 'campanha'],
    paraQue: [
      'Nenhum disparo por API sai sem ficha aprovada e registro no log. Esta tela é a ficha, a agenda e o log.',
      'A tela registra e aprova. Ela não envia a mensagem.',
    ],
    naTela: [
      '**Números:** aguardando aprovação, próximos 7 dias, conflitos de 48 horas, leitura % e resposta %.',
      '**Aba Fichas:** cada ficha com código, objetivo, data, operador, quantos recebem, status e resultado.',
      '**Aba Agenda:** últimos e próximos 7 dias, com os limites de envio.',
      '**Aba Templates:** os templates com categoria e situação (aprovado ou pendente). Só consulta.',
    ],
    comoFazer: [
      {
        titulo: 'Como montar uma ficha de disparo',
        itens: [
          'Clique em **"Nova ficha"**. Só quem opera disparo por API consegue.',
          '1 · Objetivo e produto.',
          '2 · Lista: o filtro e a quantidade.',
          '3 · Supressões: as quatro já vêm marcadas e não saem. O simulador mostra quantos saem em cada uma.',
          '4 · Template aprovado e número de envio.',
          '5 · Data, hora e operador. O padrão é amanhã às 10h.',
          '6 · Link rastreável: escreva a ação e confira o código de rastreio sugerido.',
          'Clique em **"Enviar para aprovação"**. Para guardar sem enviar, use "Salvar rascunho".',
        ],
      },
    ],
    soGestor: [
      'Ficha esperando aprovação mostra **"Aprovar"**, **"Reprovar"** e **"Agora não"**. Só o gestor vê esses botões.',
      'A ficha do gestor entra direto como aprovada ("Registrar ficha").',
    ],
    extra: [
      ul([
        'Quem está em "Negociar" ou "Aguardar pagamento".',
        'Quem recebeu disparo nas últimas 48 horas.',
        'Quem pediu para não receber.',
        'Quem já comprou o produto.',
      ], 'As quatro supressões obrigatórias'),
    ],
    dicas: [
      'O resumo ao lado diz o que falta para enviar.',
      'O código da ficha é o mesmo no template, no log e no link.',
      'Número oficial: até 250 conversas por dia pelo limite da Meta (1.000 depois da verificação). Fora da API: 30 a 50 por dia.',
    ],
    cuidados: [
      'Conflito de 48 horas (duas fichas do mesmo produto perto demais) não bloqueia, mas derruba a efetividade. Mude a data.',
      'Sem link rastreável, a ficha não sai.',
      'Template novo é aprovado pela Mensageria. Fora da janela de 24 horas, só sai template aprovado.',
    ],
    emBreve: [
      { titulo: 'Envio pelo sistema', texto: 'O disparo de verdade, com entregues, lidas e respostas voltando sozinhos, entra quando o número oficial for conectado.' },
    ],
  }),
  modulo({
    id: 'modulo-relatorios',
    titulo: 'Relatórios: fechamento do dia e funil',
    icone: 'chart',
    resumo: 'O número do dia pronto para o Slack e a conversão do funil por etapa.',
    telas: [TELAS.fechamento, { rotulo: 'Conversão do funil', href: '/comercial/relatorios#funil' }],
    sinonimos: ['fechamento', 'slack', 'relatório', 'conversão', 'perdidos por motivo', 'tempo parado', 'número do dia'],
    paraQue: [
      'Relatórios tem quatro abas: Dashboards, Fechamento do dia, Funil e Equipe. Aqui ficam as duas do dia a dia. Dashboards e Equipe têm seção própria.',
    ],
    naTela: [
      '**Fechamento do dia:** abordados, entraram em contato, responderam, em negociação e vendas com receita. Tabela por vendedor, vendas por produto e alertas do dia.',
      '**Funil:** conversão por etapa (quantos passaram da etapa anterior), tempo médio parado em cada etapa e perdidos por motivo.',
    ],
    comoFazer: [
      {
        titulo: 'Como mandar o fechamento do dia',
        itens: [
          'Deixe o CRM em dia até as 18h45.',
          'Abra **Relatórios › Fechamento do dia** e escolha "Hoje".',
          'Confira os alertas: sem próxima atividade, sem dono, atrasadas e perdidos do dia.',
          'Clique em **"Copiar para o Slack"** e cole no #comercial às 19h.',
        ],
      },
    ],
    dicas: [
      'Dá para ver outro dia em "Ontem" ou "Outra data".',
      'No Funil, escolha um produto para ver só ele. Só a "Venda ativa" entra na conta.',
      'Perdido em vermelho no fechamento é falha de processo: o gestor trata no mesmo dia.',
    ],
    cuidados: [
      'Para dias passados, "em negociação", "sem próxima atividade" e "sem dono" mostram o retrato de agora.',
      'O tempo parado na etapa é uma estimativa feita com os negócios abertos hoje.',
      'Venda só conta quando a Hotmart aprova o pagamento.',
    ],
  }),
  modulo({
    id: 'modulo-dashboards',
    titulo: 'Dashboards',
    icone: 'dashboard',
    resumo: 'Monte painéis com os números que você quer acompanhar, e compartilhe com o time.',
    telas: [TELAS.dashboards],
    sinonimos: ['dashboard', 'gráfico', 'widget', 'painel', 'modelo', 'compartilhar', 'métrica'],
    paraQue: [
      'Um dashboard é uma tela de números montada por você. Ele não muda os números: só escolhe como mostrar.',
    ],
    naTela: [
      'Chips **"Meus"** e **"Compartilhados comigo"** para escolher o dashboard. O último fica lembrado neste navegador.',
      'Quatro modelos prontos: **Visão do gestor**, **Meu dia**, **Funil e perdas** e **Recuperação**.',
      'Botões **"Novo dashboard"**, **"Duplicar"** e, para o dono e o gestor, **"Editar dashboard"**, **"Renomear"** e **"Excluir"**.',
    ],
    comoFazer: [
      {
        titulo: 'Como criar um dashboard',
        itens: [
          'Clique em **"Novo dashboard"**.',
          'Comece em branco ou de um modelo. Dê nome e, se quiser, descrição.',
          'Ligue **"Compartilhar com o time"** para todo o Comercial ver. Só você e o gestor editam.',
          'Clique em criar. Em branco, a grade já abre em edição.',
        ],
      },
      {
        titulo: 'Como editar',
        itens: [
          'Clique em **"Editar dashboard"**.',
          'Arraste uma métrica da biblioteca para a grade, ou clique nela. São 14 métricas, até 24 por dashboard.',
          'Arraste para mudar a ordem. Puxe a borda direita para mudar a largura.',
          'No menu do widget: editar propriedades (título, visual, período, agrupar, funil, vendedor, largura e altura), duplicar, mover ou remover.',
          'Clique em **"Salvar dashboard"**. Ctrl + Z desfaz; Ctrl + Shift + Z refaz.',
        ],
      },
    ],
    dicas: [
      'Quer mudar o dashboard de outra pessoa? Clique em **"Duplicar"**: a cópia é sua.',
      'O período compara com o período anterior. Métricas que são retrato do momento não mudam com o período.',
    ],
    cuidados: [
      'O vendedor vê sempre os próprios números. O filtro por vendedor vale para o gestor.',
      'Excluir apaga só a tela montada. Os números continuam.',
    ],
  }),
  modulo({
    id: 'modulo-equipe',
    titulo: 'Performance da equipe',
    icone: 'users',
    resumo: 'Ranking, cartão por vendedor e detalhe para o 1:1.',
    telas: [TELAS.equipe],
    sinonimos: ['equipe', 'time', 'ranking', 'vendedor', '1:1', 'one on one', 'desempenho', 'performance'],
    paraQue: [
      'Mostra como cada vendedor está no período, comparado com o período anterior e com a média do time.',
    ],
    naTela: [
      '**Período:** hoje, 7 dias, 30 dias, mês ou datas escolhidas.',
      '**Time no período:** vendas, receita, conversão, tempo até o 1º contato e atrasadas.',
      '**Ranking** por volume (receita), conversão, qualidade e disciplina. Cada critério tem o (i).',
      '**Cartão por vendedor:** selos de alerta (fila parada, conversão abaixo do time, primeiro contato lento, carga alta, perda por falha de processo) e de destaque.',
      '**Detalhe:** funil pessoal comparado ao time, tempo parado por etapa, atividades por tipo, horário em que trabalha, cadência cumprida, perdidos, vendas, carteira e conversas sem resposta.',
    ],
    comoFazer: [
      {
        titulo: 'Como preparar um 1:1',
        itens: [
          'Abra **Relatórios › Equipe** e escolha o período.',
          'No cartão do vendedor, clique em **"Detalhe"**.',
          'Olhe os selos de alerta e o funil pessoal comparado ao time.',
          'O endereço da página guarda o vendedor: dá para mandar o link.',
        ],
      },
    ],
    dicas: [
      'Disciplina = atividades no prazo, com desconto por atrasada e por negócio sem próximo passo.',
      'Conversão só entra com um mínimo de negócios encerrados no período.',
    ],
    cuidados: [
      'O critério "Qualidade" ainda é provisório.',
      'As anotações de 1:1 ainda não gravam: somem ao recarregar.',
    ],
  }),
  modulo({
    id: 'modulo-produtos',
    titulo: 'Produtos e ofertas',
    icone: 'wallet',
    resumo: 'O espelho da Hotmart: qual oferta vender hoje e o link certo do checkout.',
    telas: [TELAS.produtos],
    sinonimos: ['produto', 'oferta', 'preço', 'link de pagamento', 'checkout', 'hotmart', 'oferta vigente', 'condição'],
    paraQue: [
      'Responde a pergunta "qual oferta eu vendo hoje?".',
      'Produto e oferta nascem na Hotmart. O sistema não cria nenhum dos dois: ele só marca o que o comercial vende.',
    ],
    naTela: [
      '**Números:** produtos no comercial, ofertas vigentes, fora do catálogo e produtos sem oferta vigente.',
      '**O que vender hoje:** por produto, só as ofertas que valem, com condição, código, preço, pagamento e validade. Botões para copiar o link e abrir o checkout.',
      '**Produtos:** todos os produtos da Hotmart, com filtros por conta, família e busca.',
      '**Fora do catálogo:** códigos que apareceram em vendas mas não estão cadastrados.',
      '**Cadastrar pela Hotmart:** cole o link do checkout ou o código da oferta para achar o produto.',
    ],
    comoFazer: [
      {
        titulo: 'Como pegar o link certo para o lead',
        itens: [
          'Abra a aba **"O que vender hoje"**.',
          'Ache o produto. A oferta principal vem primeiro.',
          'Leia a condição e a validade.',
          'Clique em copiar link. **Copie daqui, nunca de conversa antiga.**',
        ],
      },
    ],
    soGestor: [
      '**Vincular ao comercial:** dê o nome que o comercial usa e a escada (A, serviço do escritório; B, infoproduto).',
      '**Marcar oferta vigente:** na ficha do produto, ligue "Vigente", escreva a condição (obrigatória), a validade e o uso. Clique em "Salvar oferta".',
      '**Desvincular:** as ofertas somem para o vendedor; o produto continua na Hotmart.',
    ],
    dicas: [
      'Produto ou oferta novos: crie na Hotmart, na conta certa (Academy ou Escritório), espere a sincronização ou cole o link, e vincule.',
      'Link sem código de oferta? Copie o link do checkout, não o da página de vendas.',
    ],
    cuidados: [
      'Produto sem oferta vigente: não aborde até o gestor definir.',
      'Venda com código fora do catálogo não vira pagamento no sistema. Catalogue no mesmo dia.',
      'Nenhuma condição fora da oferta vigente (inegociável 8).',
    ],
  }),
  modulo({
    id: 'modulo-registro',
    titulo: 'Registro',
    icone: 'clipboard',
    resumo: 'O log de tudo que foi feito no CRM: quem, o quê, onde e quando.',
    telas: [TELAS.registro],
    sinonimos: ['log', 'histórico', 'auditoria', 'alterações', 'quem mudou', 'exportar', 'csv'],
    paraQue: [
      'Toda alteração no CRM entra aqui: mover etapa, trocar dono, marcar perdido, criar, editar, aprovar, enviar.',
      'O registro não se edita nem se apaga.',
    ],
    naTela: [
      '**Números:** alterações no período, pessoas que alteraram, negócios movidos e perdas registradas. Os dois últimos filtram.',
      '**Filtros:** período, pessoa (ou "Sistema"), tipo de ação, entidade e busca no resumo.',
      '**Lista por dia:** autor, ação, hora e resumo. "Ver detalhes" mostra cada campo com antes e depois.',
      '**"Exportar CSV":** baixa o que está filtrado.',
    ],
    comoFazer: [
      {
        titulo: 'Como descobrir quem mudou um negócio',
        itens: [
          'Abra a ficha do negócio e a aba **Alterações**. Ou abra o **Registro**.',
          'Filtre por entidade "Negócio" e busque pelo nome.',
          'Clique em **"Ver detalhes"** para ver o antes e o depois.',
        ],
      },
    ],
    dicas: [
      'A aba "Alterações" das fichas tem o link "Ver registro completo".',
    ],
    cuidados: [
      'O gestor vê tudo. O vendedor vê o que fez e o que tocou os negócios e contatos dele.',
    ],
  }),
  modulo({
    id: 'modulo-configuracoes',
    titulo: 'Configurações',
    icone: 'sliders',
    resumo: 'Distribuição, modelo do funil, motivos de perda, links rastreáveis, integrações, conexão com o Claude e avisos.',
    telas: [TELAS.configuracoes, TELAS.distribuicao, TELAS.motivos, TELAS.links, TELAS.integracoes, TELAS.claude],
    sinonimos: ['configuração', 'distribuição', 'percentual', 'motivo', 'link rastreável', 'sck', 'utm', 'integração', 'ajustes', 'hotmart', 'reprocessar', 'claude', 'mcp', 'token'],
    paraQue: [
      'Onde o gestor ajusta as regras do Comercial. O vendedor vê tudo, só para ler (menos as próprias preferências de aviso e os próprios tokens do Claude).',
    ],
    naTela: [
      '**Distribuição:** quem recebe lead e o percentual de cada um. Simulador dos próximos 10 leads sem dono.',
      '**Modelo do funil:** etapas, prazos, critérios e campos obrigatórios. "Editar funis" leva ao Funil.',
      '**Motivos de perda:** os 9 de fábrica e os criados pelo gestor.',
      '**Links rastreáveis:** os links de cada vendedor, com o código de rastreio.',
      '**Integrações:** o que cada uma traz e leva, e a situação dela. O gestor vê também o painel da Hotmart: ligada ou não, último evento, o que aconteceu com cada evento, os erros e as ofertas vendidas fora do catálogo.',
      '**Conectar ao Claude:** gere um token pessoal e conecte o Claude Code ou o Claude Desktop ao CRM. O Claude vê o que você vê, com as mesmas regras da tela.',
      '**Notificações:** os seus avisos (cada pessoa ajusta os próprios).',
    ],
    comoFazer: [
      {
        titulo: 'Como criar o seu link rastreável',
        itens: [
          'Abra **Configurações › Links rastreáveis**.',
          'Em "Novo link", escolha produto, ação e canal (WhatsApp, ligação, e-mail, Instagram, grupo).',
          'Confira a prévia do código e clique em **"Criar link"**.',
          'Use o botão **"Copiar"** na lista. Cada vendedor usa os próprios links.',
        ],
      },
      {
        titulo: 'Como conectar o Claude ao CRM',
        itens: [
          'Abra **Configurações › Conectar ao Claude**.',
          'Em "Novo token", dê um nome (ex.: "Claude Code notebook"), escolha "Só leitura" ou "Ler e operar" e a validade.',
          'Clique em **"Gerar token"** e copie na hora: ele não aparece de novo.',
          'Em "Como conectar", copie o comando do Claude Code ou o trecho do Claude Desktop (já vem com o seu token).',
          'Teste pedindo ao Claude: "liste os funis do comercial". Token que não usa mais: **"Revogar"**.',
        ],
      },
    ],
    soGestor: [
      '**Distribuição:** ligue ou desligue quem recebe e ajuste os percentuais. A soma dos ativos tem de dar 100%. Clique em "Salvar".',
      '**Motivos:** "Novo motivo", editar, desativar e reativar. Cada motivo pode voltar para reativação, mandar para a lista de bloqueio ou avisar o gestor. Nos 9 de fábrica, só a nota e o ativo mudam.',
      'O gestor cria link para qualquer vendedor.',
      '**Hotmart:** escolha o período (24 h a 90 dias). Em cada erro, **"Reprocessar"** refaz o evento com a regra atual. Só funciona com a integração ligada.',
      '**Tokens do time:** o gestor vê os tokens de todos e revoga qualquer um.',
    ],
    dicas: [
      'Motivo desativado sai da lista de escolha, mas o histórico continua com ele.',
      'Vendedor ausente sai da distribuição antes das 9h.',
    ],
    cuidados: [
      'Contato com dono mantém o dono. A distribuição só vale para quem não tem.',
      'Troca de dono é só pelo gestor, sempre com motivo.',
      'Token do Claude é como senha: quem tem age no CRM como você. Não mande no Slack. Perdeu? Revogue e gere outro.',
      'Aviso "O MCP do Comercial está desligado": nenhum token conecta e não dá para gerar novo. Quem liga é o responsável pelo sistema.',
    ],
    emBreve: [
      { titulo: 'Integrações ligadas', texto: 'WhatsApp oficial (Infobip, Unnichat), Manychat, ActiveCampaign, SendFlow e Slack aparecem como "a conectar". A Hotmart já tem painel, mas só cria negócio quando for ligada. O Clint entra só para a migração. Instagram (social selling) vem depois, e o assistente de IA no navegador (claude.ai) e no celular também: hoje ele conecta pelo Claude Code e pelo Claude Desktop.' },
    ],
  }),
  modulo({
    id: 'modulo-notificacoes',
    titulo: 'Notificações (o sino)',
    icone: 'clock',
    resumo: 'Avisos de lead novo, resposta, prazo estourado, venda, ficha para aprovar e atividade chegando.',
    telas: [TELAS.notificacoes],
    sinonimos: ['sino', 'aviso', 'alerta', 'notificação', 'desktop', 'horário de silêncio'],
    paraQue: [
      'O sino fica no topo de toda tela do Comercial. O número vermelho mostra o que você ainda não leu.',
    ],
    naTela: [
      'Lista com até 30 avisos. Clicar leva ao negócio ou à conversa.',
      '"Marcar todas como lidas" e o link "Preferências".',
    ],
    extra: [
      tab(['Aviso', 'Leva para'], [
        ['Lead novo atribuído a mim', 'Funil'],
        ['Lead respondeu no WhatsApp', 'Conversas'],
        ['Prazo da etapa estourado', 'Funil'],
        ['Venda aprovada na Hotmart', 'Funil'],
        ['Ficha de disparo para aprovar (gestor)', 'Disparos'],
        ['Atividade vence em 30 minutos', 'Atividades'],
      ], 'O que avisa'),
    ],
    comoFazer: [
      {
        titulo: 'Como ligar o aviso no computador',
        itens: [
          'Abra **Configurações › Notificações** (ou "Preferências" no sino).',
          'Ligue **"Aviso no desktop"** e clique em **"Permitir neste computador"**.',
          'Clique em **"Enviar notificação de teste"** para conferir.',
          'Escolha o que avisa e, se quiser, um horário de silêncio. Clique em **"Salvar"**.',
        ],
      },
    ],
    dicas: [
      'O sino sempre mostra tudo. As preferências valem para o aviso no computador.',
      'Sem permissão do navegador, o aviso aparece no canto da tela por alguns segundos.',
    ],
    cuidados: [
      'Bloqueou no navegador? Libere nas configurações do navegador para este site. A tela mostra como.',
    ],
  }),
  {
    id: 'modulo-social-selling',
    titulo: 'Social selling',
    parte: 'modulos',
    icone: 'share',
    emBreve: true,
    resumo: 'Comentários do Instagram viram lead com um clique.',
    sinonimos: ['instagram', 'comentário', 'rede social'],
    ferramentas: [TELAS.socialSelling],
    blocos: [
      emBreve('Ainda não existe', 'A ideia: conectar os perfis do Instagram (Marcio, Elaine e outros), ler os comentários e cadastrar quem comenta como lead, com um clique. Hoje a tela só mostra "Em breve".'),
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Comece aqui
// ─────────────────────────────────────────────────────────────────────────────

const COMECE: SecaoAjuda[] = [
  {
    id: 'bem-vindo',
    titulo: 'Bem-vindo à central de ajuda',
    parte: 'comece',
    icone: 'wave',
    resumo: 'O que tem aqui e como achar rápido.',
    sinonimos: ['ajuda', 'como usar', 'onde fica'],
    blocos: [
      p('Aqui está **tudo o que o Comercial precisa para trabalhar**: como usar cada tela do sistema e o playbook de vendas com as regras, os scripts e os processos.'),
      passos('Três jeitos de achar o que precisa', [
        '**Busque** no topo. Escreva do seu jeito: "como mover negócio", "motivo de perda", "tá caro". Enter abre o primeiro resultado.',
        '**Navegue** pelas seis partes, nos cartões acima ou no sumário ao lado.',
        '**Mande o link.** Cada assunto tem endereço próprio. Copie o endereço da página com o assunto aberto e cole no Slack.',
      ]),
      atalhos([
        { rotulo: 'Primeiro dia do vendedor', href: '#primeiro-dia-vendedor', texto: 'O que abrir, em que ordem, e como fechar o dia.', icone: 'user' },
        { rotulo: 'Primeiro dia do gestor', href: '#primeiro-dia-gestor', texto: 'Conferência das 9h, distribuição, aprovações e equipe.', icone: 'user-check' },
        { rotulo: 'O mapa do sistema', href: '#mapa-do-sistema', texto: 'Todas as telas do Comercial, numa olhada.', icone: 'dashboard' },
        { rotulo: 'Os 9 inegociáveis', href: '#inegociaveis', texto: 'As regras que valem para todo mundo, sem exceção.', icone: 'lock' },
      ]),
    ],
  },
  {
    id: 'primeiro-dia-vendedor',
    titulo: 'Primeiro dia do vendedor',
    parte: 'comece',
    icone: 'user',
    resumo: 'O roteiro do dia no sistema, da chegada ao fechamento das 18h45.',
    sinonimos: ['vendedor novo', 'onboarding', 'começar', 'rotina do vendedor', 'meu dia'],
    blocos: [
      passos('Ao chegar', [
        'Abra o **Início** ("Meu dia"). Veja seus números e a lista **Agir agora**.',
        'Participe da daily das 9h (15 minutos, com o CRM aberto).',
        'Trabalhe o **Agir agora** de cima para baixo: atrasado, agora, hoje.',
      ]),
      passos('Durante o dia', [
        '**Conversas › Minhas:** responda primeiro quem espera há mais tempo. O prazo é 15 minutos em horário comercial.',
        '**Atividades › Hoje:** faça os toques do dia. Ao concluir, agende o próximo passo.',
        '**Funil › Meus negócios:** mova os negócios que avançaram, com os campos preenchidos.',
        'Antes de falar com alguém fora da sua fila, busque em **Contatos**. Se tem dono e não é você, não toque.',
        'Vai mandar link de pagamento? Pegue em **Produtos › O que vender hoje**.',
      ]),
      passos('Para fechar o dia', [
        'Até as **18h45**: zero atividades atrasadas e nenhum negócio sem próximo passo.',
        'Confira em **Relatórios › Fechamento do dia** se os seus números batem.',
        'Às 19h o fechamento sai no #comercial.',
      ]),
      atalhos([
        { rotulo: 'Início', href: TELAS.inicio.href, texto: 'Meu dia e Agir agora.', icone: 'home' },
        { rotulo: 'Conversas', href: TELAS.conversas.href, texto: 'Quem está esperando resposta.', icone: 'message' },
        { rotulo: 'Atividades', href: TELAS.atividades.href, texto: 'A agenda de toques.', icone: 'list-checks' },
        { rotulo: 'Funil', href: TELAS.funil.href, texto: 'Seus negócios por etapa.', icone: 'kanban' },
      ]),
      dicas([
        'Leia também os **9 inegociáveis** e a **distribuição dos leads**, no playbook.',
        'O (i) ao lado de cada número explica a conta.',
      ]),
    ],
  },
  {
    id: 'primeiro-dia-gestor',
    titulo: 'Primeiro dia do gestor',
    parte: 'comece',
    icone: 'user-check',
    resumo: 'Conferência das 9h, distribuição, aprovações, funis e acompanhamento do time.',
    sinonimos: ['gestor', 'gerente', 'líder', 'coordenador', 'rotina do gestor', 'visão do time'],
    blocos: [
      passos('Antes de tudo (uma vez)', [
        '**Configurações › Distribuição:** marque quem recebe lead e os percentuais. A soma tem de dar 100%.',
        '**Configurações › Motivos de perda:** confira os 9 de fábrica e as notas que o vendedor lê na hora de escolher.',
        '**Produtos e ofertas:** vincule os produtos e marque a oferta vigente de cada um, com a condição escrita.',
        '**Funil:** para cada projeto novo, use **"Comecei um novo projeto"**.',
      ]),
      passos('Todo dia, às 9h', [
        'Abra o **Início** ("Visão do time") e o **Controle das 9h**. As quatro listas devem estar zeradas.',
        'Negócio sem dono: atribua. Perdido por "já atendido por outro vendedor": trate hoje.',
        'Veja a **Carga por vendedor**. Clique no nome para ver o painel da pessoa.',
        'Em **Disparos**, aprove ou reprove as fichas que esperam.',
        'Em **Conversas › Sem dono**, atribua quem atende.',
      ]),
      passos('Toda semana', [
        '**Relatórios › Equipe:** ranking e detalhe de cada vendedor para o 1:1.',
        '**Relatórios › Funil:** onde o funil trava e por que se perde.',
        '**Registro:** quem mudou o quê, quando precisar conferir.',
      ]),
      atalhos([
        { rotulo: 'Início · Visão do time', href: TELAS.inicio.href, texto: 'Controle das 9h e carga por vendedor.', icone: 'home' },
        { rotulo: 'Distribuição', href: TELAS.distribuicao.href, texto: 'Quem recebe lead e quanto.', icone: 'sliders' },
        { rotulo: 'Disparos', href: TELAS.disparos.href, texto: 'Fichas para aprovar.', icone: 'send' },
        { rotulo: 'Equipe', href: TELAS.equipe.href, texto: 'Ranking e 1:1.', icone: 'users' },
      ]),
      cuidados([
        'Só o gestor troca dono, sempre com motivo.',
        'O motivo "Já atendido por outro vendedor" mede falha de distribuição. Cada ocorrência se trata no mesmo dia.',
      ]),
    ],
  },
  {
    id: 'atalhos-de-teclado',
    titulo: 'Atalhos que poupam tempo',
    parte: 'comece',
    icone: 'zap',
    resumo: 'Teclas e truques das telas do Comercial.',
    sinonimos: ['teclado', 'atalho', 'tecla', 'rápido'],
    blocos: [
      tab(['Onde', 'Atalho', 'O que faz'], [
        ['Conversas', 'Ctrl + Enter (⌘ + Enter no Mac)', 'Envia a mensagem'],
        ['Conversas', '/ com o campo vazio', 'Abre as respostas rápidas do playbook'],
        ['Dashboards (editando)', 'Ctrl + Z / Ctrl + Shift + Z', 'Desfaz e refaz'],
        ['Dashboards (editando)', 'Setas, Enter, Delete', 'Move, edita e remove o widget selecionado'],
        ['Central de ajuda', 'Enter na busca', 'Abre o primeiro resultado'],
        ['Qualquer número com (i)', 'Clique no (i), Esc fecha', 'Mostra o que é, como conta e a meta'],
        ['Abas de várias telas', 'Setas ← →', 'Troca de aba pelo teclado'],
      ]),
      dicas([
        'Muitas telas guardam a aba no endereço (por exemplo, Relatórios com #equipe). Mande o link e a pessoa cai na aba certa.',
        'Números clicáveis funcionam como filtro: clique de novo para desligar, ou use "Limpar".',
      ]),
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Como o sistema funciona
// ─────────────────────────────────────────────────────────────────────────────

const SISTEMA: SecaoAjuda[] = [
  {
    id: 'mapa-do-sistema',
    titulo: 'O mapa do sistema',
    parte: 'sistema',
    icone: 'dashboard',
    resumo: 'Todas as telas do Comercial, na ordem do menu.',
    sinonimos: ['menu', 'telas', 'onde fica', 'navegação'],
    blocos: [
      p('O menu do Comercial fica na lateral, dentro de qualquer tela do departamento. Clique num cartão para abrir a tela, ou leia a seção dela em "Módulo a módulo".'),
      atalhos([
        { rotulo: 'Início do Comercial', href: TELAS.inicio.href, texto: 'O que fazer agora e os números do dia.', icone: 'home' },
        { rotulo: 'Funil de vendas', href: TELAS.funil.href, texto: 'Negócios por etapa, por produto.', icone: 'kanban' },
        { rotulo: 'Conversas', href: TELAS.conversas.href, texto: 'WhatsApp oficial, ligado ao dono do lead.', icone: 'message' },
        { rotulo: 'Atividades', href: TELAS.atividades.href, texto: 'Agenda do dia, cadência e atrasadas.', icone: 'list-checks' },
        { rotulo: 'Contatos', href: TELAS.contatos.href, texto: 'Pessoas, dono e jornada completa.', icone: 'contact' },
        { rotulo: 'Recuperação', href: TELAS.recuperacao.href, texto: 'Filas pós-lançamento com score de A a D.', icone: 'target' },
        { rotulo: 'Disparos', href: TELAS.disparos.href, texto: 'Ficha, aprovação, supressões e agenda.', icone: 'send' },
        { rotulo: 'Relatórios', href: TELAS.relatorios.href, texto: 'Dashboards, fechamento, funil e equipe.', icone: 'chart' },
        { rotulo: 'Produtos e ofertas', href: TELAS.produtos.href, texto: 'O que vender hoje e o link certo.', icone: 'wallet' },
        { rotulo: 'Registro', href: TELAS.registro.href, texto: 'Tudo o que foi feito no CRM.', icone: 'clipboard' },
        { rotulo: 'Configurações', href: TELAS.configuracoes.href, texto: 'Distribuição, motivos, links e avisos.', icone: 'sliders' },
        { rotulo: 'Social selling (em breve)', href: TELAS.socialSelling.href, texto: 'Comentários do Instagram viram lead.', icone: 'share' },
      ]),
    ],
  },
  {
    id: 'caminho-do-lead',
    titulo: 'O caminho de um lead, do começo ao fim',
    parte: 'sistema',
    icone: 'arrow-right',
    resumo: 'Como uma pessoa entra, ganha dono, vira negócio e termina em ganho ou perda.',
    sinonimos: ['fluxo', 'processo', 'jornada do lead', 'passo a passo', 'como funciona'],
    blocos: [
      passos('As etapas, em ordem', [
        '**A pessoa chega.** Por campanha, pela Hotmart, por pesquisa ou cadastrada à mão. Ela vira um **contato**, uma vez só, reconhecida pelo e-mail ou telefone.',
        '**Ganha um dono.** Se já tinha dono, fica com ele. Se não, a **distribuição** escolhe pelo percentual de cada vendedor.',
        '**Vira negócio.** Um negócio é uma chance de venda de um produto, dentro de um funil. Entra na primeira etapa: "Fazer primeiro contato".',
        '**O dono trabalha.** Conversa, liga e registra tudo. Cada toque é uma **atividade** com data.',
        '**Avança de etapa.** Qualificar, Apresentar a oferta, Negociar, Aguardar pagamento. Cada etapa pede alguns campos preenchidos.',
        '**Termina.** Ganho, quando a Hotmart aprova o pagamento. Ou perdido, com um motivo da lista.',
        '**Fica registrado.** Tudo vai para o **Registro**, os números para os **Relatórios** e a história para a **jornada** do contato.',
      ]),
      p('Uma pessoa pode ter vários negócios ao longo dos lançamentos. Só pode ter **um aberto por funil**.'),
    ],
  },
  {
    id: 'pecas-do-crm',
    titulo: 'As peças: contato, negócio, atividade e funil',
    parte: 'sistema',
    icone: 'list-checks',
    resumo: 'O que é cada coisa no sistema, em uma frase.',
    sinonimos: ['conceitos', 'o que é', 'entidades'],
    blocos: [
      tab(['Peça', 'O que é', 'Onde ver'], [
        ['Contato', 'A pessoa. Aparece uma vez só, com dono, dados e jornada.', 'Contatos'],
        ['Negócio', 'Uma chance de venda de um produto, num funil, numa etapa.', 'Funil e ficha do negócio'],
        ['Atividade', 'Um toque com data: ligação, WhatsApp, e-mail, reunião ou tarefa.', 'Atividades'],
        ['Funil', 'As etapas de um tipo de venda. Manual (venda ativa) ou automático (Hotmart).', 'Funil'],
        ['Agrupador', 'Os funis de um mesmo produto, juntos.', 'Funil › Trocar funil'],
        ['Conversa', 'As mensagens do WhatsApp oficial com a pessoa.', 'Conversas'],
        ['Oferta vigente', 'A condição que o vendedor pode oferecer hoje.', 'Produtos e ofertas'],
        ['Ficha de disparo', 'Os 7 itens de um disparo por API, com aprovação.', 'Disparos'],
      ]),
    ],
  },
  {
    id: 'dono-e-distribuicao',
    titulo: 'Dono do lead e distribuição',
    parte: 'sistema',
    icone: 'user-check',
    resumo: 'Quem fala com quem, e como o sistema escolhe.',
    sinonimos: ['dono', 'distribuição', 'rodízio', 'atribuir', 'sem dono', 'transferir'],
    ferramentas: [TELAS.distribuicao],
    blocos: [
      p('**Todo lead tem um dono só.** É a regra número 1 do playbook, e o sistema foi feito em volta dela.'),
      ul([
        'Contato que já tem dono **mantém o dono** em qualquer negócio novo.',
        'Contato sem dono vai pela **distribuição**: o lead vai para quem está mais abaixo da própria cota. Não é sorteio.',
        'Um funil pode ter distribuição própria. Se não tiver, vale a geral.',
        'Só o **gestor** troca o dono, sempre com motivo. O contato e as atividades abertas vão junto.',
        'Lead sem dono aparece em vermelho e entra no Controle das 9h do gestor.',
      ], 'Como funciona'),
      cuidados([
        'Lead que não é seu não se toca, nem para tirar dúvida. Peça ao gestor para transferir.',
        'Antes de abordar alguém fora da fila, busque em Contatos.',
      ]),
    ],
  },
  {
    id: 'ativacao-padrao',
    titulo: 'Ativação: a primeira jornada do lead',
    parte: 'sistema',
    icone: 'user-check',
    resumo: 'Todo projeto tem um funil de Ativação. Quem se inscreve, compra o ingresso ou vira MQL recebe três toques do mesmo vendedor até o evento.',
    sinonimos: ['ativação', 'ativacao', 'mql', 'toque 1', 'toques', 'acompanhar mql', 'ingresso', 'inscrição', 'comparecimento', 'salvar o número'],
    ferramentas: [TELAS.funil],
    blocos: [
      p('**Todo projeto nasce com o funil de Ativação**, qualquer que seja o tipo. Projeto criado antes: o gestor abre um funil do projeto e clica em **Acrescentar a Ativação**.'),
      p('A pessoa entra sozinha quando se inscreve, compra o ingresso ou responde a pesquisa (quem responde e ainda não está no CRM vira contato novo). Quais listas, tags e produtos valem para cada projeto, e quais tags marcam MQL, é a catalogação de origem, cuidada pelo Victor Hugo. Uma pessoa tem um negócio de ativação por projeto: entrar de novo não duplica. O dono vem pela distribuição, e quem já tem dono continua com ele.'),
      tab(['Toque', 'Quando', 'O que fazer'], [
        ['1. Mensagem', 'Na hora em que a pessoa entra (prazo de 5 minutos; fora do horário, na abertura do próximo expediente: seg a sex 8h–20h, sáb 9h–13h; domingo e feriado fechados)', 'Mensagem curta: recebeu o presente? Salva o meu número, sou eu quem te acompanha.'],
        ['2. Ligação', 'Na sexta anterior ao evento, 10h', 'Cinco blocos: reconexão, contexto, check-in, segurança e compromisso. Não atendeu: mensagem pedindo horário. Sem resposta em 24 horas: desapegar.'],
        ['3. Link no privado', 'Em cada dia do evento, 1 hora antes', 'Mandar o link antes de ele sair no grupo.'],
      ]),
      ul([
        'As atividades dos três toques aparecem sozinhas em Atividades, para o dono. Se o gestor troca o dono, os toques vão junto.',
        'Os textos prontos ficam em **Roteiros**, na faixa da Ativação acima do funil: um clique copia.',
        'Comprou a oferta do evento na Hotmart: o negócio fecha como Comprou, com o mesmo dono.',
        'O carrinho fechou e a pessoa não comprou: no dia seguinte ao fechamento do carrinho (sem ele, ao fim do evento) o negócio vira perdido "Evento encerrado sem compra" e a pessoa entra na fila de recuperação do projeto, com o **mesmo dono**.',
        'As datas do evento vêm do cadastro do Marketing quando o projeto está lá com a mesma chave; senão valem as da Ativação. O fechamento do carrinho fica na Ativação.',
      ], 'Como funciona'),
      cuidados([
        'Só pelo número oficial do comercial. Nunca pelo WhatsApp pessoal.',
        'Nunca mencionar replay.',
        'O teto é de 50 conversas novas por dia por número. A faixa avisa a partir de 40 e quando passa de 50: divida o lote antes do toque 1.',
        'Se a Mensageria tem disparo no projeto no mesmo dia, a faixa avisa: a mesma pessoa não recebe régua e toque no mesmo dia.',
        'Sem a data do evento, só o toque 1 é agendado. O gestor preenche em Configurar.',
      ]),
    ],
  },
  {
    id: 'prazos-e-cores',
    titulo: 'Prazos, cores e sinais de urgência',
    parte: 'sistema',
    icone: 'clock',
    resumo: 'O que o amarelo e o vermelho querem dizer.',
    sinonimos: ['sla', 'prazo', 'atenção', 'crítico', 'vermelho', 'amarelo', 'alerta', 'atrasado'],
    blocos: [
      p('Cada etapa do funil tem dois prazos: **atenção** (amarelo) e **crítico** (vermelho). Eles contam o tempo desde que o negócio entrou na etapa.'),
      tab(['Etapa', 'Atenção', 'Crítico'], [
        ['Fazer primeiro contato', '5 min', '15 min (horário comercial)'],
        ['Qualificar', '24 h', '48 h'],
        ['Apresentar a oferta', '48 h', '72 h'],
        ['Negociar', '72 h', '7 dias'],
        ['Aguardar pagamento', '24 h', '48 h'],
      ], 'Prazos do modelo padrão (o gestor ajusta por funil)'),
      ul([
        '**Vermelho** aparece só quando algo viola a meta: prazo crítico, atividade atrasada, sem próximo passo, sem dono.',
        '**Amarelo** é atenção: ainda dá tempo.',
        'O card do funil mostra **um sinal só**, o mais urgente.',
        'Números em vermelho no topo das telas querem dizer "passou da meta". A meta da maioria é zero.',
      ], 'Como ler'),
    ],
  },
  {
    id: 'vendedor-e-gestor',
    titulo: 'O que muda entre vendedor e gestor',
    parte: 'sistema',
    icone: 'users',
    resumo: 'O que cada papel vê e pode fazer.',
    sinonimos: ['permissão', 'papel', 'acesso', 'pode', 'não consigo', 'bloqueado'],
    blocos: [
      tab(['O quê', 'Vendedor', 'Gestor'], [
        ['Início', '"Meu dia", com os próprios números', '"Visão do time", Controle das 9h e o painel de cada vendedor'],
        ['Conversas', 'Escreve só nas próprias', 'Escreve em qualquer uma e atribui dono'],
        ['Atividades', 'Conclui só as próprias', 'Conclui qualquer uma'],
        ['Negócio de outro vendedor', 'Só lê: a ficha abre sem ações e o card não arrasta', 'Mexe em qualquer um'],
        ['Dono do negócio', 'Não troca (o botão nem aparece)', 'Troca, com motivo'],
        ['Funis', 'Usa', 'Cria, edita, arquiva e começa projeto novo'],
        ['Disparos', 'Envia ficha para aprovação (se opera disparo)', 'Aprova, reprova e registra direto'],
        ['Produtos', 'Consulta e copia links', 'Vincula e marca a oferta vigente'],
        ['Configurações', 'Só leitura (menos os próprios avisos e tokens do Claude)', 'Ajusta tudo e vê o painel da Hotmart'],
        ['Conectar ao Claude', 'Gera e revoga os próprios tokens', 'Vê e revoga os tokens do time'],
        ['Registro', 'O que fez e o que tocou a carteira dele', 'Tudo'],
        ['Dashboards', 'Vê os próprios números', 'Filtra por vendedor e edita qualquer um'],
      ]),
    ],
  },
  {
    id: 'ler-os-numeros',
    titulo: 'Como ler os números (o ícone i)',
    parte: 'sistema',
    icone: 'chart',
    resumo: 'Toda tela tem uma faixa de números no topo, com a definição exata.',
    sinonimos: ['indicador', 'métrica', 'kpi', 'informação', 'definição', 'meta'],
    blocos: [
      ul([
        'Clique no **(i)** ao lado do número. Abre: o que é, como conta, para que serve e a meta.',
        'Alguns números são **clicáveis**: viram filtro da tela. Clique de novo ou em "Limpar" para desligar.',
        'Os números do dia contam de meia-noite até agora, no horário de Brasília.',
        'O mesmo nome quer dizer a mesma conta em todas as telas (Início, Relatórios, Dashboards).',
      ]),
      tab(['Número', 'O que conta'], [
        ['Abordados', 'Pessoas diferentes com ligação ou WhatsApp concluídos no dia'],
        ['Entraram em contato', 'Quem escreveu primeiro, sem ter sido abordado'],
        ['Responderam', 'Negócios que entraram na etapa de qualificação no dia'],
        ['Em negociação', 'Negócios abertos em Negociar ou Aguardar pagamento, agora'],
        ['Vendas e receita', 'Negócios ganhos (pagamento aprovado) no dia'],
      ], 'Os números do fechamento'),
    ],
  },
  {
    id: 'demonstracao',
    titulo: 'Demonstração e implantação: o que já grava',
    parte: 'sistema',
    icone: 'eye',
    resumo: 'Por que aparece "Demonstração · dados fictícios" e o que isso muda.',
    sinonimos: ['demo', 'teste', 'fictício', 'não salvou', 'sumiu', 'ver como', 'fase 2', 'erro ao salvar'],
    blocos: [
      p('O sistema do Comercial está sendo ligado aos poucos. Por isso ele funciona de dois jeitos:'),
      ul([
        '**Demonstração:** aparece a faixa "Demonstração · dados fictícios". As pessoas são inventadas. Tudo funciona, mas **nada fica gravado**: ao recarregar, volta como era.',
        '**Ligado ao banco real:** a gravação só funciona depois que o gestor liberar o CRM para uso. Até lá, ao tentar gravar, aparece "CRM em manutenção: escrita desligada." Isso é esperado, não é erro seu.',
      ]),
      p('Na demonstração, o seletor **"Ver como"** troca a pessoa da tela. Serve para ver o sistema como vendedor ou como gestor. O "x" esconde a faixa nesta sessão.'),
      dicas(['Use a demonstração para treinar: mova, perca, agende e conclua à vontade.']),
    ],
  },
  {
    id: 'o-que-vem-por-ai',
    titulo: 'O que ainda vem por aí',
    parte: 'sistema',
    icone: 'hourglass',
    emBreve: true,
    resumo: 'Funções planejadas que ainda não existem no sistema.',
    sinonimos: ['futuro', 'roadmap', 'próximas fases', 'integração', 'quando'],
    blocos: [
      p('Estas partes estão planejadas. Enquanto não chegam, **não conte com elas**.'),
      emBreve('Gravar no banco', 'Criar, mover, perder, agendar e todas as outras gravações valendo de verdade, com o registro automático de cada mudança.'),
      emBreve('Hotmart automática', 'Carrinho abandonado, cartão recusado e compra aprovada criando e fechando negócios sozinhos. Ganho fechando com o pagamento aprovado.'),
      emBreve('WhatsApp oficial', 'Envio e recebimento de verdade nas Conversas e nos Disparos, pelo número oficial (Infobip ou Unnichat).'),
      emBreve('Outras integrações', 'ActiveCampaign, SendFlow, Manychat, pesquisas e Slack alimentando a jornada e os alertas.'),
      emBreve('Migração do Clint', 'Trazer os negócios e o histórico do Clint para cá. Até lá, o Clint segue sendo o CRM em uso.'),
      emBreve('Assistente de IA do Comercial', 'Perguntar e agir no CRM conversando: buscar pessoa, ver o funil, criar atividade, mover etapa, montar o fechamento do dia.'),
      emBreve('Social selling', 'Comentários do Instagram virando lead com um clique.'),
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Perguntas frequentes
// ─────────────────────────────────────────────────────────────────────────────

const FAQ: SecaoAjuda[] = [
  {
    id: 'faq-negocios',
    titulo: 'Funil e negócios',
    parte: 'faq',
    icone: 'kanban',
    blocos: [
      pergunta('Por que não consigo mover o negócio de etapa?', 'Falta campo obrigatório. A etapa nova pede campos, e as anteriores também contam. O sistema abre a ficha: preencha em "Campos do negócio", salve e mova de novo.', TELAS.funil),
      pergunta('Como marco um negócio como ganho?', 'Você não marca. Ganho é pagamento aprovado na Hotmart. "O lead disse sim" não é ganho. Leve o negócio até "Aguardar pagamento" e espere a aprovação.'),
      pergunta('O sistema marca perdido sozinho quando falta próximo passo?', 'Não. Ele mostra em vermelho ("Sem próximo passo") e o negócio entra nos alertas do dia. Quem agenda o próximo passo, ou marca perdido com motivo, é você.'),
      pergunta('Sumiu um negócio do quadro. Onde está?', 'Negócio perdido não aparece no quadro. Confira também os filtros (dono, busca, números clicáveis). Para achar, abra a ficha do contato, aba Negócios.', TELAS.contatos),
      pergunta('Não consigo criar negócio para um contato. Por quê?', 'Três motivos possíveis: ele já tem negócio aberto nesse funil; ele pediu para não receber contato; ou o funil é automático (só a Hotmart cria nele).'),
      pergunta('Qual motivo de perda eu uso?', 'Um da lista. Leia a nota de cada motivo na hora de escolher. "Não é o momento" e "Sem condição financeira agora" voltam para reativação. "Pediu para não receber contato" manda para a lista de bloqueio.', TELAS.motivos),
    ],
  },
  {
    id: 'faq-contatos',
    titulo: 'Contatos e dono',
    parte: 'faq',
    icone: 'contact',
    blocos: [
      pergunta('Um lead me chamou, mas é de outro vendedor. O que faço?', 'Não responda. Lead que não é seu não se toca. Avise o gestor, que transfere se for o caso.'),
      pergunta('Como sei se uma pessoa já tem dono?', 'Busque em Contatos pelo final do telefone ou pelo e-mail. A coluna Dono mostra.', TELAS.contatos),
      pergunta('Quem troca o dono de um lead?', 'Só o gestor, na ficha do negócio, com motivo registrado. O contato e as atividades abertas vão junto.'),
      pergunta('Apareceu "Possível duplicado". E agora?', 'Quer dizer que outra pessoa tem o mesmo final de telefone. Pode ser a mesma pessoa ou não. Confira antes de abordar e não cadastre de novo.'),
      pergunta('O que é "Não quer contato"?', 'A pessoa pediu para não receber contato. Ela fica fora de disparos, abordagens e negócio novo.'),
    ],
  },
  {
    id: 'faq-conversas',
    titulo: 'Conversas e WhatsApp',
    parte: 'faq',
    icone: 'message',
    blocos: [
      pergunta('Por que não consigo escrever na conversa?', 'Uma destas: o lead é de outro vendedor; o lead está sem dono (o gestor atribui antes); a pessoa pediu para não receber contato; ou o contato não tem telefone. A tela mostra o motivo.'),
      pergunta('O que é a janela de 24 horas?', 'Depois da última mensagem do lead, você tem 24 horas para mandar mensagem livre. Fechou, só sai template aprovado.'),
      pergunta('Posso falar pelo meu WhatsApp pessoal?', 'Não. Só se fala com lead pelos números oficiais do comercial.'),
      pergunta('A mensagem que mandei chegou no lead?', 'Ainda não. O WhatsApp oficial está a conectar. Hoje a caixa de Conversas é de demonstração.'),
    ],
  },
  {
    id: 'faq-atividades',
    titulo: 'Atividades e rotina',
    parte: 'faq',
    icone: 'list-checks',
    blocos: [
      pergunta('Até que horas o CRM tem de estar em dia?', 'Até as 18h45. O fechamento do dia sai às 19h no #comercial.'),
      pergunta('Concluí a atividade e não agendei a próxima. E agora?', 'O negócio ficou sem próximo passo. Abra a ficha e clique em "Próxima atividade", ou use "Agendar agora" no aviso vermelho.'),
      pergunta('Quantas vezes tento falar com quem não responde?', 'Siga a cadência de 5 dias. Depois da proposta, até 5 tentativas cruzando ligação e WhatsApp. Esgotou: perdido com o motivo "Tentativas de contato esgotadas".', TELAS.atividades),
      pergunta('Não consigo concluir a atividade de um colega.', 'É de propósito. Só o dono da atividade (ou o gestor) conclui.'),
    ],
  },
  {
    id: 'faq-vendas',
    titulo: 'Ofertas, links e disparos',
    parte: 'faq',
    icone: 'wallet',
    blocos: [
      pergunta('Onde pego o link de pagamento?', 'Em Produtos e ofertas, aba "O que vender hoje". Copie de lá, nunca de conversa antiga.', TELAS.produtos),
      pergunta('Posso dar um desconto?', 'Só o que está na oferta vigente. Condição fora da oferta não existe. Toda condição especial tem contrapartida, e só a que a oferta prevê.'),
      pergunta('Não sei o preço. O que faço?', 'Não estime. Número na mesa, nunca estimativa. Não sabe, escala (veja a tabela de escalonamento no playbook).'),
      pergunta('Posso fazer um disparo para a minha lista?', 'Só com ficha aprovada e registro no log. Monte a ficha em Disparos e envie para aprovação.', TELAS.disparos),
      pergunta('Por que meu link precisa ser rastreável?', 'Para saber de onde veio cada venda e de qual vendedor. Crie os seus em Configurações › Links rastreáveis.', TELAS.links),
    ],
  },
  {
    id: 'faq-sistema',
    titulo: 'Sistema e acesso',
    parte: 'faq',
    icone: 'settings',
    blocos: [
      pergunta('Apareceu "CRM em manutenção: escrita desligada". Fiz algo errado?', 'Não. O CRM ainda não foi liberado para gravar. Quando o gestor liberar, salvar passa a funcionar normalmente.'),
      pergunta('Mudei algo e sumiu quando recarreguei.', 'Você está na demonstração (faixa "Demonstração · dados fictícios"). Nela nada fica gravado.'),
      pergunta('Quem pode entrar no Comercial?', 'Hoje, só administradores. Quando o sistema estiver ligado ao banco, o acesso passa a ser do time do Comercial (gestor e vendedores).'),
      pergunta('Como paro de receber aviso fora do horário?', 'Em Configurações › Notificações, ligue o horário de silêncio e salve.', TELAS.notificacoes),
      pergunta('Achei um erro ou falta algo aqui na ajuda.', 'Avise o Arthur Galvão. A central é atualizada junto com o sistema.'),
    ],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Glossário do sistema
// ─────────────────────────────────────────────────────────────────────────────

const GLOSSARIO_SISTEMA: SecaoAjuda = {
  id: 'glossario-sistema',
  titulo: 'Termos do sistema',
  parte: 'glossario',
  icone: 'dashboard',
  resumo: 'As palavras que aparecem nas telas do Comercial.',
  blocos: [
    tab(['Termo', 'O que é'], [
      ['Agir agora', 'A lista do Início com o que pede ação, em ordem de urgência'],
      ['Agrupador', 'Os funis de um mesmo produto, juntos'],
      ['Campo obrigatório', 'Dado que uma etapa pede para o negócio entrar nela'],
      ['Carga', 'Quantos negócios abertos e pendências cada vendedor tem agora'],
      ['Contato', 'A pessoa. Aparece uma vez só, reconhecida pelo e-mail ou pelo DDD com os últimos 8 dígitos do telefone'],
      ['Controle das 9h', 'As quatro listas que o gestor confere todo dia, com meta zero'],
      ['Crítico', 'Prazo da etapa estourado (vermelho)'],
      ['Atenção', 'Prazo da etapa chegando ao limite (amarelo)'],
      ['Ativação', 'O funil padrão de todo projeto: os três toques do mesmo vendedor, da entrada até o evento'],
      ['Dashboard', 'Tela de números montada por alguém, com widgets'],
      ['Distribuição', 'A regra que escolhe o dono de quem chega sem dono, pelo percentual de cada vendedor'],
      ['Faixa de números', 'Os números do topo de cada tela, com o (i)'],
      ['Ficha do negócio', 'A gaveta que abre ao clicar num negócio'],
      ['Ficha do contato', 'A gaveta que abre ao clicar numa pessoa, com a jornada'],
      ['Funil manual', 'Funil onde o comercial trabalha e cria negócio à mão'],
      ['Funil automático', 'Funil preenchido pela Hotmart; não se cria negócio à mão'],
      ['Fora do catálogo', 'Código de oferta que apareceu em venda mas não está cadastrado'],
      ['Jornada', 'Tudo o que a pessoa fez com a casa, por lançamento'],
      ['Negócio', 'Uma chance de venda de um produto, num funil'],
      ['Oferta vigente', 'A oferta que o vendedor pode oferecer hoje, com condição e validade'],
      ['Opt-out ("Não quer contato")', 'Pessoa que pediu para não receber contato'],
      ['Pago líquido', 'Compras menos reembolsos e chargebacks'],
      ['Papel da etapa', 'O que a etapa é no playbook (entrada, qualificação, oferta, negociação, pagamento, ganho)'],
      ['Possível duplicado', 'Outro contato com o mesmo final de telefone'],
      ['Projeto', 'Um lançamento ou evento. "Comecei um novo projeto" cria os funis dele de uma vez'],
      ['Registro', 'O log de tudo o que foi feito no CRM'],
      ['Score', 'Nota de 0 a 100 na recuperação; define a faixa A, B, C ou D'],
      ['Sem próximo passo', 'Negócio aberto sem atividade futura com data'],
      ['Sino', 'As notificações, no topo de cada tela'],
      ['Ver como', 'Na demonstração, troca a pessoa da tela para ver como vendedor ou gestor'],
      ['Widget', 'Um cartão ou gráfico dentro de um painel ou dashboard'],
    ]),
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// Tudo junto, na ordem da tela
// ─────────────────────────────────────────────────────────────────────────────

/** Nome do grupo do playbook dentro da parte "Playbook" ("Comece aqui" do playbook vira "Fundamentos"). */
const SUBGRUPO_PLAYBOOK = Object.fromEntries(GRUPOS.map((g) => [g.key, g.key === 'comece' ? 'Fundamentos' : g.titulo]));

const PLAYBOOK: SecaoAjuda[] = SECOES
  .filter((s) => s.id !== 'glossario')
  .map((s) => ({ ...s, parte: 'playbook' as const, subgrupo: SUBGRUPO_PLAYBOOK[s.grupo] }));

const GLOSSARIO_PLAYBOOK: SecaoAjuda[] = SECOES
  .filter((s) => s.id === 'glossario')
  .map((s) => ({ ...s, titulo: 'Termos de vendas (playbook)', parte: 'glossario' as const, icone: 'notebook' }));

export const CENTRAL: SecaoAjuda[] = [
  ...COMECE,
  ...SISTEMA,
  ...MODULOS,
  ...PLAYBOOK,
  ...FAQ,
  GLOSSARIO_SISTEMA,
  ...GLOSSARIO_PLAYBOOK,
];

export function parte(key: ParteKey): Parte {
  return PARTES.find((x) => x.key === key)!;
}

const POR_PARTE = new Map<ParteKey, SecaoAjuda[]>(PARTES.map((x) => [x.key, CENTRAL.filter((s) => s.parte === x.key)]));

export function secoesDaParte(key: ParteKey): SecaoAjuda[] {
  return POR_PARTE.get(key) ?? [];
}

/** Os dois guias em destaque na entrada. */
export const PRIMEIRO_DIA: { id: string; titulo: string; texto: string; icone: string }[] = [
  { id: 'primeiro-dia-vendedor', titulo: 'Sou vendedor: meu primeiro dia', texto: 'O que abrir, em que ordem, e como deixar o CRM em dia até as 18h45.', icone: 'user' },
  { id: 'primeiro-dia-gestor', titulo: 'Sou gestor: meu primeiro dia', texto: 'Distribuição, conferência das 9h, aprovações e acompanhamento do time.', icone: 'user-check' },
];

/** Atalhos de busca na entrada (o que mais se pergunta). */
export const BUSCAS_SUGERIDAS = ['mover etapa', 'motivo de perda', 'próximo passo', 'janela de 24 horas', 'oferta vigente', 'disparo', 'objeção', 'fechamento do dia'];
